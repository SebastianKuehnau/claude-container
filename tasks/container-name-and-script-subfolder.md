# Task
Make the `claude-task` container naming configurable and tidy the
`.devcontainer` layout, without changing today's default behavior:

1. **Configurable project name.** The name that drives the per-project image
   (`claude-task-<name>:latest`) and the per-worktree container
   (`claude-<name>-<branch>`) becomes resolvable, in this precedence:
   1. a `CLAUDE_TASK_NAME` variable in the (git-ignored) local env file, if set
      and non-empty — **local override**;
   2. a committed `name` field in `.devcontainer/claude-task.json`, if present
      and non-empty — **canonical/team source**;
   3. the current directory-basename default (`project_name()`) — **fallback**.
   Every resolved value is passed through the existing `sanitize()`.
2. **Scripts subfolder.** Move the seven `.devcontainer/*.sh` scripts into
   `.devcontainer/scripts/`, updating the Dockerfile so the image still builds.

Projects with no `claude-task.json` and no env override keep exactly today's
behavior (global image, directory-derived container name) — no regression.

# Context
- Repository: claude-container (home of `bin/claude-task`, the base-image
  `.devcontainer/Dockerfile`, and docs).
- `bin/claude-task` drives `docker build`/`docker run` directly (never
  `devcontainer up`). It is **sourceable** — the file ends with
  `if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then main "$@"; fi` — so its
  functions can be unit-tested without Docker.
- Naming today (all derive `project` from the main-repo directory basename via
  `project_name()`, `bin/claude-task:83-88`):
  - `image_tag_for_project()` → `claude-task-<project>:latest` (`:160-162`)
  - `container_name_for()` → `claude-<project>-<branch>` (`:164-167`)
  - Callers: `cmd_start` (`project=` at `:312`), `cmd_done` (`:372`),
    `cmd_sync` (`:441`). `cmd_done` does **not** read the project config today —
    it will need to, so its container name matches `cmd_start`'s.
  - Project-vs-global switch is `has_project_config()` = presence of
    `.devcontainer/claude-task.json` (`:135-137`); global fallback
    `ensure_global_image()` (`:203-220`) is unchanged by this task.
  - The config schema is written by `cmd_init` via `jq -n '{version, variant,
    java, buildTool, firewall, mcpServers, plugins}'`; read back with `cfg_get`
    (`:139-142`). There is no `name` field yet.
  - The local env file is `.devcontainer/devcontainer.env` (git-ignored per
    `.gitignore`), seeded copy-if-missing from `devcontainer.env.example`
    (`build_run_args`; `write_devcontainer_env_example`, `:645`). It is
    currently read **after** the name is computed and only for container env
    injection — the override must read it **earlier**, from the main-repo-root
    copy, so all worktrees of a project resolve the same name.
- Scripts to move and their build references:
  - Files: `entrypoint.sh`, `entrypoint-dind.sh`, `entrypoint-opencode.sh`,
    `init-firewall.sh`, `init-vaadin-plugins.sh`, `install-docker.sh`,
    `statusline-command.sh`.
  - The **only build-breaking references** are the 14 `COPY <src> …`
    statements in `.devcontainer/Dockerfile` across its four stages (base,
    opencode, dind, opencode-dind). Build context is `.devcontainer/`, so each
    `COPY` source is context-relative and must gain a `scripts/` prefix.
  - Everything else is unaffected: all runtime references, cross-script calls,
    `postStartCommand`s, aliases, and the `chmod`/exec lines use the **install
    destination** `/usr/local/bin/…`, which does not change.
  - `.github/workflows/build.yml` builds the image with `docker build` and thus
    also exercises the `COPY` paths (a CI safety net, not a task step).

# Implementation frame
- Single mechanism: `bin/claude-task`. Do **not** touch root
  `docker-compose.yml` or the devcontainer-CLI `*.json` naming — out of scope.
- Add one name-resolution path used by all three commands; the resolved name
  replaces the current `project="$(project_name …)"` in `cmd_start`,
  `cmd_done`, and `cmd_sync`. Resolution must be deterministic and identical
  across the three (a container started by `cmd_start` must be found by
  `cmd_done`/`--shell`). The env-file read must be robust (ignore comments and
  surrounding whitespace/quotes; tolerate a missing file).
- Add an optional `name` field to `claude-task.json`; extend `cmd_init` to ask
  for it (default = directory basename) and write it. Document the
  `CLAUDE_TASK_NAME` override as a commented line in **both** env-example
  writers (this repo's `.devcontainer/devcontainer.env.example` and the
  `write_devcontainer_env_example()` scaffold).
- Move the scripts with `git mv` (preserve history) into `.devcontainer/scripts/`
  and prefix every affected `COPY` source in the Dockerfile with `scripts/`.
  Do not change any `/usr/local/bin/…` destination.
