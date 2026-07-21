This container is based on: https://code.claude.com/docs/en/devcontainer and https://github.com/anthropics/claude-code/tree/main/.devcontainer but somewhat heavily modified. 

# TL;DR - just get me claude in a contaner, I'll think of security later!

First, create the global directories for persistent login and caching:

```
mkdir -p ~/.claude-container/claude
touch ~/.claude-container/claude.json
mkdir -p ~/.claude-m2-cache
```

Then make a folder with a workspace folder inside it:

```
mkdir -p claude-container-instance/workspace
```
go into the folder and create a .env file

```
cd claude-container-instance
nano .env
```

in the env file copy the following (.env.example): 

```
# Claude Container Environment Variables
# Copy this file to .env and customize as needed
# Usage: docker run --env-file .env ...

# Claude configuration directory (inside container)
CLAUDE_CONFIG_DIR=/home/node/.claude

# GitHub Personal Access Token for gh CLI
# GH_TOKEN=ghp_your_token_here

# Git identity (used for commits inside the container)
# GIT_USER_NAME=Your Name
# GIT_USER_EMAIL=your.email@example.com

# Timezone (defaults to Europe/Helsinki if not set)
# TZ=America/New_York

# Skip firewall initialization (set to 1 to disable)
SKIP_FIREWALL=1

# Notification URL (e.g., ntfy.sh) - called when Claude is idle or needs permission
# Supports any URL that accepts POST requests (ntfy.sh, webhooks, etc.)
# NOTIFICATION_URL=https://ntfy.sh/your-topic-here

# Vaadin Pro/Commercial key (for Charts, Board, Acceleration Kits, etc.)
# Alternatively, mount a ~/.vaadin/proKey file into the container
# VAADIN_PRO_KEY=your-pro-key-here

# Node.js memory limit
NODE_OPTIONS=--max-old-space-size=4096
```

For a first test the above config disables the firewall. 

* If you want to commit inside the container, you probably want to set the `GIT_USER` related params
* If you want to use Vaadin commercial components, either set your `proKey` (just the value starting with `pro-` in the environment variable, or later inside the contaier `mkdir -p ~/.vaadin && nano ~/node/.vaadin/proKey` and copy your entire prokey from a different system (or follow the browser process to sign in...)
* `GH_TOKEN` is there if you want to use Github fine graned PATs for limited access to GH from within the container
* etc..


then run the prebuilt container with (uses global directories for persistent login and Maven cache):

```
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --env-file .env \
  -v "${HOME}/.claude-container/claude:/home/node/.claude" \
  -v "${HOME}/.claude-container/claude.json:/home/node/.claude.json" \
  -v "${HOME}/.claude-m2-cache:/home/node/.m2" \
  -v "./workspace:/workspace" \
  ghcr.io/petrixh/claude-container:latest
```

> **Note:** Using `~/.claude-container/` persists your login across all container instances. Log in once, use everywhere!


Clone your projects under `/workspace`, run claude do stuff :) 

Read what the `entrypoint.sh` command tells you about installed versions. Or don't... you can re-run the entrypoint inside the container terminal by just typing `entrypoint.sh` to get to the info later also (should be fine to rerun). To update claude run `sudo claude update` as new versions are being pushed constantly... 

# TL;DR I just want a devcontainer from my IDE/Codespaces optinally with docker-in-docker fully understanding the risks it might bring

First, create the global directories for persistent login (same as in the first TL;DR):

```
mkdir -p ~/.claude-container/claude
touch ~/.claude-container/claude.json
mkdir -p ~/.claude-m2-cache
```

Then check out your project in a directory, and inside that directory create the `.devcontainer` folder:

```
mkdir .devcontainer
```

then create a devcontainer file under `.devcontainer/devcontainer.json` with the content: 

