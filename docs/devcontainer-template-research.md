# Devcontainer Template: Publishing Research

Research on how to make this project available as a devcontainer template searchable in VS Code's "Add Dev Container Configuration Files" dialog.

## Overview

Dev Container Templates are distributable, parameterized devcontainer configurations published as OCI artifacts. VS Code discovers them via a community index at [containers.dev](https://containers.dev).

## Required Steps

### 1. Restructure repo for template publishing

Current layout:
```
.devcontainer/
  ansible/   (devcontainer.json, Dockerfile, proxy scripts...)
  claude/    (devcontainer.json, Dockerfile, proxy scripts...)
```

Template repos need a `src/` directory:
```
src/
  claude-code-ansible/
    devcontainer-template.json
    .devcontainer/
      devcontainer.json
      Dockerfile
      init-firewall.sh, init-proxy.sh, proxy-allowlist.txt, ...
  claude-code/
    devcontainer-template.json
    .devcontainer/
      devcontainer.json
      Dockerfile
      ...
test/
  claude-code-ansible/test.sh
  claude-code/test.sh
```

The `.devcontainer/` directory can remain for local use — `src/` is only for publishing.

### 2. Create `devcontainer-template.json` per template

Required fields:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique template ID (matches directory name) |
| `version` | string | Semver version |
| `name` | string | Human-readable name |
| `description` | string | Template summary |

Optional fields:

| Field | Type | Description |
|-------|------|-------------|
| `options` | object | User-configurable parameters (prompted at apply time) |
| `keywords` | array | Searchable terms |
| `publisher` | string | Maintainer name |
| `documentationURL` | string | Link to docs |
| `licenseURL` | string | Link to license |
| `platforms` | array | Supported platforms |

#### Options schema

Options allow users to customize templates at apply time:
```json
{
  "options": {
    "enableProxy": {
      "type": "boolean",
      "description": "Enable Tinyproxy sandbox for network filtering",
      "default": "true"
    },
    "claudeCodeVersion": {
      "type": "string",
      "description": "Claude Code version to install",
      "default": "latest",
      "proposals": ["latest", "0.2.x"]
    }
  }
}
```

### 3. Add GitHub Action for OCI publishing

Use the official [devcontainers/action](https://github.com/devcontainers/action) GitHub Action.

```yaml
# .github/workflows/publish-templates.yml
name: Publish Dev Container Templates
on:
  push:
    branches: [main]
    paths: ['src/**']
  workflow_dispatch:

jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      packages: write
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: devcontainers/action@v1
        with:
          publish-templates: true
          base-path-template: src
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Templates are published to: `ghcr.io/leogallego/claude-code-devcontainer/<template-id>:<version>`

**Important:** After first publish, manually set GHCR packages to **public** in GitHub package settings.

### 4. Register in the community index

Submit a PR to [devcontainers/devcontainers.github.io](https://github.com/devcontainers/devcontainers.github.io) adding to `_data/collection-index.yml`:

```yaml
- name: Claude Code Dev Containers
  maintainer: Leonardo Gallego
  contact: https://github.com/leogallego/claude-code-devcontainer/issues
  repository: https://github.com/leogallego/claude-code-devcontainer
  ociReference: ghcr.io/leogallego/claude-code-devcontainer
```

Once merged, VS Code and GitHub Codespaces will list the templates.

### 5. CLI publishing alternative

Can also publish via CLI without the GitHub Action:
```bash
devcontainer templates publish -r ghcr.io -n leogallego/claude-code-devcontainer ./src
```

## Design Decisions To Make

1. **Two templates or one?** Publish `claude-code` and `claude-code-ansible` as separate templates, or one template with an `option` to select profile?
2. **What should be parameterized?** Candidates: Claude Code version, proxy enabled/disabled, timezone, proxy allowlist customization.
3. **Starter repo vs restructure?** Fork [devcontainers/template-starter](https://github.com/devcontainers/template-starter) (has CI pre-wired) or restructure this repo in-place?
4. **Dual-purpose repo?** Keep `.devcontainer/` for direct use AND `src/` for template publishing, or split into separate repos?

## Key Resources

- [Template Starter Repo](https://github.com/devcontainers/template-starter) — fork-ready structure with CI
- [Template Spec](https://containers.dev/implementors/templates/) — devcontainer-template.json reference
- [Template Distribution Spec](https://containers.dev/implementors/templates-distribution/) — OCI packaging details
- [Official Templates](https://github.com/devcontainers/templates) — examples to follow
- [Publishing Action](https://github.com/devcontainers/action) — GitHub Action for OCI publishing
- [Community Index](https://github.com/devcontainers/devcontainers.github.io) — where to register for VS Code discovery