- Constraint to document: because `CLAUDE_TASK_NAME` is a local override,
  changing it (or the config `name`) mid-task orphans a running container
  (its name no longer resolves). State this; do not build auto-recovery.
- Keep changes additive/backwards-compatible: unset override + no `name` field
  ⇒ byte-identical image/container names to today.

# Procedure
1. **Plan first.** Restate the approach and the name-resolution precedence,
   list the exact functions/files to touch, and wait for explicit approval
   before editing. (Precondition checks from "Definition of Done" run here,
   at the very start.)
2. Implement in verified steps, committing after each (Conventional Commits,
   no push):
   a. **Scripts move** — `git mv` + Dockerfile `COPY` prefixes; verify
      (static checks + build gate) before committing.
   b. **Name resolution** — resolver + helper, wire into the three commands;
      verify (sourced-function tests) before committing.
   c. **`--init` + config `name` field + env-example docs**; verify.
   d. **Docs** — update `CLAUDE.md` and `docs/working-with-tasks.md` where
      naming/layout changed; no duplication.
3. Verify against the Definition of Done before reporting done.

# Definition of Done
Preconditions (checked at the very start; if any is unmet, **abort and report**
— do not do partial work):
- `git`, `jq`, `bash`, and `shellcheck` are available.
- **Docker can build in this environment** (`docker version` succeeds and a
  trivial `docker build` runs). The build gate below is mandatory, so this task
  must run in a Docker-capable environment (host, or a `dind` `claude-task`
  session) — if Docker is unavailable, abort and say so.

Scripts move:
- `.devcontainer/scripts/` contains exactly the seven scripts; **no `*.sh`
  remains directly under `.devcontainer/`** (`ls` / `find`).
- Every `COPY … *.sh …` line in `.devcontainer/Dockerfile` has a `scripts/`
  source prefix, and every such source file exists under
  `.devcontainer/scripts/` (grep the Dockerfile; cross-check the file set).
- `git status` shows the moves as renames (history preserved).
- **Build gate:** `docker build --target dind -f .devcontainer/Dockerfile
  .devcontainer` and `docker build --target opencode-dind -f
  .devcontainer/Dockerfile .devcontainer` both succeed (together these two
  targets cover all 14 `COPY` statements). Build logs go to a git-ignored log
  file, not the commit.
- `bash -n` passes on all seven moved scripts.

Name resolution (verified by sourcing `bin/claude-task` in a throwaway
`git init` fixture — no Docker):
- No `name` field, no `CLAUDE_TASK_NAME` ⇒ resolved name equals
  `project_name(<repo>)` (byte-identical to today); the produced image tag and
  container name are unchanged from the pre-change output for the same repo/branch.
- `claude-task.json` `.name = "acme"` (no env) ⇒ image `claude-task-acme:latest`,
  container `claude-acme-<branch>`.
- `CLAUDE_TASK_NAME=override` in the local env file ⇒ resolves to `override`
  even when `.name = "acme"` is present (override wins).
- A value needing sanitization (e.g. `Foo Bar`) is sanitized identically to the
  current path (`foo-bar`).
- `cmd_done`/`--shell` resolve the **same** container name as `cmd_start` for
  identical inputs (assert the shared resolver is used by all three).
- The test script and its output are git-ignored / kept in scratch — not
  committed.

Init & docs:
- `bash -n bin/claude-task` and `shellcheck bin/claude-task` are clean.
- A scratch `claude-task --init` run writes a `claude-task.json` containing a
  `name` field, and the generated `devcontainer.env.example` carries a
  commented `#CLAUDE_TASK_NAME=` line; this repo's own
  `.devcontainer/devcontainer.env.example` carries the same commented line.
- `CLAUDE.md` reflects the `.devcontainer/scripts/` layout and the name
  override; `docs/working-with-tasks.md` documents the naming precedence. No
  stale references remain (grep for bare `.devcontainer/*.sh` paths in docs).

# Final report
- Commits with one-liners (one per procedure step).
- The final name-resolution precedence as implemented, and the exact
  env-file/variable used (`.devcontainer/devcontainer.env` / `CLAUDE_TASK_NAME`).
- Proof of the build gate (the two `docker build` target names + "succeeded")
  and a transcript snippet of the sourced-function name-resolution assertions.
- Confirmation that the unset-override/no-`name` case is byte-identical to the
  previous naming (the regression assertion).
- Decisions deliberately left to the user: (a) whether to also expose the name
  on the docker-compose / devcontainer-CLI paths later (currently out of
  scope); (b) whether to promote the throwaway name-resolution checks into a
  committed `test/` suite (none exists today).