```
{
  "name": "Claude Code Sandbox",
  "image": "ghcr.io/petrixh/claude-container:latest",
  "runArgs": [
    "--cap-add=NET_ADMIN",
    "--cap-add=NET_RAW",
    "--env-file=.devcontainer/.env", //if desired to setup vars in a file instead, comment out containerEnv-entries if used
  ],
// If you want to bring env variables from your current environment to the devconatiner
  // "containerEnv": {
  //   "SKIP_FIREWALL": "1",
  //   "GH_TOKEN": "${localEnv:GH_TOKEN}",
  //   "GIT_USER_NAME": "${localEnv:GIT_USER_NAME}",
  //   "GIT_USER_EMAIL": "${localEnv:GIT_USER_EMAIL}",
  //   "NODE_OPTIONS": "--max-old-space-size=4096",
  //   "CLAUDE_CONFIG_DIR": "/home/node/.claude",
  //   //"VAADIN_PRO_KEY": "${localEnv:VAADIN_PRO_KEY}",
  //   "NOTIFICATION_URL": "${localEnv:NOTIFICATION_URL}",
  // },
  "customizations": {
    "vscode": {
      "extensions": [
        "vscjava.vscode-java-pack",
        "vscjava.vscode-maven"
      ],
      "settings": {
        "terminal.integrated.defaultProfile.linux": "zsh",
        "editor.formatOnSave": true,
        "java.configuration.detectJdksAtStart": true
      }
    }
  },
// If you need docker inside the dev container, does open up options for the AI to do all kinds of things... 
//  "features": {
//    "ghcr.io/devcontainers/features/docker-in-docker:3": {
//      "version": "latest",
//      "enableNonRootDocker": "true",
//      "moby": "false"
//    }
//  },
  "initializeCommand": "mkdir -p \"${localEnv:HOME}/.claude-container/claude\" && touch \"${localEnv:HOME}/.claude-container/claude.json\" && mkdir -p \"${localEnv:HOME}/.claude-m2-cache\"",
  "remoteUser": "node",
  "mounts": [
    "source=${localEnv:HOME}/.claude-container/claude,target=/home/node/.claude,type=bind,consistency=cached",
    "source=${localEnv:HOME}/.claude-container/claude.json,target=/home/node/.claude.json,type=bind,consistency=cached",
    "source=${localEnv:HOME}/.claude-m2-cache,target=/home/node/.m2,type=bind,consistency=cached",
    "source=claude-code-bashhistory-${devcontainerId},target=/commandhistory,type=volume"
  ],
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=delegated",
  "workspaceFolder": "/workspace",
  "postStartCommand": "/usr/local/bin/entrypoint.sh"
}
```

create an `.env` file under `.devcontainer` and add it to .gitignore immediatlely! Or create it somewhere else and map it at the top in the `runArgs` section. Inside the .env file look at `.env.example` or just copy paste: 

```
# Claude Container Environment Variables
# Copy this file to .env and customize as needed
# Usage: docker run --env-file .env ...

# Claude configuration directory (inside container)
CLAUDE_CONFIG_DIR=/home/node/.claude

# GitHub Personal Access Token for gh CLI
# GH_TOKEN=ghp_your_token_here

# Git identity (used for commits inside the container)
# GIT_USER_NAME=Your Name
# GIT_USER_EMAIL=your.email@example.com

# Timezone (defaults to Europe/Helsinki if not set)
# TZ=America/New_York

# Skip firewall initialization (set to 1 to disable)
SKIP_FIREWALL=1

# Notification URL (e.g., ntfy.sh) - called when Claude is idle or needs permission
# Supports any URL that accepts POST requests (ntfy.sh, webhooks, etc.)
# NOTIFICATION_URL=https://ntfy.sh/your-topic-here

# Vaadin Pro/Commercial key (for Charts, Board, Acceleration Kits, etc.)
# Alternatively, mount a ~/.vaadin/proKey file into the container
# VAADIN_PRO_KEY=your-pro-key-here

# Node.js memory limit
NODE_OPTIONS=--max-old-space-size=4096
```

If you had the folder open in VS Code, it should have already prompted you that a devcotnainer config was found. If not open the command palette and with > at the front look for "Dev Containers: Rebuild and Reopend in Container". It will download the internet and reopen the folder inside the devcotnaienr in VS Code. 

Read what the `entrypoint.sh` command tells you about installed versions. Or don't... you can re-run the entrypoint inside the container terminal by just typing `entrypoint.sh` to get to the info later also (should be fine to rerun). To update claude run `sudo claude update` as new versions are being pushed constantly... 

# TL;DR — claude-task: one command, per-branch containers, zero setup

`claude-task` wraps everything above into a single script: per-branch git
worktrees, containerized Claude Code sessions, and (for projects that opt
in via `--init`) a project-specific Java/build-tool image plus a
worktree-shared Maven cache. No clone of this repository required to
install it.

