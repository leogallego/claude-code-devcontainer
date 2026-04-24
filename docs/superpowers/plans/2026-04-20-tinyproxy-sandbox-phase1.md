# Tinyproxy + nftables Sandbox (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace IP-based firewall with Tinyproxy domain-filtering proxy + simple static nftables rules for both devcontainers (ansible/Fedora and claude/Debian).

**Architecture:** Tinyproxy listens on `127.0.0.1:8888` and filters HTTPS CONNECT requests by domain regex. nftables enforces that all outbound traffic goes through the proxy (allow loopback + DNS, block everything else). The `init-firewall.sh` scripts remain as a fallback option. Proxy follows same opt-in/opt-out pattern as the existing firewall: enabled by default for claude devcontainer, disabled by default for ansible devcontainer.

**Tech Stack:** Tinyproxy 1.11.x, nftables, bash, devcontainer.json

**Issue:** https://github.com/leogallego/claude-code-devcontainer/issues/2

---

## File Structure

### New files (6)
| File | Responsibility |
|------|---------------|
| `.devcontainer/ansible/proxy-allowlist.txt` | Domain regex patterns for Tinyproxy filter (Fedora) |
| `.devcontainer/ansible/tinyproxy.conf` | Tinyproxy configuration (Fedora) |
| `.devcontainer/ansible/init-proxy.sh` | Startup script: start tinyproxy, apply nftables (Fedora/dnf) |
| `.devcontainer/claude/proxy-allowlist.txt` | Domain regex patterns for Tinyproxy filter (Debian) |
| `.devcontainer/claude/tinyproxy.conf` | Tinyproxy configuration (Debian) |
| `.devcontainer/claude/init-proxy.sh` | Startup script: start tinyproxy, apply nftables (Debian/apt) |

### Modified files (4)
| File | Changes |
|------|---------|
| `.devcontainer/ansible/Dockerfile` | Install tinyproxy, copy config files, add sudoers entry for init-proxy.sh |
| `.devcontainer/ansible/devcontainer.json` | Add HTTP_PROXY/HTTPS_PROXY/NO_PROXY env vars, update postAttachCommand |
| `.devcontainer/claude/Dockerfile` | Install tinyproxy + nftables, copy config files, add sudoers entry for init-proxy.sh |
| `.devcontainer/claude/devcontainer.json` | Add HTTP_PROXY/HTTPS_PROXY/NO_PROXY env vars, update postStartCommand |

### Unchanged files (kept as fallback)
| File | Note |
|------|------|
| `.devcontainer/ansible/init-firewall.sh` | Remains as alternative — no changes |
| `.devcontainer/claude/init-firewall.sh` | Remains as alternative — no changes |

---

## Design Decisions

**Tinyproxy user:** On both Fedora and Debian, the `tinyproxy` package creates a `tinyproxy` system user. The nftables output rules use `skuid tinyproxy` to allow only the tinyproxy process to make outbound HTTP/HTTPS connections. All other processes must go through the proxy.

**nftables on both platforms:** The existing init-firewall.sh uses iptables for Docker and nftables for Podman. For the proxy approach, we standardize on nftables for both — it's simpler (static rules, no ipset) and both Dockerfiles can install it. The iptables fallback remains in init-firewall.sh.

**Shared allowlist content:** Both proxy-allowlist.txt files have identical content. They're separate files (not symlinked) to keep each devcontainer self-contained, matching the existing pattern where init-firewall.sh is duplicated.

**NO_PROXY:** Set to `localhost,127.0.0.1` so local services (language servers, dev servers) aren't routed through the proxy.

**ConnectPort:** Tinyproxy's `ConnectPort` restricts which ports CONNECT can tunnel to. We allow 443 (HTTPS) and 80 (HTTP). This prevents the proxy from being used to tunnel arbitrary protocols.

---

## Task 1: Create domain allowlist files

**Files:**
- Create: `.devcontainer/ansible/proxy-allowlist.txt`
- Create: `.devcontainer/claude/proxy-allowlist.txt`

Both files have identical content — the domain regex patterns from the issue.

- [ ] **Step 1: Create ansible proxy-allowlist.txt**

