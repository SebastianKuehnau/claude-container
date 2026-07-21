# `claude-task` Cheat Sheet

Per-branch, containerized Claude Code sessions via git worktrees.
One branch = one git worktree = one container. See
[working-with-tasks.md](working-with-tasks.md) for the long-form guide.

---

## Command reference

| Command | What it does |
|---|---|
| `claude-task <branch>` | Start (or attach to) a Claude Code session for `<branch>`. Creates the worktree + container if missing. |
| `claude-task --plan <branch>` | Same as above, but start Claude in **plan mode** (`--permission-mode plan`). |
| `claude-task --shell <branch>` | Open a `zsh` debug shell instead of Claude. If the container is already running, attaches a **second** terminal (`docker exec`). |
| `claude-task --sync <branch>` | Headless: rebase onto `origin/main`, run tests, push, open/update the PR. No Claude session. |
| `claude-task --done <branch>` | Stop & remove the container, then remove the worktree. The branch itself is kept. |
| `claude-task --init [--force]` | Scaffold a project-specific container config (interactive Q&A). |
| `claude-task --update` | Self-update the script to the latest GitHub release. |
| `claude-task --help` | Show usage. |

### Modifiers (pass after the branch/subcommand)

| Modifier | Applies to | Effect |
|---|---|---|
| `--rebuild` | `<branch>`, `--plan`, `--shell` | Force a project image rebuild (`--pull --no-cache`) even if the config hash matches. Use when the upstream base image changed. |
| `--force` | `--init` | Overwrite an existing project config. |
| `--force` | `--done` | Skip the uncommitted/unpushed-work safety check and remove anyway. |

---

## Function map (what the script does internally)

Grouped as in the source (`bin/claude-task`).

### Git worktree / project identity
| Function | Role |
|---|---|
| `require_git_repo` | Aborts unless run inside a git repo. |
| `resolve_main_repo_root` | Resolves the **main** repo root via `--git-common-dir`, so cache/image identity is shared across all worktrees. |
| `sanitize` | Lowercases & collapses illegal chars so names satisfy Docker naming rules. |
| `project_name` | Derives the sanitized project name from the repo folder. |
| `worktree_path` | Computes `<parent>/<repo>-worktrees/<branch>` (sibling dir, not nested). |
| `worktree_exists` | Checks the porcelain `git worktree list` for a path. |
| `find_or_create_worktree` | Reuses or creates a worktree. Resolution order: local branch → `origin/<branch>` → new branch off `HEAD`. |

### Project config
| Function | Role |
|---|---|
| `config_path` / `has_project_config` | Locate / detect `.devcontainer/claude-task.json`. |
| `cfg_get` | Read a `jq` field with a default. |
| `detect_build_tool` | Best-effort build-tool guess (maven/gradle/none) for projects **without** a config, used by `--sync`. |

### Image build / naming
| Function | Role |
|---|---|
| `image_tag_for_project` | `claude-task-<project>:latest`. |
| `container_name_for` | `claude-<project>-<branch>` (both sanitized). |
| `config_hash` / `needs_rebuild` | Hash the rendered Dockerfile; compare against the image's `com.claude-task.config-hash` label. |
| `build_project_image` | Build the project image if forced or hash mismatch. |
| `ensure_global_image` | Fallback for unconfigured projects: build locally if inside claude-container, else pull the GHCR base image. |

### Container run
| Function | Role |
|---|---|
| `build_run_args` | Assembles the `docker run` argument array: mounts (worktree → `/workspace`, global Claude auth, m2 cache, main `.git`), env (`GH_TOKEN`, git identity, `TZ`, `VAADIN_PRO_KEY`, `NOTIFICATION_URL`), TTY (interactive only), firewall. |
| `running_container` | Is the named container currently up? |
| `cmd_start` | Backs `<branch>` / `--plan` / `--shell`. |
| `cmd_done` | Backs `--done` (with safety checks). |
| `cmd_sync` | Backs `--sync` (headless rebase/test/push/PR). |

### `--init` scaffolding
Renders and writes all machine-owned files:
`render_dockerfile`, `write_devcontainer_json`, `write_devcontainer_env_example`,
`write_allowed_domains`, `mcp_server_json` / `write_mcp_json`,
`write_claude_settings`, `write_claude_md_skeleton`, `ensure_gitignore_entries`,
plus interactive helpers `ask_choice` / `sed_escape_replacement`, orchestrated by `cmd_init`.

### Distribution
`resolve_latest_tag`, `cmd_update` — fetch the latest release of `bin/claude-task` and replace the installed file. `main` dispatches subcommands.

---

## Workflows

### 1. Spec **and** implement in one container, then PR to `main`

Author the task file and implement it in the same session; ship via PR.

```bash
# 1. Start a session on a NEW feature branch (worktree is created off HEAD)
claude-task feature/my-task
#    (or: claude-task --plan feature/my-task  to start in plan mode)

# 2. Inside the container / Claude session:
#    - Co-author the spec into tasks/my-task.md
#    - Implement it straight away on the same branch
#    - Commit your work (git commit ...)

# 3. Ship it: rebase onto origin/main, run tests, push, open the PR
claude-task --sync feature/my-task     # needs GH_TOKEN with repo write scope

# 4. Merge the PR on GitHub, then clean up
claude-task --done feature/my-task
```

Notes:
- `tasks/` is **gitignored** — the spec stays in the worktree, never reaches
  `main`, and never blocks `--done`/`--sync`.
- Do **not** run the `task-spec` skill here; it is built for the split flow
  below and stops on a feature branch.