## Install

```bash
LATEST_TAG=$(curl -fsSL https://api.github.com/repos/SebastianKuehnau/claude-container/releases/latest \
  | grep -m1 '"tag_name"' | cut -d'"' -f4)
curl -fsSL -o ~/.local/bin/claude-task \
  "https://raw.githubusercontent.com/SebastianKuehnau/claude-container/${LATEST_TAG}/bin/claude-task"
chmod +x ~/.local/bin/claude-task
```

Make sure `~/.local/bin` is on your `PATH` (it isn't by default on macOS
zsh):
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc   # or ~/.bashrc
```

Update later with `claude-task --update` (re-resolves the latest release
and replaces the installed script in place).

## New project

Run once, inside any project's git repository:
```bash
claude-task --init
```

Five quick questions (Enter accepts the default):

| Question | Default | Choices |
|---|---|---|
| Java version | 25 | 17 / 21 / 25 |
| Java vendor | temurin | temurin / corretto / zulu |
| Build tool | maven | maven / gradle / none |
| Container variant | base | base / dind / opencode |
| Firewall profile | allowlist | allowlist (seeded starter list) / open |

...then optional picks for MCP servers (github / context7 / filesystem)
and any `plugin@marketplace` references.

`--init` stages (never commits) `.devcontainer/claude-task.json`, a
generated `.devcontainer/claude-task.Dockerfile` (`FROM` the published base
image + a SDKMAN layer for your Java/build-tool choices),
`.devcontainer/devcontainer.json`, `.devcontainer/allowed-domains.conf`
(only if `allowlist`), `.mcp.json`, `.claude/settings.json`, `CLAUDE.md`,
and two `.gitignore` entries. Task specs under `tasks/` are **not** ignored:
they are committed to the feature branch and stripped by `claude-task --sync`
before merge, so they live in the branch history but never reach `main`.
Review with `git status` /
`git diff --cached`, then commit yourself. Re-running `--init` on an
already-initialized project refuses to touch anything unless you pass
`--force` — and even then, `CLAUDE.md` / `.claude/settings.json` are only
written once and never overwritten.

Daily use after that:
```bash
claude-task <branch>          # start/attach a session (own git worktree + container)
claude-task --plan <branch>   # same, but start Claude explicitly in plan mode
claude-task --shell <branch>  # debug shell instead of Claude
claude-task --done <branch>   # stop the container, remove the worktree
                               # (refuses if there's uncommitted/unpushed work)
```

Projects that never ran `--init` keep exactly today's behavior — global
image, global Maven cache, zero regression. Full workflow and design
rationale: [docs/working-with-tasks.md](docs/working-with-tasks.md).

## Separate devcontainer and workspaces

```
mkdir workspace
```

Then clone your project(s) under `workspace`

After starting the devconatiner in VS Code use the command palette (top center) and with > at the beginning look for "File: Open Folder" and then navigate to `/workspace/workspace/your-project`. Now your devcontainer config and project are separate, but all still runs inside the devcontainer. To get back to your devcontainer config do the same open but select `/workspace` instead. 
 
To keep your devcontainer and workspace permananently separate change the `workspaceMount` entry, use: `-v "${localWorkspaceFolder}/workspace/:/workspace" ` for the bind mount instead. 

# The not TL;DR version

Below is a more compehensive example with instructions etc... Reading through them can give you insight into the whats and the whys... 

# Claude Container

A Docker devcontainer for running Claude Code in a sandboxed environment with:
- Node.js 20
- Java 21 (Eclipse Temurin)
- GitHub CLI with PAT authentication
- Domain-whitelist firewall (default deny)
- Configurable Claude config directory for subscription authentication
- Optional Docker-in-Docker (DinD) support for containerized development

## Prerequisites

Before running the container, ensure:

1. **Claude config directory** exists on your Docker host for persisting authentication:
   ```bash
   mkdir -p /path/to/claude-container-config
   ```
2. **GitHub PAT** (optional) - set the `GH_TOKEN` environment variable:
   ```bash
   export GH_TOKEN=ghp_your_token_here
   ```

## Authentication / Persistent Login

This container uses a **dedicated host directory** for Claude Code authentication state, ensuring login persists across container recreations without interfering with your host Claude Code installation.

### How It Works

Claude Code stores authentication in two locations inside the Linux container:
- `~/.claude/.credentials.json` — OAuth token
- `~/.claude.json` — Account state, onboarding preferences (note: this is a **file** in the home directory, not inside `.claude/`)

Both are mounted from `~/.claude-container/` on your host:
- `~/.claude-container/claude/` → container `/home/node/.claude/`
- `~/.claude-container/claude.json` → container `/home/node/.claude.json`

The `initializeCommand` in `devcontainer.json` (or the equivalent setup in `docker-compose.yml`) automatically creates these directories and files **before** the container starts, avoiding Docker's bind-mount trap where missing files get created as directories.

### First-Time Login

When you start a container for the **first time**, Claude Code will prompt you to log in:

```bash
# Inside the container
claude login
```

Follow the authentication flow. Your credentials will be saved to `~/.claude-container/` on the host.

### Subsequent Starts

After the initial login, **all future container starts** (including new worktrees, different projects, or container rebuilds) will automatically use the saved credentials. No re-login or onboarding required.

### Security Notes

⚠️ **Important:**
- `~/.claude-container/` contains your authentication credentials
- **Do not commit** this directory to version control
- **Do not share** these files (they're tied to your account)
- If you delete `~/.claude-container/`, you'll need to log in again
- This directory is separate from your host `~/.claude/` (if you have Claude Code installed locally) to avoid conflicts

### Verifying Setup

After your first login, verify the files exist on your host:

```bash
# On your macOS/Linux host
ls -la ~/.claude-container/
# Should show:
#   claude/                      (directory)
#   claude.json                  (file, not directory!)

