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
project-specific `.devcontainer/claude-task.json` (name, Java version/vendor,
build tool, container variant, firewall profile, permission mode, MCP servers,
plugins, passthrough env); a
project with this file gets its own image (`claude-task-<name>:latest`,
built `FROM` the published GHCR base image + a SDKMAN layer) and a
worktree-shared Maven cache at `<main-repo-root>/.devcontainer/m2-cache`.
The `<name>` that drives the image tag and the per-worktree container
(`claude-<name>-<branch>`) resolves in precedence: `CLAUDE_TASK_NAME` in the
git-ignored `.devcontainer/devcontainer.env` (local override) → the committed
`name` field in `claude-task.json` → the repository directory name (default).
Projects without the config file and without an override keep the global
image/cache behavior and directory-derived name unchanged. Full workflow:
[docs/working-with-tasks.md](docs/working-with-tasks.md).

### Permission mode (YOLO by default)

A no-modifier `claude-task <branch>` starts Claude Code with permission prompts
bypassed (`claude --dangerously-skip-permissions`), so it works uninterrupted;
the sandbox (firewall allowlist + no host access) and the `.claude/settings.json`
`permissions.deny` rules — which still block even under bypass — are the real
safety boundary, not the prompts. Precedence: an explicit `--plan` modifier wins,
then the optional `permissionMode` field (`bypass` | `plan` | `ask`) in
`claude-task.json`, then the built-in `bypass` default. The `base`/`dind`
entrypoint no longer pins a `defaultMode`; the launch command chosen by
`bin/claude-task` is authoritative (and a stale `permissions.defaultMode` from
the persistent `~/.claude` mount is cleared on start). Direct
`docker-compose`/`devcontainer` usage is unaffected by the bypass default: those
paths start Claude in its built-in prompting mode.

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
| `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` | AI-provider keys; forwarded from the host into the container when set (see host env passthrough below) |

The devcontainer additionally uses `.devcontainer/devcontainer.env` (gitignored) for secrets. It is seeded copy-if-missing from `.devcontainer/devcontainer.env.example` by the `initializeCommand` (never overwriting an edited file) and passed via `--env-file`.

### Host env passthrough

Host-exported environment variables can be forwarded into the container without
writing secrets into a committed file. `bin/claude-task` reads an optional
`passthroughEnv` array of variable *names* from `.devcontainer/claude-task.json`
and forwards each name via `-e NAME=$NAME` **only when it is set and non-empty
on the host** (values never touch disk). If the field is absent (or there is no
config file), the built-in default set `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` is
forwarded; an explicit empty array (`[]`) forwards nothing. `docker-compose.yml`
and the `devcontainer*.json` variants are static and cannot read that array, so
they carry the default key set only, wired in via `${VAR:-}` (compose) /
`${localEnv:VAR}` (devcontainer). Note: forwarding a non-default provider key
via `passthroughEnv` may additionally require allowlisting that provider's
domain in `.devcontainer/allowed-domains.conf` (`api.openai.com` and
`api.anthropic.com` are already allowed).

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
  scripts/                # Shell scripts COPY'd into the image (see Dockerfile)
    entrypoint.sh           # Container entrypoint (base/dind)
    entrypoint-opencode.sh  # Container entrypoint (opencode)
    entrypoint-dind.sh      # Docker daemon startup (dind)
    install-docker.sh       # Install Docker CE; shared by all DinD build stages
    init-firewall.sh        # iptables firewall setup (runs at postStart)
    init-vaadin-plugins.sh  # Vaadin plugin bootstrap helper
    statusline-command.sh   # Claude Code status line (model + progress bar + context %)
  allowed-domains.conf    # Allowlist for outbound network access
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

**Build-tool wrapper exec bits:** on start, the entrypoint (`entrypoint.sh` /
`entrypoint-opencode.sh`) restores the executable bit on `/workspace/mvnw` and
`/workspace/gradlew` when it was lost crossing the host→container bind mount, so
`./mvnw` / `./gradlew` work without a manual `chmod`. It only repairs wrappers
git itself records as executable (index mode `100755`), so it never dirties the
worktree; a wrapper git tracks as non-executable is left alone (use the
image-provided `mvn`/`gradle` instead).

## Keeping This File In Sync

A `Stop` hook (`.claude/hooks/claude-md-sync.sh`, wired up in `.claude/settings.json`) checks at the end of each task whether code/config files changed without a corresponding `CLAUDE.md` update. If so, it prompts Claude once to review and update this file. Update `CLAUDE.md` whenever you add/rename scripts, change build/run commands, or add configuration/env variables.