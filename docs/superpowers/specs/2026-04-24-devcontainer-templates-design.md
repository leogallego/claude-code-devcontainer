# Devcontainer Template Publishing — Design Spec

## Goal

Restructure this repo so both devcontainer profiles (claude and ansible) are published as searchable devcontainer templates in VS Code's "Add Dev Container Configuration Files" dialog.

## Decision Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| One template or two? | Two separate templates | Different base images (node:20 vs Fedora), package managers (apt vs dnf), user models (node vs root), and extension sets. Separate entries are more discoverable in VS Code search. |
| Repo purpose | Templates only | Remove `.devcontainer/`, `src/` becomes the single source of truth. Eliminates sync burden. |
| Template options | Version + timezone + proxy toggle | Covers the main customization needs without over-engineering. |
| Starter repo vs restructure | Restructure in-place | Repo already exists with history, issues, and PRs. No need to fork. |

## Templates

### 1. `claude-code`

- **Name:** Claude Code (Node.js)
- **Base image:** `node:20`
- **User:** `node`
- **Description:** Node.js development environment with Claude Code CLI, proxy sandbox, zsh, and git-delta
- **Keywords:** `claude`, `claude-code`, `anthropic`, `ai`, `nodejs`, `proxy`, `sandbox`

### 2. `claude-code-ansible`

- **Name:** Ansible Development (Claude Code)
- **Base image:** `ghcr.io/ansible/community-ansible-dev-tools:latest`
- **User:** `root`
- **Description:** Ansible development environment with Claude Code CLI, ansible-lint, molecule, and proxy sandbox
- **Keywords:** `claude`, `claude-code`, `anthropic`, `ai`, `ansible`, `redhat`, `proxy`, `sandbox`

## Template Options

Both templates expose the same three options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `claudeCodeVersion` | string | `latest` | Claude Code npm package version |
| `timezone` | string | `America/Los_Angeles` | Container timezone (TZ) |
| `enableProxy` | boolean | `true` | Enable Tinyproxy + nftables proxy sandbox |

Options are substituted using `${templateOption:optionName}` syntax in `devcontainer.json` and `Dockerfile`.

### Proxy toggle implementation

- `Dockerfile`: Always installs tinyproxy and nftables (no conditional RUN blocks).
- `devcontainer.json`: The `postStartCommand` conditionally runs proxy startup based on the option. Since `${templateOption:enableProxy}` is resolved at template-apply time (not runtime), we use it to select which `postStartCommand` string gets written. This means the applied `devcontainer.json` will have the proxy command baked in or removed — no runtime conditional needed.

Approach: use `postStartCommand` that checks for a sentinel file `/etc/tinyproxy/.proxy-enabled` written by the Dockerfile when `enableProxy` is true. This way the Dockerfile handles the toggle at build time:

```dockerfile
ARG ENABLE_PROXY=true
RUN if [ "${ENABLE_PROXY}" = "true" ]; then touch /etc/tinyproxy/.proxy-enabled; fi
```

And `postStartCommand` checks:
```
"postStartCommand": "echo ${CLOUD_ML_REGION} > /tmp/.cloud_ml_region && if [ -f /etc/tinyproxy/.proxy-enabled ]; then ... proxy startup ...; fi"
```

In the template's `devcontainer.json`, the build arg is set from the template option:
```json
"build": {
  "args": {
    "ENABLE_PROXY": "${templateOption:enableProxy}"
  }
}
```

## Repo Structure

```
src/
  claude-code/
    devcontainer-template.json
    .devcontainer/
      devcontainer.json
      Dockerfile
      init-firewall.sh
      init-proxy.sh
      proxy-allowlist.txt
      tinyproxy.conf
      tinyproxy-passthrough.conf
  claude-code-ansible/
    devcontainer-template.json
    .devcontainer/
      devcontainer.json
      Dockerfile
      init-firewall.sh
      init-proxy.sh
      proxy-allowlist.txt
      tinyproxy.conf
      tinyproxy-passthrough.conf
test/
  claude-code/
    test.sh
  claude-code-ansible/
    test.sh
  test-utils/
    test-utils.sh
.github/
  workflows/
    release.yml
docs/
  devcontainer-template-research.md
  docker-in-container-research.md
README.md
LICENSE
```

### Files removed

- `.devcontainer/` — replaced by `src/` templates

## GitHub Action Workflow

File: `.github/workflows/release.yml`

- **Trigger:** push to `main` (paths: `src/**`) + `workflow_dispatch`
- **Action:** `devcontainers/action@v1` with `publish-templates: "true"` and `base-path-to-templates: "./src"`
- **Registry:** `ghcr.io/leogallego/claude-code-devcontainer/<template-id>:<version>`
- **Permissions:** `packages: write`, `contents: read`

## Test Scripts

Each template gets a `test.sh` that verifies:

### claude-code/test.sh
1. Node.js is available (`node --version`)
2. Claude Code CLI is installed (`claude --version`)
3. gh CLI is available (`gh --version`)
4. zsh is available (`zsh --version`)

### claude-code-ansible/test.sh
1. Ansible is available (`ansible --version`)
2. ansible-lint is available (`ansible-lint --version`)
3. Claude Code CLI is installed (`claude --version`)
4. gh CLI is available (`gh --version`)

## Post-Publish Manual Steps (not automated)

1. Set GHCR packages to **public** in GitHub package settings
2. Submit PR to [devcontainers/devcontainers.github.io](https://github.com/devcontainers/devcontainers.github.io) adding collection to `_data/collection-index.yml`:
   ```yaml
   - name: Claude Code Dev Containers
     maintainer: Leonardo Gallego
     contact: https://github.com/leogallego/claude-code-devcontainer/issues
     repository: https://github.com/leogallego/claude-code-devcontainer
     ociReference: ghcr.io/leogallego/claude-code-devcontainer
   ```

## Out of Scope

- Auto-generated docs PR in CI (can add later)
- Custom allowlist option (users edit the file post-apply)
- Devcontainer features (proxy sandbox is baked into the template, not extracted as a reusable feature)