ls -la ~/.claude-container/claude/
# Should show:
#   .credentials.json            (file with your OAuth token)
```

## Container Variants

This repository provides Claude Code and OpenCode variants. The Claude Code variants:

| Variant | Size | Docker | Best For | Limitations |
|---------|------|--------|----------|-------------|
| **`claude`** (base) ⭐ | 3.47GB | ❌ No | General Claude Code development | No Docker support |
| **`claude-docker-host`** | 3.92GB | ✅ Via host | Docker development, testing | Requires host Docker |
| **`claude-dind`** | 3.92GB | ✅ Isolated | Secure isolation, CI/CD | Firewall blocks Docker Hub |

The OpenCode variants swap Claude Code for [sst/opencode](https://opencode.ai) but share the
same base (Java, firewall):

| Variant | Docker | Best For | Limitations |
|---------|--------|----------|-------------|
| **`opencode`** | ❌ No | General OpenCode development | No Docker support |
| **`opencode-dind`** | ✅ Isolated | OpenCode + isolated Docker daemon | Firewall blocks Docker Hub |

**Quick test of `opencode-dind`** — pull the published image and drop into a shell with a working, isolated Docker daemon:

```bash
docker run --rm -it --privileged \
  -v claude-docker-data:/var/lib/docker \
  -e SKIP_FIREWALL=1 \
  ghcr.io/petrixh/claude-container-opencode-dind:latest zsh
```

Then, inside the container, confirm the nested daemon works:

```bash
docker run --rm alpine:latest echo "Hello from Docker-in-Docker"
```

Notes:
- `--privileged` + the `claude-docker-data` volume are required for the inner daemon — the volume gives `/var/lib/docker` a non-overlay backing filesystem, otherwise `overlay2` can't mount on an overlay-backed container rootfs.
- `SKIP_FIREWALL=1` lets the daemon pull from Docker Hub. With the firewall on, Docker Hub's CDN domains are blocked (see [Known Limitations](#known-limitations-and-workarounds)); for real Docker development use the host-socket approach instead.

### Quick Decision Guide

**Choose `claude` (base) if:** ⭐ RECOMMENDED
- General development (Java, Node.js, etc.)
- You don't need Docker inside the container
- You want the smallest, fastest container

**Choose `claude-docker-host` if:**
- You need Docker and have Docker on your host
- You want to pull from Docker Hub
- You want lower resource usage than DinD

**Choose `claude-dind` if:**
- You need complete isolation from host Docker
- You're testing untrusted code
- You're willing to work around firewall limitations

## Quick Start

### Most Common Use Cases

**Standard Development (recommended):**
```bash
docker compose up -d claude
docker compose exec claude zsh
claude --version
```

**Docker Development (host socket):**
```bash
docker compose up -d claude-docker-host
docker compose exec claude-docker-host zsh
docker pull alpine  # Works without firewall issues!
```

**Isolated Docker Environment:**
```bash
docker compose up -d claude-dind
docker compose exec claude-dind zsh
# Note: Docker Hub pulls blocked by firewall - see Known Limitations
```

### Build the Images

```bash
# Base variant (default)
docker build -t claude-container:base --target base .devcontainer/