```
# Claude Code
api\.anthropic\.com
sentry\.io
statsig\.anthropic\.com
statsig\.com

# GitHub
github\.com
api\.github\.com
.*\.githubusercontent\.com

# npm
registry\.npmjs\.org

# VS Code marketplace and CDN
marketplace\.visualstudio\.com
vscode\.blob\.core\.windows\.net
update\.code\.visualstudio\.com
.*\.gallery\.vsassets\.io
.*\.gallerycdn\.vsassets\.io
.*\.vscode-cdn\.net
.*\.vscode-unpkg\.net

# Python (pip)
pypi\.org
files\.pythonhosted\.org

# Vertex AI (optional — needed if using Google Cloud)
oauth2\.googleapis\.com
.*-aiplatform\.googleapis\.com
```

Write this to `.devcontainer/ansible/proxy-allowlist.txt`.

- [ ] **Step 2: Create claude proxy-allowlist.txt**

Copy the identical content to `.devcontainer/claude/proxy-allowlist.txt`.

- [ ] **Step 3: Commit**

```bash
git add .devcontainer/ansible/proxy-allowlist.txt .devcontainer/claude/proxy-allowlist.txt
git commit -m "feat: add domain allowlist files for tinyproxy filtering

Part of issue #2 — Phase 1: Tinyproxy + nftables sandbox."
```

---

## Task 2: Create Tinyproxy configuration files

**Files:**
- Create: `.devcontainer/ansible/tinyproxy.conf`
- Create: `.devcontainer/claude/tinyproxy.conf`

The configs differ only in the `Group` directive (Fedora uses `tinyproxy`, Debian uses `tinyproxy` too — the package creates the group on both, but we verify this).

- [ ] **Step 1: Create ansible tinyproxy.conf (Fedora)**

```
User tinyproxy
Group tinyproxy

Port 8888
Listen 127.0.0.1

Timeout 600
MaxClients 100

Filter "/etc/tinyproxy/allowlist"
FilterDefaultDeny Yes
FilterURLs Off
FilterCaseSensitive Off
FilterExtended On

ConnectPort 443
ConnectPort 80

LogFile "/var/log/tinyproxy/tinyproxy.log"
LogLevel Info

DisableViaHeader Yes
```

Write this to `.devcontainer/ansible/tinyproxy.conf`.

- [ ] **Step 2: Create claude tinyproxy.conf (Debian)**

Identical content to ansible version. Write to `.devcontainer/claude/tinyproxy.conf`.

- [ ] **Step 3: Commit**

```bash
git add .devcontainer/ansible/tinyproxy.conf .devcontainer/claude/tinyproxy.conf
git commit -m "feat: add tinyproxy configuration files

Configures tinyproxy to listen on 127.0.0.1:8888 with
FilterDefaultDeny to block all domains not in the allowlist.

Part of issue #2 — Phase 1."
```

---

## Task 3: Create init-proxy.sh for ansible (Fedora)

**Files:**
- Create: `.devcontainer/ansible/init-proxy.sh`

This script handles: starting tinyproxy, applying nftables rules, verification, --disable, and --status.

- [ ] **Step 1: Create init-proxy.sh**

