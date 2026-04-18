# Devcontainer Base Repository

A base devcontainer configuration for creating consistent development environments with Podman compatibility.

## Features

- Podman-compatible container setup
- Firewall configuration for network connectivity
- Ready to use as a template for new projects

## Usage

### Using This Template in New Projects

Choose the approach that best fits your workflow:

#### Option 1: GitHub Template Repository (Recommended)

1. Go to this repo's settings on GitHub → Enable "Template repository"
2. When creating a new project, click "Use this template" on GitHub
3. Clone your new repo and open in VS Code
4. VS Code will prompt to reopen in container

**Pros:** Clean, no git history, official GitHub feature

#### Option 2: Copy `.devcontainer/` Folder

```bash
# In your new project directory
cp -r /path/to/base-repo/.devcontainer .
```

**Pros:** Simple, explicit, easy to customize per project  
**Best for:** One-off projects or when you want independent configs

#### Option 3: Git Submodule (Shared Updates)

```bash
# In your new project
git submodule add <this-repo-url> .devcontainer
```

**Pros:** Keep base config synced across all projects  
**Cons:** More complex to manage  
**Best for:** When you want to propagate updates to multiple projects

#### Option 4: Degit

```bash
npx degit <your-username>/<this-repo> my-new-project
cd my-new-project
```

**Pros:** Quick, clean, no git history  
**Best for:** If you already use degit in your workflow

#### Option 5: Manual Clone

```bash
git clone <this-repo> my-new-project
cd my-new-project
rm -rf .git
git init
```

**Pros:** Works without GitHub features  
**Best for:** Self-hosted git or GitLab/Bitbucket

## Configuration

The devcontainer includes:
- [`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json) - Main devcontainer configuration
- [`.devcontainer/init-firewall.sh`](.devcontainer/init-firewall.sh) - Firewall initialization script

## Requirements

- VS Code with Dev Containers extension
- Podman or Docker
- Git

## Customization

Modify the devcontainer configuration to add:
- Additional VS Code extensions
- Custom environment variables
- Port forwarding
- Volume mounts
- Initialization scripts

## Troubleshooting

If you encounter network connectivity issues, ensure the firewall initialization script has proper permissions and runs during container startup.

## License

MIT
