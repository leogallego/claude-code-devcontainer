#!/bin/bash
# Set up container registry authentication using a fallback chain:
# 1. Persistent auth.json (~/.config/containers/auth.json bind-mounted from host)
# 2. Ephemeral auth.json (XDG_RUNTIME_DIR/containers/auth.json from host)
# 3. Environment variables (REGISTRY_REDHAT_IO_TOKEN, QUAY_TOKEN, DOCKER_TOKEN)

PERSISTENT_AUTH="/root/.config/containers/auth.json"
CONTAINER_AUTH_DIR="/root/.config/containers"

if [ -s "$PERSISTENT_AUTH" ]; then
    export REGISTRY_AUTH_FILE="$PERSISTENT_AUTH"
    echo "Registry auth: using persistent auth.json"
    exit 0
fi

XDG_AUTH="${XDG_RUNTIME_DIR:-/run/user/0}/containers/auth.json"
if [ -s "$XDG_AUTH" ]; then
    mkdir -p "$CONTAINER_AUTH_DIR"
    cp "$XDG_AUTH" "$PERSISTENT_AUTH"
    export REGISTRY_AUTH_FILE="$PERSISTENT_AUTH"
    echo "Registry auth: copied from ephemeral auth.json"
    exit 0
fi

LOGGED_IN=false
mkdir -p "$CONTAINER_AUTH_DIR"

if [ -n "$REGISTRY_REDHAT_IO_TOKEN" ]; then
    echo "$REGISTRY_REDHAT_IO_TOKEN" | podman login --authfile "$PERSISTENT_AUTH" -u unused --password-stdin registry.redhat.io 2>/dev/null && LOGGED_IN=true
fi

if [ -n "$QUAY_TOKEN" ]; then
    echo "$QUAY_TOKEN" | podman login --authfile "$PERSISTENT_AUTH" -u unused --password-stdin quay.io 2>/dev/null && LOGGED_IN=true
fi

if [ -n "$DOCKER_TOKEN" ]; then
    echo "$DOCKER_TOKEN" | podman login --authfile "$PERSISTENT_AUTH" -u "${DOCKER_USER:-unused}" --password-stdin docker.io 2>/dev/null && LOGGED_IN=true
fi

if [ "$LOGGED_IN" = true ]; then
    export REGISTRY_AUTH_FILE="$PERSISTENT_AUTH"
    echo "Registry auth: logged in via environment variables"
else
    echo "Registry auth: no credentials found (auth.json or env vars)"
fi