```bash
#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

PROXY_PORT=8888
TINYPROXY_CONF="/etc/tinyproxy/tinyproxy.conf"
TINYPROXY_LOG="/var/log/tinyproxy/tinyproxy.log"

if [ "${1:-}" = "--disable" ]; then
    echo "Disabling proxy sandbox..."
    # Stop tinyproxy
    pkill tinyproxy 2>/dev/null || true
    # Flush nftables rules
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
# Allow DNS responses
nft add rule inet proxy_sandbox input udp sport 53 accept
# Allow host network (VS Code, devcontainer communication)
nft add rule inet proxy_sandbox input ip saddr "$HOST_NETWORK" accept
# Allow container networks
while IFS= read -r net; do
    [ -z "$net" ] && continue
    nft add rule inet proxy_sandbox input ip saddr "$net" accept
done < <(ip route | awk '!/default/ && /^[0-9]/{print $1}')
# Allow DNS servers
while IFS= read -r dns_ip; do
    [ -z "$dns_ip" ] && continue
    nft add rule inet proxy_sandbox input ip saddr "$dns_ip" accept
done < <(awk '/^nameserver/{print $2}' /etc/resolv.conf | grep -E '^[0-9]+\.')

# --- Forward chain ---
nft add chain inet proxy_sandbox forward '{ type filter hook forward priority 0 ; policy drop ; }'

# --- Output chain ---
nft add chain inet proxy_sandbox output '{ type filter hook output priority 0 ; policy drop ; }'
# Allow loopback (processes connect to proxy on localhost)
nft add rule inet proxy_sandbox output oif lo accept
# Allow DNS (tinyproxy needs to resolve domains)
nft add rule inet proxy_sandbox output udp dport 53 accept
nft add rule inet proxy_sandbox output tcp dport 53 accept
# Allow established connections
nft add rule inet proxy_sandbox output ct state established,related accept
# Allow host network
nft add rule inet proxy_sandbox output ip daddr "$HOST_NETWORK" accept
# Allow container networks
while IFS= read -r net; do
    [ -z "$net" ] && continue
    nft add rule inet proxy_sandbox output ip daddr "$net" accept
done < <(ip route | awk '!/default/ && /^[0-9]/{print $1}')
# Allow tinyproxy user to make outbound HTTP/HTTPS connections
nft add rule inet proxy_sandbox output skuid tinyproxy tcp dport '{80, 443}' accept
# Log and reject everything else
nft add rule inet proxy_sandbox output log prefix '"PROXY_BLOCKED: "' counter reject with icmp type admin-prohibited

echo "nftables rules applied"

# === Verification ===
echo "Verifying proxy sandbox..."

# Test 1: blocked domain via proxy should fail
if curl --proxy "http://127.0.0.1:${PROXY_PORT}" --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Verification failed — proxy allowed https://example.com"
    exit 1
else
    echo "PASS: proxy correctly blocked https://example.com"
fi

# Test 2: allowed domain via proxy should succeed
if ! curl --proxy "http://127.0.0.1:${PROXY_PORT}" --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Verification failed — proxy blocked https://api.github.com"
    exit 1
else
    echo "PASS: proxy correctly allowed https://api.github.com"
fi

# Test 3: direct connection (bypassing proxy) should fail
if curl --noproxy '*' --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Verification failed — direct connection bypassed nftables"
    exit 1
else
    echo "PASS: nftables correctly blocked direct connection"
fi

echo "Proxy sandbox active — all traffic routed through tinyproxy on 127.0.0.1:${PROXY_PORT}"
```

Write this to `.devcontainer/ansible/init-proxy.sh`.

- [ ] **Step 2: Commit**

```bash
git add .devcontainer/ansible/init-proxy.sh
git commit -m "feat: add init-proxy.sh for ansible devcontainer (Fedora)

Starts tinyproxy, applies static nftables rules to enforce proxy usage,
and verifies the sandbox with three checks: blocked domain, allowed
domain, and direct connection bypass attempt.

Part of issue #2 — Phase 1."
```

---

## Task 4: Create init-proxy.sh for claude (Debian)

**Files:**
- Create: `.devcontainer/claude/init-proxy.sh`

Identical logic to ansible version. The only behavioral difference is that nftables is pre-installed via the Dockerfile (Task 6), so no runtime package install is needed. The script itself is the same.

- [ ] **Step 1: Create init-proxy.sh**

The content is identical to the ansible version from Task 3, Step 1. Write the same script to `.devcontainer/claude/init-proxy.sh`.

- [ ] **Step 2: Commit**

```bash
git add .devcontainer/claude/init-proxy.sh
git commit -m "feat: add init-proxy.sh for claude devcontainer (Debian)

Same proxy sandbox logic as ansible variant — starts tinyproxy, applies
nftables rules, and runs verification checks.

Part of issue #2 — Phase 1."
```

---

## Task 5: Update ansible Dockerfile

**Files:**
- Modify: `.devcontainer/ansible/Dockerfile`

Changes: install tinyproxy, copy tinyproxy.conf and allowlist, copy and set up init-proxy.sh with sudoers.

- [ ] **Step 1: Update Dockerfile**

The current Dockerfile at `.devcontainer/ansible/Dockerfile` needs these changes:

**Change 1:** Add `tinyproxy` to the dnf install line (line 9):

Replace:
```dockerfile
RUN dnf install -y nodejs npm sudo nftables iptables ipset curl jq bind-utils iproute aggregate && dnf clean all
```
With:
```dockerfile
RUN dnf install -y nodejs npm sudo nftables iptables ipset curl jq bind-utils iproute aggregate tinyproxy && dnf clean all
```

**Change 2:** Add tinyproxy config copy and proxy script setup after the firewall section. Replace the block starting at `# Copy and set up firewall script` (lines 17-21) through `WORKDIR /workspace` (line 23) with:

