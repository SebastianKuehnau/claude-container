# Container Capabilities

A complete overview of what the `claude-container` in this repository can
do. It is a reference companion to the README (setup and usage details) and
[working-with-tasks.md](working-with-tasks.md) (the `claude-task`
workflow) — this document instead answers a single question: *what is this
thing capable of?*

At its core it is a Docker image (published multi-arch to GHCR) that runs an
AI coding agent in a sandboxed, batteries-included Java/Vaadin development
environment, plus `bin/claude-task`, a standalone script that turns it into
a per-branch, worktree-isolated workflow.

## 1. Run AI coding agents in a sandbox

- **Claude Code** — the default agent (base variant). Installed via the
  official installer, self-updatable (`sudo claude update`), version
  pinnable through `CLAUDE_CODE_VERSION` (`latest` / `stable` / a concrete
  version).
- **OpenCode** (sst/opencode) — an alternative agent in its own variant,
  version pinnable through `OPENCODE_VERSION`.
- **One-off headless prompts** — `docker run … claude -p "…"` for single
  non-interactive runs.
- **Two entry modes** — usable as a VS Code / IntelliJ Gateway dev
  container *or* directly via `docker run` / `docker-compose`, from the same
  image.
- **Multi-platform** — `linux/amd64` and `linux/arm64` (Apple Silicon),
  built and pushed to GHCR by CI.

## 2. Four build variants

The multi-stage `Dockerfile` produces four targets, exposed as
docker-compose services:

| Service | Target | Docker inside | Best for |
|---|---|---|---|
| `claude` (base) ⭐ | `base` | no | General development, smallest/fastest image |
| `claude-docker-host` | `dind` | via host socket | Docker development without firewall issues |
| `claude-dind` | `dind` | isolated daemon (privileged) | Full isolation, testing untrusted code |
| `opencode` | `opencode` | no | Using OpenCode instead of Claude Code |

## 3. Java / Vaadin development environment

- **Java JDK** pre-installed — version selectable (**17 / 21 / 25**) and
  vendor selectable (**Temurin / Corretto / Zulu**) via build args.
- **Container-safe Maven** — FS-safe file locking baked into `MAVEN_OPTS`
  so concurrent builds sharing one bind-mounted `~/.m2` don't corrupt each
  other.
- **Persistent Maven cache** — bind-mounted from the host, surviving
  container rebuilds.
- **Vaadin commercial components** — activated via `VAADIN_PRO_KEY` (env
  var or a mounted `~/.vaadin/proKey`): Charts, Board, Grid Pro,
  Acceleration Kits.
- **Vaadin Claude plugins** — `vaadin-skills@vaadin-marketplace`
  pre-installed at build time, with a start-time fallback installer.
- **Node.js 22** with an increased heap (`--max-old-space-size=4096`).

## 4. Network firewall (security)

- **Domain-whitelist firewall** (iptables, default-deny on `OUTPUT`) — only
  approved domains are reachable.
- A **default allowlist** is baked in (Anthropic API, npm, GitHub, Maven
  Central, VS Code marketplace, optionally Docker Hub).
- **Per-project allowlist** via `/workspace/.devcontainer/allowed-domains.conf`.
- **Runtime control** — `firewall-reload`, `firewall-status`.
- **Toggle off** — `SKIP_FIREWALL=1` (e.g. for DinD Docker Hub pulls).

## 5. `claude-task` — per-branch containerized sessions

A standalone Bash script (`bin/claude-task`), installable **without cloning
this repository**. It wraps everything above into one command:

| Command | What it does |
|---|---|
| `claude-task <branch>` | Start/attach a Claude session for `<branch>` — own git worktree + own container |
| `claude-task --plan <branch>` | Same, but start Claude in plan mode |
| `claude-task --shell <branch>` | Debug zsh shell instead of Claude (attaches to a running container) |
| `claude-task --done <branch>` | Stop the container, remove the worktree (refuses on uncommitted/unpushed work) |
| `claude-task --init [--force]` | Scaffold a project-specific config (see §6) |
| `claude-task --update` | Self-update to the latest release |

**Parallelism** — because each branch runs in its own worktree
(`<repo>-worktrees/<branch>`) and its own container, multiple branches of
the same project can run isolated sessions side by side.

**Smart image/cache logic:**
- Projects *without* `--init` use the global GHCR image and global Maven
  cache — no regression from the pre-`claude-task` behavior.
- Projects *with* a config get a **dedicated image**
  (`claude-task-<project>:latest`, `FROM` the GHCR base + a SDKMAN layer)
  and a **worktree-shared Maven cache**.
- **Config-hash-based rebuilds** — the image is rebuilt only when the
  rendered Dockerfile changes (`--rebuild` forces it regardless).

## 6. `claude-task --init` — project scaffolding

Five questions (Java version, Java vendor, build tool maven/gradle/none,
container variant, firewall profile) plus optional MCP-server and plugin
picks. It stages (never commits) a tailored setup:

- `.devcontainer/claude-task.json` — the config
- `.devcontainer/claude-task.Dockerfile` — generated (SDKMAN for Java/build tool)
- `.devcontainer/devcontainer.json` — for IDE attach
- `.devcontainer/allowed-domains.conf` — firewall starter list (allowlist profile only)
- `.mcp.json` — curated servers (github / context7 / filesystem)
- `.claude/settings.json` — includes deny rules against destructive commands (written once, never overwritten)
- `CLAUDE.md` skeleton, `tasks/` directory, and `.gitignore` entries

## 7. Persistent authentication & state

- **Login persistence** — a dedicated host directory (`~/.claude-container/`)
  keeps `claude login` valid across all containers, worktrees, and rebuilds;
  kept separate from the host's own `~/.claude/`.
- **GitHub auth** — via `GH_TOKEN` (fine-grained PATs) or a mounted
  `~/.config/gh`.
- **Git identity** — via `GIT_USER_NAME` / `GIT_USER_EMAIL`; HTTPS is forced
  over SSH for GitHub access.
- **Persistent shell history** — via a named volume.

## 8. Agent quality-of-life

- **Notifications** — `NOTIFICATION_URL` (e.g. ntfy.sh, Slack webhook);
  hooks fire on idle / permission prompt / elicitation.
- **Status line** — model name + progress bar + context-window usage %.
- **Plan mode by default** on start (never bypass mode).
- **Language policy** injected into the global `CLAUDE.md` — chat in German,
  code and docs in English.
- **Oh My Zsh** with helpful aliases, configurable timezone, passwordless
  sudo for the `node` user.

## 9. CI/CD & maintenance

- GitHub Actions builds all three variants (base/dind/opencode) multi-arch,
  **tests** `VAADIN_PRO_KEY` passthrough and the
  OpenCode CLI, then pushes to GHCR on push and on a weekly schedule.
- **Dependabot** configured for dependency updates.

## In one sentence

A turnkey, secured (firewall + deny rules + isolation) environment for
running Claude Code or OpenCode against Java/Vaadin projects — with
persistent login/cache, and, through
`claude-task`, a branch-parallel worktree workflow that builds a tailored
Java/build environment per project.