# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a Docker container setup for running AI coding agents (Claude Code, OpenCode), designed to also function as a VS Code dev container. The container provides a sandboxed environment with:

- Claude Code (or OpenCode) pre-installed
- Java 25 (Temurin JDK) for Java/Vaadin development
- Playwright + Chromium for browser automation (MCP and agent CLI variants)
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

The Dockerfile uses a multi-stage build with four targets:

| Service (docker-compose) | Target | Description |
|---|---|---|
| `claude` | `base` | Claude Code, no Docker daemon |
| `claude-dind` | `dind` | Claude Code + Docker-in-Docker (privileged) |
| `claude-docker-host` | `dind` | Claude Code + host Docker socket mounted |
| `opencode` | `opencode` | OpenCode (sst/opencode), no Docker daemon |

## Build & Run Commands

```bash
# Build and run a specific variant (recommended)
docker-compose up claude              # base variant
docker-compose up claude-dind         # Docker-in-Docker
docker-compose up claude-docker-host  # host Docker socket
docker-compose up opencode            # OpenCode variant

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

The devcontainer additionally uses `.devcontainer/devcontainer.env` (gitignored) for secrets — see `.devcontainer/devcontainer.env.example`.

## Architecture

```
bin/
  claude-task             # Standalone per-branch/worktree container-session script (see "claude-task" above)
docs/
  working-with-tasks.md   # claude-task daily workflow, image/cache/cleanup mechanisms
.devcontainer/
  Dockerfile              # Multi-stage build (base-common → base/dind/opencode)
  devcontainer.json       # VS Code dev container config (base variant)
  devcontainer-dind.json  # VS Code dev container config (DinD variant)
  devcontainer-opencode.json  # VS Code dev container config (OpenCode variant)
  entrypoint.sh           # Container entrypoint (base/dind)
  entrypoint-opencode.sh  # Container entrypoint (opencode)
  entrypoint-dind.sh      # Docker daemon startup (dind)
  init-firewall.sh        # iptables firewall setup (runs at postStart)
  allowed-domains.conf    # Allowlist for outbound network access
  playwright-info.sh      # Helper script: show installed Playwright versions
  statusline-command.sh   # Claude Code status line (model + progress bar + context %)
  claude-language-policy.md  # Global CLAUDE.md policy: German chat, English code/docs
docker-compose.yml        # All four service variants
.env.example              # Environment variable template
```

## Playwright Setup

Three Playwright installations coexist in the image (all browsers pre-installed at `/opt/playwright-browsers`):

1. **`playwright` (npm global)** — for Java Playwright integration tests
2. **`@playwright/mcp` (npm global)** — Claude's MCP browser tools
3. **`@playwright/cli` (npm global, `playwright-cli`)** — lower-token agent browser automation via shell commands

Run `playwright-info` inside the container to see installed versions and Chromium build IDs.

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