```dockerfile
# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "root ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/root-firewall && \
  chmod 0440 /etc/sudoers.d/root-firewall

# Copy and set up proxy sandbox
COPY tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
COPY proxy-allowlist.txt /etc/tinyproxy/allowlist
RUN mkdir -p /var/log/tinyproxy && chown tinyproxy:tinyproxy /var/log/tinyproxy
COPY init-proxy.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-proxy.sh && \
  echo "root ALL=(root) NOPASSWD: /usr/local/bin/init-proxy.sh" > /etc/sudoers.d/root-proxy && \
  chmod 0440 /etc/sudoers.d/root-proxy

WORKDIR /workspace
```

- [ ] **Step 2: Commit**

```bash
git add .devcontainer/ansible/Dockerfile
git commit -m "feat: install tinyproxy and proxy configs in ansible Dockerfile

Adds tinyproxy package, copies config and allowlist to /etc/tinyproxy/,
sets up init-proxy.sh with sudoers entry.

Part of issue #2 — Phase 1."
```

---

## Task 6: Update claude Dockerfile

**Files:**
- Modify: `.devcontainer/claude/Dockerfile`

Changes: install tinyproxy + nftables (nftables not previously installed for claude), copy config files, set up init-proxy.sh with sudoers.

- [ ] **Step 1: Update Dockerfile**

**Change 1:** Add `tinyproxy` and `nftables` to the apt-get install list (lines 9-28):

Replace:
```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/*
```
With:
```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  tinyproxy \
  nftables \
  && apt-get clean && rm -rf /var/lib/apt/lists/*
```

**Change 2:** Add proxy config copy and init-proxy.sh setup. After the existing firewall setup block (lines 86-91), add the proxy setup before the final `USER node`:

Replace (lines 85-91):
```dockerfile
# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall
USER node
```
With:
```dockerfile
# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall

# Copy and set up proxy sandbox
COPY tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
COPY proxy-allowlist.txt /etc/tinyproxy/allowlist
RUN mkdir -p /var/log/tinyproxy && chown tinyproxy:tinyproxy /var/log/tinyproxy
COPY init-proxy.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-proxy.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-proxy.sh" > /etc/sudoers.d/node-proxy && \
  chmod 0440 /etc/sudoers.d/node-proxy
USER node
```

- [ ] **Step 2: Commit**

```bash
git add .devcontainer/claude/Dockerfile
git commit -m "feat: install tinyproxy and proxy configs in claude Dockerfile

Adds tinyproxy and nftables packages, copies config and allowlist to
/etc/tinyproxy/, sets up init-proxy.sh with sudoers entry for node user.

Part of issue #2 — Phase 1."
```

---

## Task 7: Update ansible devcontainer.json

**Files:**
- Modify: `.devcontainer/ansible/devcontainer.json`

Changes: add proxy environment variables, update postAttachCommand to mention both firewall and proxy options.

- [ ] **Step 1: Update devcontainer.json**

**Change 1:** Add proxy env vars to `containerEnv` (after the `GH_TOKEN` line):

Replace:
```json
  "containerEnv": {
    "NODE_OPTIONS": "--max-old-space-size=4096",
    "CLAUDE_CONFIG_DIR": "/root/.claude",
    "CLAUDE_CODE_USE_VERTEX": "${localEnv:CLAUDE_CODE_USE_VERTEX}",
    "ANTHROPIC_VERTEX_PROJECT_ID": "${localEnv:ANTHROPIC_VERTEX_PROJECT_ID}",
    "CLOUD_ML_REGION": "${localEnv:CLOUD_ML_REGION}",
    "GH_TOKEN": "${localEnv:GH_TOKEN}"
  },
```
With:
```json
  "containerEnv": {
    "NODE_OPTIONS": "--max-old-space-size=4096",
    "CLAUDE_CONFIG_DIR": "/root/.claude",
    "CLAUDE_CODE_USE_VERTEX": "${localEnv:CLAUDE_CODE_USE_VERTEX}",
    "ANTHROPIC_VERTEX_PROJECT_ID": "${localEnv:ANTHROPIC_VERTEX_PROJECT_ID}",
    "CLOUD_ML_REGION": "${localEnv:CLOUD_ML_REGION}",
    "GH_TOKEN": "${localEnv:GH_TOKEN}",
    "HTTP_PROXY": "http://127.0.0.1:8888",
    "HTTPS_PROXY": "http://127.0.0.1:8888",
    "NO_PROXY": "localhost,127.0.0.1"
  },
```

**Change 2:** Update `postAttachCommand` to mention the proxy option:

