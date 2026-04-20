FROM ghcr.io/ansible/community-ansible-dev-tools:latest

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

# Install Node.js for Claude Code (Fedora uses dnf)
RUN dnf install -y nodejs npm && dnf clean all

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "root ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/root-firewall && \
  chmod 0440 /etc/sudoers.d/root-firewall
USER root

WORKDIR /workspace
