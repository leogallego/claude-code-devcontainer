FROM ghcr.io/ansible/community-ansible-dev-tools:latest

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest
ARG ENABLE_PROXY=true

# Install Node.js, sudo, and networking dependencies (Fedora uses dnf)
RUN dnf install -y nodejs npm sudo nftables iptables ipset curl jq bind-utils iproute aggregate tinyproxy procps-ng gh && dnf clean all

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

ENV DEVCONTAINER=true

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "root ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/root-firewall && \
  chmod 0440 /etc/sudoers.d/root-firewall

# Copy and set up proxy sandbox
COPY tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
COPY tinyproxy-passthrough.conf /etc/tinyproxy/tinyproxy-passthrough.conf
COPY proxy-allowlist.txt /etc/tinyproxy/allowlist
RUN mkdir -p /var/log/tinyproxy && chown tinyproxy:tinyproxy /var/log/tinyproxy
COPY init-proxy.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-proxy.sh && \
  echo "root ALL=(root) NOPASSWD: /usr/local/bin/init-proxy.sh" > /etc/sudoers.d/root-proxy && \
  chmod 0440 /etc/sudoers.d/root-proxy

# Proxy toggle: create sentinel file when enabled
RUN if [ "${ENABLE_PROXY}" = "true" ]; then touch /etc/tinyproxy/.proxy-enabled; fi

WORKDIR /workspace
