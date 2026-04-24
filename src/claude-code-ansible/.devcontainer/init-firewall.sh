#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

if [ "${1:-}" = "--disable" ]; then
    echo "Disabling firewall..."
    nft flush ruleset 2>/dev/null || { iptables -F; iptables -P INPUT ACCEPT; iptables -P OUTPUT ACCEPT; iptables -P FORWARD ACCEPT; }
    echo "Firewall disabled — all traffic allowed"
    exit 0
fi

if [ "${1:-}" = "--status" ]; then
    if [ -f /run/.containerenv ] || [ "${container:-}" = "podman" ]; then
        nft list ruleset 2>/dev/null || echo "No nftables rules"
    else
        iptables -L -n 2>/dev/null || echo "No iptables rules"
    fi
    exit 0
fi

RUNTIME="docker"
if [ "${container:-}" = "podman" ] || [ "${container:-}" = "oci" ] || \
   [ -f /run/.containerenv ]; then
    RUNTIME="podman"
fi
echo "Container runtime: $RUNTIME"

if [ "$RUNTIME" = "podman" ] && ! command -v nft >/dev/null 2>&1; then
    echo "Installing nftables (iptables-nft is not enforced under pasta)..."
    dnf install -y -q nftables >/dev/null 2>&1
fi

# === Collect allowed IPs while network is unrestricted ===

ALLOWED_ENTRIES=()

echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi

if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: GitHub API response missing required fields"
    exit 1
fi

echo "Processing GitHub IPs..."
while read -r cidr; do
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
        exit 1
    fi
    echo "Adding GitHub range $cidr"
    ALLOWED_ENTRIES+=("$cidr")
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