---

### 2. Split flow: write the spec in one dev container, implement in another

Useful when spec authoring and implementation happen in separate sessions
(e.g. different people or different times).

```bash
# --- Container A: author the spec ---
claude-task --plan spec/my-task        # plan mode, worktree off HEAD
#    Inside: co-author tasks/my-task.md (the task-spec skill fits here).
#    Because tasks/ is gitignored, the spec is NOT shared via git.
```

The spec is untracked, so to move it to the implementation worktree you copy
the file across the sibling worktree directories on the host:

```bash
# On the host, copy the spec into the implementation branch's worktree.
# Worktrees live at <parent-of-repo>/<repo>-worktrees/<branch>/
cp ../<repo>-worktrees/spec/my-task/tasks/my-task.md \
   ../<repo>-worktrees/feature/my-task/tasks/   # create feature worktree first (step below)
```

```bash
# --- Container B: implement the spec ---
claude-task feature/my-task            # new worktree off HEAD (creates the dir)
#    Inside: implement tasks/my-task.md, commit the code.

# Ship + clean up
claude-task --sync feature/my-task
claude-task --done feature/my-task
# Optionally clean up the spec worktree too:
claude-task --done spec/my-task
```

Tip: if you genuinely want the spec versioned/shared through git, commit it
with `git add -f tasks/my-task.md` (forces past the ignore rule) — but then it
rides along into `main` on merge.

---

### 3. Work on **multiple** task files / branches in parallel

Each branch is fully isolated (own worktree, own container, shared Maven
cache). Just start one session per branch — they don't collide.

```bash
claude-task feature/task-a       # terminal 1
claude-task feature/task-b       # terminal 2
claude-task feature/task-c       # terminal 3
```

- Containers are named `claude-<project>-<branch>`, so they coexist.
- The Maven cache is shared across all worktrees of the project
  (`<main-repo-root>/.devcontainer/m2-cache`, file-lock safe), so a
  dependency downloaded on one branch is instantly reused on another.
- Peek into a running session without disturbing Claude:
  `claude-task --shell feature/task-a` (attaches a second terminal).
- Sync/clean each branch independently:
  `claude-task --sync feature/task-a`, `claude-task --done feature/task-a`.
- `--sync` is headless (no TTY), so it can run **alongside** a live
  interactive session on the same or another branch.

---

### 4. Resolve **merge/rebase conflicts** against `main`

`--sync` never auto-resolves conflicts — it hands the branch back for
interactive resolution.

```bash
claude-task --sync feature/my-task
#   -> exits with code 10 on a rebase conflict:
#      "Rebase conflict — resolve interactively: 'claude-task feature/my-task' ..."

# 1. Reopen the branch interactively. The in-progress rebase persists,
#    because the main repo's .git is bind-mounted into the container.
claude-task feature/my-task
#    Inside: `git status` already shows the conflict. Resolve it, e.g.:
#      <edit conflicted files>
#      git add <files>
#      git rebase --continue
#    (or ask Claude to resolve the conflicts for you)

# 2. Re-run sync to finish (test + push + PR)
claude-task --sync feature/my-task
```

If you'd rather bail out of the rebase entirely, run `git rebase --abort`
inside the interactive session.

---

### 5. **Pause** and **resume** a task

There is no explicit "pause" command — pausing = stopping the container while
**keeping** the worktree (and its uncommitted state) intact.

```bash
# Pause: just exit Claude / close the container (Ctrl-D or /exit).
# The container is --rm'd, but the worktree and all its files remain on disk.

# Best practice before a long pause: commit your progress so nothing is lost.
#   git commit -am "wip: ..."   (inside the session)

# Resume later — same command, same branch. The existing worktree is reused
# (no new checkout), so your files / in-progress work are exactly as you left them.
claude-task feature/my-task
```

Key point: **do not** run `--done` if you want to resume — that removes the
worktree. Simply exiting the session pauses it; re-running `claude-task
<branch>` resumes it.

---

### 6. **Stop** a task (finished / abandon)

`--done` stops the container and removes the worktree.

```bash
claude-task --done feature/my-task
```

Safety checks (refuses unless clean):
- **Uncommitted changes** present → aborts.
- **Commits not pushed** to the upstream → aborts.
- A branch with **no upstream** skips the push check but still requires a
  clean worktree.

Force removal (discard the safety net — you lose uncommitted/unpushed work):

```bash
claude-task --done --force feature/my-task
```

The **branch is never deleted** — only the worktree and container. Delete the
branch yourself when done:

```bash
git branch -d feature/my-task           # or -D to force
git push origin --delete feature/my-task
```

---

## Quick reference — one task, start to finish

```bash
claude-task --init                 # once per project: scaffold config, commit it
claude-task feature/x              # start: spec + implement + commit
# ... exit to pause; re-run the same command to resume ...
claude-task --sync feature/x       # rebase + test + push + PR  (needs GH_TOKEN)
#   on conflict: claude-task feature/x  -> resolve -> claude-task --sync feature/x
# merge PR on GitHub
claude-task --done feature/x       # stop container, remove worktree
git branch -D feature/x            # delete the branch (manual)
```

## Requirements / gotchas

- `--sync` requires `GH_TOKEN` (repo write scope) exported on the host.
- Task specs go in `tasks/` and are **gitignored** by design.
- Project images rebuild automatically when the config/Dockerfile changes;
  use `--rebuild` to force a pull of a new upstream base image.
- Worktrees are siblings of the repo: `<parent>/<repo>-worktrees/<branch>/`.