Replace:
```json
  "postAttachCommand": "echo 'Firewall disabled by default. Enable with: sudo /usr/local/bin/init-firewall.sh'",
```
With:
```json
  "postAttachCommand": "echo 'Network sandbox disabled by default. Enable proxy sandbox: sudo /usr/local/bin/init-proxy.sh | Enable IP firewall: sudo /usr/local/bin/init-firewall.sh'",
```

- [ ] **Step 2: Commit**

```bash
git add .devcontainer/ansible/devcontainer.json
git commit -m "feat: add proxy env vars to ansible devcontainer.json

Sets HTTP_PROXY, HTTPS_PROXY, NO_PROXY for tinyproxy integration.
Proxy sandbox remains disabled by default (same as existing firewall).

Part of issue #2 — Phase 1."
```

---

## Task 8: Update claude devcontainer.json

**Files:**
- Modify: `.devcontainer/claude/devcontainer.json`

Changes: add proxy environment variables, switch postStartCommand from init-firewall.sh to init-proxy.sh.

- [ ] **Step 1: Update devcontainer.json**

**Change 1:** Add proxy env vars to `containerEnv`:

Replace:
```json
  "containerEnv": {
    "NODE_OPTIONS": "--max-old-space-size=4096",
    "CLAUDE_CONFIG_DIR": "/home/node/.claude",
    "POWERLEVEL9K_DISABLE_GITSTATUS": "true",
    "CLAUDE_CODE_USE_VERTEX": "${localEnv:CLAUDE_CODE_USE_VERTEX}",
    "ANTHROPIC_VERTEX_PROJECT_ID": "${localEnv:ANTHROPIC_VERTEX_PROJECT_ID}",
    "CLOUD_ML_REGION": "${localEnv:CLOUD_ML_REGION}",
    "GH_TOKEN": "${localEnv:GH_TOKEN}"
  },
```
With:
```json
  "containerEnv": {
    "NODE_OPTIONS": "--max-old-space-size=4096",
    "CLAUDE_CONFIG_DIR": "/home/node/.claude",
    "POWERLEVEL9K_DISABLE_GITSTATUS": "true",
    "CLAUDE_CODE_USE_VERTEX": "${localEnv:CLAUDE_CODE_USE_VERTEX}",
    "ANTHROPIC_VERTEX_PROJECT_ID": "${localEnv:ANTHROPIC_VERTEX_PROJECT_ID}",
    "CLOUD_ML_REGION": "${localEnv:CLOUD_ML_REGION}",
    "GH_TOKEN": "${localEnv:GH_TOKEN}",
    "HTTP_PROXY": "http://127.0.0.1:8888",
    "HTTPS_PROXY": "http://127.0.0.1:8888",
    "NO_PROXY": "localhost,127.0.0.1"
  },
```

**Change 2:** Switch `postStartCommand` from firewall to proxy:

Replace:
```json
  "postStartCommand": "echo ${CLOUD_ML_REGION} > /tmp/.cloud_ml_region && sudo /usr/local/bin/init-firewall.sh",
```
With:
```json
  "postStartCommand": "echo ${CLOUD_ML_REGION} > /tmp/.cloud_ml_region && sudo /usr/local/bin/init-proxy.sh",
```

- [ ] **Step 2: Commit**

```bash
git add .devcontainer/claude/devcontainer.json
git commit -m "feat: switch claude devcontainer to proxy sandbox

Replaces init-firewall.sh with init-proxy.sh in postStartCommand.
Sets HTTP_PROXY, HTTPS_PROXY, NO_PROXY for tinyproxy integration.
Proxy sandbox enabled by default (same behavior as existing firewall).

Part of issue #2 — Phase 1."
```

---

## Task 9: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read current README.md**

Read `README.md` to understand its current structure and find where to add proxy sandbox documentation.

- [ ] **Step 2: Add proxy sandbox section**

Add a section documenting the proxy sandbox alongside the existing firewall documentation. Include:
- What the proxy sandbox does (Tinyproxy + nftables)
- How to enable/disable it
- How to check status
- How to add domains to the allowlist
- Which devcontainer has it enabled/disabled by default
- Mention init-firewall.sh as the legacy alternative

The exact content depends on the current README structure — adapt to fit.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add proxy sandbox documentation to README

Documents the tinyproxy + nftables proxy sandbox, how to enable/disable,
check status, and manage the domain allowlist.

Part of issue #2 — Phase 1."
```
