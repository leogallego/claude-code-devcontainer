#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

PROXY_PORT=8888
TINYPROXY_CONF="/etc/tinyproxy/tinyproxy.conf"
TINYPROXY_LOG="/var/log/tinyproxy/tinyproxy.log"

if [ "${1:-}" = "--disable" ]; then
    echo "Disabling proxy sandbox..."
    pkill tinyproxy 2>/dev/null || true
    nft flush ruleset 2>/dev/null || true
    echo "Proxy sandbox disabled — all traffic allowed"
    exit 0
fi

if [ "${1:-}" = "--status" ]; then
    echo "=== Tinyproxy ==="
    if pgrep -x tinyproxy >/dev/null 2>&1; then
        echo "Status: running (PID $(pgrep -x tinyproxy | head -1))"
        echo "Log (last 10 lines):"
        tail -10 "$TINYPROXY_LOG" 2>/dev/null || echo "  (no log file)"
    else
        echo "Status: not running"
    fi
    echo ""
    echo "=== nftables ==="
    nft list ruleset 2>/dev/null || echo "No nftables rules"
    exit 0
fi

echo "Setting up proxy sandbox..."

# Ensure log directory exists
mkdir -p /var/log/tinyproxy
chown tinyproxy:tinyproxy /var/log/tinyproxy

# Stop any existing tinyproxy
pkill tinyproxy 2>/dev/null || true
sleep 0.5

# Start tinyproxy
echo "Starting tinyproxy on 127.0.0.1:${PROXY_PORT}..."
tinyproxy -c "$TINYPROXY_CONF"

# Verify tinyproxy is running
sleep 0.5
if ! pgrep -x tinyproxy >/dev/null; then
    echo "ERROR: tinyproxy failed to start"
    cat "$TINYPROXY_LOG" 2>/dev/null || true
    exit 1
fi
echo "Tinyproxy started (PID $(pgrep -x tinyproxy | head -1))"

# === Apply nftables rules ===
echo "Applying nftables rules..."

# Detect host network
HOST_IP=$(ip route | awk '/default/{print $3}')
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi
HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network: $HOST_NETWORK"

nft flush ruleset 2>/dev/null || true

nft add table inet proxy_sandbox

# --- Input chain ---
nft add chain inet proxy_sandbox input '{ type filter hook input priority 0 ; policy drop ; }'
nft add rule inet proxy_sandbox input iif lo accept
nft add rule inet proxy_sandbox input ct state established,related accept
nft add rule inet proxy_sandbox input ip saddr "$HOST_NETWORK" accept
while IFS= read -r net; do
    [ -z "$net" ] && continue
    nft add rule inet proxy_sandbox input ip saddr "$net" accept
done < <(ip route | awk '!/default/ && /^[0-9]/{print $1}')
while IFS= read -r dns_ip; do
    [ -z "$dns_ip" ] && continue
    nft add rule inet proxy_sandbox input ip saddr "$dns_ip" accept
done < <(awk '/^nameserver/{print $2}' /etc/resolv.conf | grep -E '^[0-9]+\.')

# --- Forward chain ---
nft add chain inet proxy_sandbox forward '{ type filter hook forward priority 0 ; policy drop ; }'

# --- Output chain ---
nft add chain inet proxy_sandbox output '{ type filter hook output priority 0 ; policy drop ; }'
nft add rule inet proxy_sandbox output oif lo accept
nft add rule inet proxy_sandbox output udp dport 53 accept
nft add rule inet proxy_sandbox output tcp dport 53 accept
nft add rule inet proxy_sandbox output ct state established,related accept
nft add rule inet proxy_sandbox output ip daddr "$HOST_NETWORK" accept
while IFS= read -r net; do
    [ -z "$net" ] && continue
    nft add rule inet proxy_sandbox output ip daddr "$net" accept
done < <(ip route | awk '!/default/ && /^[0-9]/{print $1}')
nft add rule inet proxy_sandbox output skuid tinyproxy tcp dport '{80, 443}' accept
nft add rule inet proxy_sandbox output log prefix '"PROXY_BLOCKED: "' counter reject with icmp type admin-prohibited

echo "nftables rules applied"

# === Verification ===
echo "Verifying proxy sandbox..."

if curl --proxy "http://127.0.0.1:${PROXY_PORT}" --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Verification failed — proxy allowed https://example.com"
    exit 1
else
    echo "PASS: proxy correctly blocked https://example.com"
fi

if ! curl --proxy "http://127.0.0.1:${PROXY_PORT}" --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Verification failed — proxy blocked https://api.github.com"
    exit 1
else
    echo "PASS: proxy correctly allowed https://api.github.com"
fi

if curl --noproxy '*' --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Verification failed — direct connection bypassed nftables"
    exit 1
else
    echo "PASS: nftables correctly blocked direct connection"
fi

echo "Proxy sandbox active — all traffic routed through tinyproxy on 127.0.0.1:${PROXY_PORT}"
