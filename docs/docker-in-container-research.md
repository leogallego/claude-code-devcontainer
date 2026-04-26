# Docker-in-Container Research

Investigation into running Docker inside the devcontainers.

## Can dockerd run inside these containers?

### ansible profile (Fedora, root)
Already has most DinD prerequisites: `SYS_ADMIN`, `seccomp=unconfined`, `apparmor=unconfined`, `--userns=host`. Would still need `--privileged` or additional device access. The official DinD feature sets `"privileged": true`.

### claude profile (Debian, node user)
Only has `NET_ADMIN` + `NET_RAW` -- far short of what dockerd requires. Would need `--privileged` or a significant list of additional capabilities plus seccomp/apparmor disabled.

## Official Devcontainer Features

Two official features exist in `ghcr.io/devcontainers/features/`:

- **`docker-in-docker:2`** -- Installs dockerd + CLI inside the container. Requires `"privileged": true`. Debian/Ubuntu only (uses `apt`).
- **`docker-outside-of-docker:1`** -- Installs only the Docker CLI and bind-mounts the host's `/var/run/docker.sock`. No privileged mode needed.

No official Podman devcontainer feature exists.

## DinD vs DooD (Docker-outside-Docker)

| | DinD | DooD |
|---|---|---|
| Daemon | Full dockerd inside container | Uses host's dockerd |
| Isolation | Full -- independent daemon, images, networks | Shared -- containers are siblings |
| Privileged | Required | Not required |
| Bind mounts | Work naturally (paths inside container) | Tricky -- must use host paths |
| Performance | Storage overhead (layered filesystems) | Native performance |
| Security | Privileged = near-root on host | Socket access = root-equivalent on host |

## Proxy sandbox conflicts with DinD

This is the critical issue. The nftables firewall sets `FORWARD policy DROP`. Docker's internal networking depends on:
- iptables/nftables FORWARD chain rules for container-to-container traffic
- NAT rules for port forwarding and outbound masquerading
- docker0 bridge traffic flowing through FORWARD

DinD would break the proxy sandbox because:
1. dockerd inserts its own iptables/nftables rules, conflicting with the firewall
2. FORWARD DROP policy blocks all container networking
3. HTTP_PROXY/HTTPS_PROXY env vars would need propagation to child containers

Workarounds: exempt docker bridge interfaces from firewall, or run dockerd with `--iptables=false` and manually manage routing.

## Podman-in-Podman (recommended for ansible profile)

Podman is designed for rootless nested execution and is a better fit for the ansible profile:
- Works without `--privileged` using rootless mode + `fuse-overlayfs`
- The ansible profile already has `--device=/dev/fuse` and sufficient capabilities
- No daemon means no iptables/nftables conflict for basic container operations
- Container networking (`slirp4netns` / `pasta`) could still conflict with nftables rules
- The ansible profile's existing capabilities (`SYS_ADMIN`, `MKNOD`, `/dev/fuse`, cgroup unmask) are sufficient for rootless Podman-in-Podman

## Recommendation

| Profile | Best option | Notes |
|---------|-------------|-------|
| ansible | Podman-in-Podman (rootless) | Already has the capabilities, no daemon conflict |
| claude | DooD (mount host socket) | Avoids privileged mode and firewall conflicts |
| Either | DinD | Only if full isolation needed; requires `--privileged` and firewall rework |
