# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a Docker container setup for running AI coding agents (Claude Code, OpenCode), designed to also function as a VS Code dev container. The container provides a sandboxed environment with:

- Claude Code (or OpenCode) pre-installed
- Java 25 (Temurin JDK) for Java/Vaadin development
- GitHub CLI (`gh`)
- Firewall (iptables) for network access control
- Oh My Zsh with useful aliases

## claude-task

`bin/claude-task` is a standalone bash script (installable without cloning
this repo — see README "Install") that runs Claude Code per branch, one git
worktree each, in a container. `claude-task --init` scaffolds a
project-specific `.devcontainer/claude-task.json` (Java version/vendor,
build tool, container variant, firewall profile, MCP servers, plugins); a
project with this file gets its own image (`claude-task-<project>:latest`,
built `FROM` the published GHCR base image + a SDKMAN layer) and a
worktree-shared Maven cache at `<main-repo-root>/.devcontainer/m2-cache`.
Projects without the config file keep the global image/cache behavior
unchanged. Full workflow: [docs/working-with-tasks.md](docs/working-with-tasks.md).

## Build Variants

The Dockerfile uses a multi-stage build with five targets (`base-common` → `base`/`opencode`, then `dind` (from `base`) and `opencode-dind` (from `opencode`)):

| Service (docker-compose) | Target | Description |
|---|---|---|
| `claude` | `base` | Claude Code, no Docker daemon |
| `claude-dind` | `dind` | Claude Code + Docker-in-Docker (privileged) |
| `claude-docker-host` | `dind` | Claude Code + host Docker socket mounted |
| `opencode` | `opencode` | OpenCode (sst/opencode), no Docker daemon |
| `opencode-dind` | `opencode-dind` | OpenCode + Docker-in-Docker (privileged) |

## Build & Run Commands

```bash
# Build and run a specific variant (recommended)
docker-compose up claude              # base variant
docker-compose up claude-dind         # Docker-in-Docker
docker-compose up claude-docker-host  # host Docker socket
docker-compose up opencode            # OpenCode variant
docker-compose up opencode-dind       # OpenCode + Docker-in-Docker

# Build without running
docker-compose build claude

# Run interactively
docker-compose run --rm claude zsh
```

## Dev Container Usage (VS Code)

Open this repository in VS Code and use "Dev Containers: Reopen in Container" from the command palette, or use the devcontainer CLI:

```bash
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . bash
```

The default `devcontainer.json` uses the `base` variant. Alternative configs:
- `.devcontainer/devcontainer-dind.json` — Docker-in-Docker variant
- `.devcontainer/devcontainer-opencode.json` — OpenCode variant
- `.devcontainer/devcontainer-opencode-dind.json` — OpenCode + Docker-in-Docker variant

## Configuration

Copy `.env.example` to `.env` and set environment variables before running:

```bash
cp .env.example .env
# Edit .env with your values
```

Key environment variables:

| Variable | Description |
|---|---|
| `GH_TOKEN` | GitHub Personal Access Token for `gh` CLI |
| `JAVA_VERSION` | JDK version to install (default: `25`) |
| `JAVA_VENDOR` | JVM vendor: `temurin` (default), `corretto`, `zulu` |
| `GIT_USER_NAME` / `GIT_USER_EMAIL` | Git identity for commits inside container |
| `TZ` | Timezone (default: `Europe/Helsinki`) |
| `VAADIN_PRO_KEY` | Vaadin commercial license key |
| `NOTIFICATION_URL` | URL called when Claude is idle (e.g. ntfy.sh) |
| `SKIP_FIREWALL` | Set to `1` to disable firewall init |

The devcontainer additionally uses `.devcontainer/devcontainer.env` (gitignored) for secrets. It is seeded copy-if-missing from `.devcontainer/devcontainer.env.example` by the `initializeCommand` (never overwriting an edited file) and passed via `--env-file`.

## Architecture

```
bin/
  claude-task             # Standalone per-branch/worktree container-session script (see "claude-task" above)
docs/
  working-with-tasks.md   # claude-task daily workflow, image/cache/cleanup mechanisms
.devcontainer/
  Dockerfile              # Multi-stage build (base-common → base/opencode → dind/opencode-dind)
  devcontainer.json       # VS Code dev container config (base variant)
  devcontainer-dind.json  # VS Code dev container config (DinD variant)
  devcontainer-opencode.json  # VS Code dev container config (OpenCode variant)
  devcontainer-opencode-dind.json  # VS Code dev container config (OpenCode DinD variant)
  entrypoint.sh           # Container entrypoint (base/dind)
  entrypoint-opencode.sh  # Container entrypoint (opencode)
  entrypoint-dind.sh      # Docker daemon startup (dind)
  install-docker.sh       # Install Docker CE; shared by all DinD build stages
  init-firewall.sh        # iptables firewall setup (runs at postStart)
  allowed-domains.conf    # Allowlist for outbound network access
  statusline-command.sh   # Claude Code status line (model + progress bar + context %)
  claude-language-policy.md  # Global CLAUDE.md policy: German chat, English code/docs
docker-compose.yml        # All five service variants
.env.example              # Environment variable template
```

## Firewall

The container runs `init-firewall.sh` on start (`postStartCommand`). It uses iptables to restrict outbound traffic to the domains listed in `allowed-domains.conf`. Inside the container:

```bash
sudo firewall-reload    # re-apply firewall rules
sudo iptables -L -n -v  # inspect current rules
```

## Java / Vaadin Development

The image includes Java 25 (Temurin JDK). Maven cache is mounted at `/home/node/.m2` (bind mount from host) to persist between container rebuilds. The `VAADIN_PRO_KEY` env var activates commercial Vaadin components.

## Keeping This File In Sync

A `Stop` hook (`.claude/hooks/claude-md-sync.sh`, wired up in `.claude/settings.json`) checks at the end of each task whether code/config files changed without a corresponding `CLAUDE.md` update. If so, it prompts Claude once to review and update this file. Update `CLAUDE.md` whenever you add/rename scripts, change build/run commands, or add configuration/env variables.