# DinD variant (both claude-dind and claude-docker-host use this)
docker build -t claude-container:dind --target dind .devcontainer/

# OpenCode variant
docker build -t claude-container:opencode --target opencode .devcontainer/

# OpenCode DinD variant (isolated Docker daemon)
docker build -t claude-container:opencode-dind --target opencode-dind .devcontainer/
```

### Interactive Shell Options

#### Option 1: Docker Compose (Recommended)

Start an interactive development environment:

```bash
# Start container in background and attach
docker compose up -d && docker compose exec claude zsh

# Or start and attach directly (container removed on exit)
docker compose run --rm claude

# Stop the container
docker compose down

# DinD variant with separate Docker daemon
docker compose up -d claude-dind && docker compose exec claude-dind zsh

# DinD variant mounting host Docker socket
docker compose up -d claude-docker-host && docker compose exec claude-docker-host zsh

# OpenCode variant
docker compose up -d opencode && docker compose exec opencode zsh

# OpenCode DinD variant (separate Docker daemon)
docker compose up -d opencode-dind && docker compose exec opencode-dind zsh
```

### Option 2: Interactive Shell (Docker Run)

```bash
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v "${HOME}/.claude-container/claude:/home/node/.claude" \
  -v "${HOME}/.claude-container/claude.json:/home/node/.claude.json" \
  -e CLAUDE_CONFIG_DIR="/home/node/.claude" \
  -w /workspace \
  claude-container:base
```

> **Note:** The `CLAUDE_CONFIG_DIR` environment variable tells Claude where to store authentication credentials. Mount `~/.claude-container/` from the host to persist login across container restarts (see [Authentication](#authentication--persistent-login) section).

### Option 2b: Docker Run with Environment File

For easier management of environment variables, use a `.env` file:

```bash
# Copy the example env file and edit with your settings
cp .env.example .env
vim .env

# Minimal: just env file
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --env-file .env \
  claude-container:base
```

**Add Maven cache** to avoid re-downloading dependencies:

```bash
mkdir -p ~/.m2-cache

docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --env-file .env \
  -v "${HOME}/.m2-cache:/home/node/.m2" \
  claude-container:base
```

**Add workspace** to work on a project:

```bash
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --env-file .env \
  -v "${HOME}/.m2-cache:/home/node/.m2" \
  -v "$(pwd):/workspace" \
  claude-container:base
```

**Full setup** with all common mounts:

```bash
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --env-file .env \
  -v "${HOME}/.claude-container/claude:/home/node/.claude" \
  -v "${HOME}/.claude-container/claude.json:/home/node/.claude.json" \
  -v "${HOME}/.m2-cache:/home/node/.m2" \
  -v "${HOME}/.npm-cache:/home/node/.npm" \
  -v "${HOME}/.config/gh:/home/node/.config/gh" \
  -v "$(pwd):/workspace" \
  claude-container:base
```

**Volume mounts explained:**

| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `~/.claude-container/claude/` | `/home/node/.claude` | Claude config directory (credentials) |
| `~/.claude-container/claude.json` | `/home/node/.claude.json` | Claude account state file |
| `~/.m2-cache` | `/home/node/.m2` | Maven local repository cache |
| `~/.npm-cache` | `/home/node/.npm` | NPM cache |
| `~/.config/gh` | `/home/node/.config/gh` | GitHub CLI authentication |
| `$(pwd)` | `/workspace` | Your project directory |

### Option 3: Run a One-Off Claude Prompt

Execute a single prompt and exit:

```bash
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v "/path/to/claude-container-config:/claude-container-config" \
  -e CLAUDE_CONFIG_DIR="/claude-container-config" \
  -w /workspace \
  claude-container \
  claude -p "Your prompt here"
```

## VS Code Dev Container

### Base Variant
1. Open this repository in VS Code
2. Install the "Dev Containers" extension
3. Run **"Dev Containers: Reopen in Container"** from the command palette

### DinD Variant
Use the alternative configuration for Docker-in-Docker support:

```bash
# Using devcontainer CLI
devcontainer up --workspace-folder . \
  --config .devcontainer/devcontainer-dind.json

# Or rename the config (backup original first)
mv .devcontainer/devcontainer.json .devcontainer/devcontainer-base.json
mv .devcontainer/devcontainer-dind.json .devcontainer/devcontainer.json
```

### OpenCode Variants
Use the OpenCode configurations to run [sst/opencode](https://opencode.ai) instead of Claude Code:

```bash
# OpenCode (no Docker)
devcontainer up --workspace-folder . \
  --config .devcontainer/devcontainer-opencode.json

# OpenCode with Docker-in-Docker (isolated daemon)
devcontainer up --workspace-folder . \
  --config .devcontainer/devcontainer-opencode-dind.json
```

## Docker-in-Docker Usage

> **⚠️ Important:** The `claude-dind` variant's firewall blocks Docker Hub image pulls due to dynamic CDN domains. For Docker development with image pulling, use the `claude-docker-host` variant instead. See [Known Limitations](#known-limitations-and-workarounds) for details.

### When to Use Each Variant

**Base Variant (`claude`)** ⭐ Recommended
- ✅ Standard Claude Code development
- ✅ Smallest image size (3.47GB)
- ✅ Fastest startup (~2 seconds)
- ✅ Lowest resource usage
- Use when: General development without Docker needs (most users)

**Host Socket Variant (`claude-docker-host`)** - For Docker development
- ✅ Access to Docker without firewall issues
- ✅ Shares host Docker daemon and images
- ✅ Lower resource usage than separate daemon
- ✅ No privileged mode required
- ⚠️  Can affect host Docker state
- ⚠️  Requires host Docker installation
- Use when: You need Docker and trust your environment

**Separate Daemon Variant (`claude-dind`)** - For isolated environments
- ✅ Full isolation from host Docker
- ✅ Persistent Docker cache in container
- ✅ Works without host Docker
- ⚠️  Requires privileged mode
- ⚠️  Higher resource usage (+100-200MB RAM)
- ⚠️  Docker Hub pulls blocked by firewall
- ⚠️  Slower startup (~8 seconds)
- Use when: You need isolated Docker or untrusted code testing

### Testing Docker Inside Container

```bash
# Enter DinD container
docker compose exec claude-dind zsh

# Verify Docker installation
docker version
docker compose version

# Note: Docker Hub image pulls may be blocked by firewall
# See "Known Limitations" section below for workarounds
```

### Known Limitations and Workarounds

#### Docker Hub Image Pulls with Firewall

**Issue:** Docker Hub now uses Cloudflare R2 storage with dynamic subdomains that cannot be whitelisted by domain name. Image pulls will timeout when the firewall is enabled.

**Symptoms:**
```
failed to do request: Get "https://docker-images-prod.*.r2.cloudflarestorage.com/...":
dial tcp 172.64.66.1:443: i/o timeout
```

**Workarounds:**

**Option 1: Disable Firewall for DinD Container**
```bash
# Method A: Skip firewall initialization
docker run -it --rm --privileged \
  -e SKIP_FIREWALL=1 \
  claude-container:dind

# Method B: Run with permissive OUTPUT policy
docker run -it --rm --privileged \
  claude-container:dind bash -c \
  "sudo iptables -P OUTPUT ACCEPT && exec zsh"
```

**Option 2: Use Host Docker Socket (Recommended)**

The `claude-docker-host` variant mounts the host's Docker socket, bypassing the firewall issue:
```bash
docker compose up -d claude-docker-host
docker compose exec claude-docker-host zsh

# Now use host's Docker (images, containers shared with host)
docker pull alpine
docker images  # Shows host images
```

**Option 3: Pre-pull Images on Host**

Pull images on your host machine, then they're available inside DinD:
```bash
# On host
docker pull alpine:latest
docker pull node:20

# In claude-docker-host container
docker images  # Images available immediately
```

**Option 4: Use Local/Private Registry**

Configure a local or private registry with known domain names:
```bash
# Add your registry to allowed-domains.conf
echo "registry.mycompany.com" >> .devcontainer/allowed-domains.conf

# Rebuild and use
docker pull registry.mycompany.com/myimage:latest
```

**Option 5: Build Images Locally**

Build images inside the container without pulling from Docker Hub:
```bash
# Inside DinD container
cat > Dockerfile <<'EOF'
FROM scratch
COPY ./myapp /app
CMD ["/app/myapp"]
EOF

docker build -t myapp:latest .
docker run myapp:latest
```

## Firewall Configuration

The container uses a domain-whitelist firewall that blocks all outbound traffic except to approved domains. A default whitelist is baked into the image at `/usr/local/etc/allowed-domains.conf`.

### Default Allowed Domains

- `api.anthropic.com` - Claude API
- `registry.npmjs.org` - NPM packages
- `github.com`, `api.github.com` - GitHub
- `repo1.maven.org`, `repo.maven.apache.org` - Maven Central
- VS Code marketplace domains
- `registry-1.docker.io`, `auth.docker.io` - Docker Hub (DinD variant)

### Customizing the Domain Whitelist

To use your own domain whitelist, bind mount a custom config file:

```bash
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v "/path/to/your/allowed-domains.conf:/usr/local/etc/allowed-domains.conf:ro" \
  -v "/path/to/claude-container-config:/claude-container-config" \
  -e CLAUDE_CONFIG_DIR="/claude-container-config" \
  claude-container
```

Or copy the default config and modify it:

```bash
# Copy from this repo
cp .devcontainer/allowed-domains.conf ~/my-allowed-domains.conf

# Edit to add your domains
echo "example.com" >> ~/my-allowed-domains.conf
```

### Runtime Firewall Commands

Inside the container:

```bash
# View current firewall rules
firewall-status

# Reload firewall after editing the config
firewall-reload
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `CLAUDE_CONFIG_DIR` | Directory for Claude authentication and config (mount from host for persistence) |
| `GH_TOKEN` | GitHub Personal Access Token for `gh` CLI authentication |
| `GIT_USER_NAME` | Git author/committer name (sets `git config --global user.name`) |
| `GIT_USER_EMAIL` | Git author/committer email (sets `git config --global user.email`) |
| `TZ` | Timezone (default: `Europe/Helsinki`). Pass `-e TZ=$TZ` to inherit from host |
| `CLAUDE_CODE_VERSION` | Claude Code version to install (default: `latest`) |
| `SKIP_FIREWALL` | Set to `1` to skip firewall initialization (useful for DinD troubleshooting) |
| `FIREWALL_CONFIG` | Custom path to allowed-domains.conf (default: workspace or `/usr/local/etc`) |
| `DOCKER_HOST` | Docker daemon socket (default: `unix:///var/run/docker.sock`) |
| `NOTIFICATION_URL` | URL to POST notifications to when Claude is idle or needs permission (e.g., `https://ntfy.sh/your-topic`) |
| `VAADIN_PRO_KEY` | Vaadin Pro/Commercial subscription key for commercial components (Charts, Board, etc.) and Acceleration Kits |

## Notifications

The container can notify you when Claude needs attention via any URL that accepts POST requests (e.g., [ntfy.sh](https://ntfy.sh), Slack webhooks, custom endpoints).

### Setup

Set the `NOTIFICATION_URL` environment variable:
```bash
# In .env file
NOTIFICATION_URL=https://ntfy.sh/your-topic-here

# Or via docker run
docker run -it --rm \
  -e NOTIFICATION_URL=https://ntfy.sh/your-topic-here \
  claude-container:base
```

The entrypoint automatically configures Claude Code hooks in `settings.json` for these events:

| Event | Message |
|-------|---------|
| `idle_prompt` | Claude finished and is waiting for your input (60+ seconds idle) |
| `permission_prompt` | Claude needs your permission to proceed |
| `elicitation_dialog` | Claude is asking a question and waiting for your answer |

### Additional Hook Events

You can manually add more hooks to `~/.claude/settings.json` for these events:

| Matcher / Event | Description |
|-----------------|-------------|
| `auth_success` | Authentication completed |
| `Stop` (event, not matcher) | Claude finished responding (fires every time) |
| `TaskCompleted` (event) | A task was marked as completed |

See the [Claude Code hooks documentation](https://docs.anthropic.com/en/docs/claude-code/hooks) for the full reference.

## Vaadin Commercial Components

The container supports [Vaadin commercial components](https://vaadin.com/components) (Charts, Board, Grid Pro, etc.) and Acceleration Kits via the `VAADIN_PRO_KEY` environment variable.

### Providing the Pro Key

There are two ways to provide your Vaadin Pro subscription key:

**Option 1: Environment variable (recommended for containers)**

Set `VAADIN_PRO_KEY` in your `.env` file or pass it directly:
```bash
# In .env file
VAADIN_PRO_KEY=your-pro-key-here

# Or via docker run
docker run -it --rm \
  -e VAADIN_PRO_KEY=your-pro-key-here \
  claude-container:base
```

**Option 2: Mount a proKey file**

If you prefer file-based configuration, mount your `~/.vaadin/proKey` file from the host:
```bash
docker run -it --rm \
  -v "${HOME}/.vaadin:/home/node/.vaadin:ro" \
  claude-container:base
```

### Firewall Domains

If you're using Vaadin commercial components with the firewall enabled, uncomment the Vaadin domains in `allowed-domains.conf`:
```
maven.vaadin.com
tools.vaadin.com
vaadin.com
cdn.vaadin.com
```

Or add them at runtime:
```bash
# Inside the container
echo -e "maven.vaadin.com\ntools.vaadin.com\nvaadin.com\ncdn.vaadin.com" | sudo tee -a /usr/local/etc/allowed-domains.conf
firewall-reload
```

## Troubleshooting

### Docker Hub Pulls Timeout in DinD

**Symptom:** `dial tcp 172.64.66.1:443: i/o timeout` when pulling Docker images

**Solution:** Use the `claude-docker-host` variant instead, or disable the firewall:
```bash
# Recommended: Use host socket variant
docker compose up -d claude-docker-host

# Alternative: Disable firewall in DinD
docker run -it --rm --privileged -e SKIP_FIREWALL=1 claude-container:dind
```

### Docker Daemon Fails to Start

**Symptom:** "Error: Docker daemon failed to start"

**Check logs:**
```bash
# Inside container
cat /var/log/docker.log

# Common issues:
# - Missing privileged mode: Add --privileged flag
# - Missing SYS_ADMIN capability: Add --cap-add=SYS_ADMIN
```

**Solution:** Ensure proper flags:
```bash
docker run --rm --privileged \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --cap-add=SYS_ADMIN \
  claude-container:dind
```

### Firewall Blocking Required Domain

**Symptom:** Connection timeouts or "Could not resolve" warnings

**Check firewall status:**
```bash
# Inside container
firewall-status

# Check if domain is allowed
grep "mydomain.com" /usr/local/etc/allowed-domains.conf
```

**Solution:** Add domain to whitelist:
```bash
# Edit allowed-domains.conf
echo "mydomain.com" >> .devcontainer/allowed-domains.conf

# Rebuild image
docker build -t claude-container:base --target base .devcontainer/

# Or reload firewall at runtime (temporary)
# Inside container:
echo "mydomain.com" | sudo tee -a /usr/local/etc/allowed-domains.conf
firewall-reload
```

### Permission Denied Errors

**Symptom:** "Permission denied" when accessing Docker socket

**For host socket variant:**
```bash
# Ensure your user is in docker group on host
sudo usermod -aG docker $USER
newgrp docker

# Or run container with your user's UID
docker run --rm -u $(id -u):$(getent group docker | cut -d: -f3) \
  -v /var/run/docker.sock:/var/run/docker.sock \
  claude-container:dind
```

### Overlay2 Storage Driver Issues

**Symptom:** "invalid argument" when running nested containers

**Solution:** Use a named volume for `/var/lib/docker`:
```bash
docker run --rm --privileged \
  -v claude-docker-data:/var/lib/docker \
  claude-container:dind
```

## Rebuilding

After modifying the Dockerfile:

```bash
# Docker Compose (base variant)
docker compose build --no-cache claude

# Docker Compose (DinD variants)
docker compose build --no-cache claude-dind
docker compose build --no-cache claude-docker-host

# Docker directly
docker build --no-cache -t claude-container:base --target base .devcontainer/
docker build --no-cache -t claude-container:dind --target dind .devcontainer/
```

## Quick Reference (Docker Remote)

For Docker remote setups where the Docker daemon runs on a separate host, use absolute paths on the Docker host:

```bash
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v "/home/deb/claude-container-config:/claude-container-config" \
  -w /workspace \
  -e CLAUDE_CONFIG_DIR="/claude-container-config" \
  claude-container
```