VERTEX_REGION=$(cat /tmp/.cloud_ml_region 2>/dev/null || echo "")
if [ -n "$VERTEX_REGION" ]; then
    echo "Fetching Google Cloud IP ranges for Vertex AI (region: $VERTEX_REGION)..."
    gcloud_ranges=$(curl -s https://www.gstatic.com/ipranges/cloud.json)
    if [ -z "$gcloud_ranges" ]; then
        echo "WARNING: Failed to fetch Google Cloud IP ranges"
    else
        while read -r cidr; do
            echo "Adding Google Cloud range $cidr"
            ALLOWED_ENTRIES+=("$cidr")
        done < <(echo "$gcloud_ranges" | jq -r --arg region "$VERTEX_REGION" \
            '.prefixes[] | select(.ipv4Prefix and (.scope | test("global|" + $region))) | .ipv4Prefix')
    fi

fi

REQUIRED_DOMAINS=(
    "registry.npmjs.org"
    "api.anthropic.com"
    "sentry.io"
    "statsig.anthropic.com"
    "statsig.com"
    "marketplace.visualstudio.com"
    "vscode.blob.core.windows.net"
    "update.code.visualstudio.com"
)

OPTIONAL_DOMAINS=(
    # VS Code official (code.visualstudio.com/docs/setup/network)
    "vsmarketplacebadges.dev"
    "default.exp-tas.com"
    "vscode.download.prss.microsoft.com"
    "download.visualstudio.microsoft.com"
    # Wildcard CDN — resolve a known subdomain to get the CDN IPs
    # *.gallery.vsassets.io (extension downloads)
    "redhat.gallery.vsassets.io"
    # *.gallerycdn.vsassets.io (extension assets)
    "redhat.gallerycdn.vsassets.io"
    # *.vscode-cdn.net (VS Code CDN)
    "vscode.vscode-cdn.net"
    # *.vscode-unpkg.net (web extensions)
    "openvsxorg.vscode-unpkg.net"
    # Google OAuth (token refresh for Vertex AI)
    "oauth2.googleapis.com"
    # Python extension — pypi.org
    "pypi.org"
    "files.pythonhosted.org"
    # YAML extension — schema store
    "www.schemastore.org"
    "json.schemastore.org"
)

resolve_domain() {
    local domain="$1"
    local required="$2"
    echo "Resolving $domain..."
    local ips
    ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
    if [ -z "$ips" ]; then
        ips=$(dig +noall +answer CNAME "$domain" | awk '{print $NF}' | while read -r cname; do
            dig +noall +answer A "$cname" | awk '$4 == "A" {print $5}'
        done)
    fi
    if [ -z "$ips" ]; then
        if [ "$required" = "true" ]; then
            echo "ERROR: Failed to resolve $domain"
            exit 1
        else
            echo "WARNING: Failed to resolve $domain (optional, skipping)"
            return
        fi
    fi

    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            if [ "$required" = "true" ]; then
                echo "ERROR: Invalid IP from DNS for $domain: $ip"
                exit 1
            else
                echo "WARNING: Invalid IP from DNS for $domain: $ip (skipping)"
                continue
            fi
        fi
        echo "Adding $ip for $domain"
        ALLOWED_ENTRIES+=("$ip")
    done < <(echo "$ips")
}

for domain in "${REQUIRED_DOMAINS[@]}"; do
    resolve_domain "$domain" true
done

for domain in "${OPTIONAL_DOMAINS[@]}"; do
    resolve_domain "$domain" false
done

HOST_IP=$(ip route | awk '/default/{print $3}')
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi
HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"

# === Set up firewall ===

if [ "$RUNTIME" = "podman" ]; then
    echo "Setting up nftables firewall (Podman)..."

    nft flush ruleset 2>/dev/null || true

    nft add table inet firewall
    nft add set inet firewall allowed_domains '{ type ipv4_addr ; flags interval ; auto-merge ; }'

    readarray -t UNIQUE_ENTRIES < <(printf '%s\n' "${ALLOWED_ENTRIES[@]}" | sort -u)
    elements=""
    for entry in "${UNIQUE_ENTRIES[@]}"; do
        elements+="${elements:+, }${entry}"
    done
    if [ -n "$elements" ]; then
        nft add element inet firewall allowed_domains "{ ${elements} }"
    fi

    # Input chain
    nft add chain inet firewall input '{ type filter hook input priority 0 ; policy drop ; }'
    nft add rule inet firewall input iif lo accept
    nft add rule inet firewall input udp sport 53 accept
    nft add rule inet firewall input tcp sport 53 ct state established accept
    nft add rule inet firewall input tcp sport 22 ct state established accept

    while IFS= read -r dns_ip; do
        [ -z "$dns_ip" ] && continue
        echo "Allowing DNS server: $dns_ip"
        nft add rule inet firewall input ip saddr "$dns_ip" accept
    done < <(awk '/^nameserver/{print $2}' /etc/resolv.conf | grep -E '^[0-9]+\.')

    nft add rule inet firewall input ip saddr "$HOST_NETWORK" accept

    while IFS= read -r net; do
        [ -z "$net" ] && continue
        echo "Allowing Podman network: $net"
        nft add rule inet firewall input ip saddr "$net" accept
    done < <(ip route | awk '!/default/ && /^[0-9]/{print $1}')

    nft add rule inet firewall input ct state established,related accept

    # Forward chain
    nft add chain inet firewall forward '{ type filter hook forward priority 0 ; policy drop ; }'

    # Output chain
    nft add chain inet firewall output '{ type filter hook output priority 0 ; policy drop ; }'
    nft add rule inet firewall output oif lo accept
    nft add rule inet firewall output udp dport 53 accept
    nft add rule inet firewall output tcp dport 53 accept
    nft add rule inet firewall output tcp dport 22 accept

    while IFS= read -r dns_ip; do
        [ -z "$dns_ip" ] && continue
        nft add rule inet firewall output ip daddr "$dns_ip" accept
    done < <(awk '/^nameserver/{print $2}' /etc/resolv.conf | grep -E '^[0-9]+\.')

    nft add rule inet firewall output ip daddr "$HOST_NETWORK" accept

    while IFS= read -r net; do
        [ -z "$net" ] && continue
        nft add rule inet firewall output ip daddr "$net" accept
    done < <(ip route | awk '!/default/ && /^[0-9]/{print $1}')

    nft add rule inet firewall output ct state established,related accept
    nft add rule inet firewall output ip daddr @allowed_domains accept
    nft add rule inet firewall output log prefix '"BLOCKED: "' counter reject with icmp type admin-prohibited

else
    echo "Setting up iptables firewall (Docker)..."

    DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    ipset destroy allowed-domains 2>/dev/null || true

    if [ -n "$DOCKER_DNS_RULES" ]; then
        echo "Restoring Docker DNS rules..."
        iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
        iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
        echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
    fi

    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -p udp --sport 53 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    ipset create allowed-domains hash:net
    readarray -t UNIQUE_ENTRIES < <(printf '%s\n' "${ALLOWED_ENTRIES[@]}" | sort -u)
    for entry in "${UNIQUE_ENTRIES[@]}"; do
        ipset add allowed-domains "$entry"
    done

    iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
    iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT DROP

    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT
    iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited
fi

echo "Firewall configuration complete"

echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
    exit 1
else
    echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi
