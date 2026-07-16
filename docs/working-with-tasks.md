# Working with `claude-task`

`claude-task` runs Claude Code in a container, one git worktree per branch,
so multiple branches of the same project can have independent, isolated
sessions running in parallel without stepping on each other's working
directory. This document covers the daily workflow, how project-specific
configuration changes what gets built, and the mechanisms behind cache
sharing and cleanup safety. For installation and the `--init` question
flow, see the README's "Install" / "New project" sections.

## Daily workflow

```bash
claude-task <branch>          # start/attach a session for <branch>
claude-task --plan <branch>   # same, but start Claude explicitly in plan mode
claude-task --shell <branch>  # open a zsh debug shell instead of Claude
claude-task --done <branch>   # stop the container, remove the worktree
```

Each subcommand takes the branch name as its positional argument, plus
optional modifiers: `--rebuild` (force a project image rebuild even if
nothing changed) for the start commands, and `--force` (skip the
uncommitted/unpushed-work safety check) for `--done`.

### What happens on `claude-task <branch>`

1. Resolves the **main repository root** — the anchor used for cache and
   image identity — via `git rev-parse --path-format=absolute
   --git-common-dir`. This works identically whether you run `claude-task`
   from the main checkout or from any existing worktree, because
   `--git-common-dir` (unlike `--git-dir`) always points at the shared
   `.git` directory rather than a per-worktree one.
2. Finds or creates a git worktree for `<branch>` at
   `<parent-of-repo>/<repo-name>-worktrees/<branch>` (a sibling directory,
   not nested inside the repo itself — this keeps IDE indexing, `grep`
   sweeps, and git's own worktree bookkeeping simple). Branch resolution
   order: existing local branch → existing `origin/<branch>` (tracked) →
   new branch off the current `HEAD`.
3. Reads `.devcontainer/claude-task.json` **from that worktree's checkout**
   (not from the main repo root) — a branch can legitimately carry
   different config than another, e.g. a branch trying out a Gradle
   migration.
4. If the project has a config, builds/reuses a project-specific image
   (see below); otherwise falls back to the global image and cache,
   identical to this repo's behavior before `claude-task` existed.
5. Runs the container (`docker run -it --rm`), mounting the worktree at
   `/workspace`, the global Claude auth directories (always global — auth
   is account state, never project state), and the resolved Maven cache.

`--shell` on a branch whose container is already running attaches a second
terminal to it (`docker exec`) instead of starting a new one — handy for
poking around while a Claude session is active in another terminal.

## Project-specific images

A project that ran `claude-task --init` gets its own image,
`claude-task-<project>:latest`, built from the generated
`.devcontainer/claude-task.Dockerfile`:

```dockerfile
FROM ghcr.io/sebastiankuehnau/claude-container[-dind|-opencode]:latest
# ... SDKMAN layer installing the chosen Java version/vendor and build tool
```

This is a thin layer on top of the already-published, fully-baked base
image — no need to rebuild the whole toolchain, and no need to clone this
repository at all. `claude-task` drives `docker build`/`docker run`
directly; it never shells out to the devcontainers CLI (`devcontainer up`).
The generated `devcontainer.json` is for IDE attach (VS Code, IntelliJ
Gateway) only.

**Rebuild trigger:** a Docker image `LABEL`
(`com.claude-task.config-hash`) holds a hash of the rendered Dockerfile.
`claude-task` compares it via `docker image inspect` on every invocation
and rebuilds automatically on a mismatch — e.g. after re-running
`claude-task --init --force` with different answers. `--rebuild` forces a
rebuild (`--pull --no-cache`) regardless of the hash, for when the
*upstream* published base image changed and you want that update now. The
firewall profile is deliberately excluded from the hash — it's a runtime
mount/env concern, not baked into the image, so switching it never
triggers a rebuild.

**Container naming:** `claude-<project>-<branch>`, both sanitized
(lowercased, disallowed characters collapsed to `-`) to satisfy Docker's
naming rules — this is why a branch like `Feature/Foo_Bar` becomes
`feature-foo_bar` in the container name.

## Worktree-safe Maven cache

For a configured project, the cache lives at
`<main-repo-root>/.devcontainer/m2-cache` (gitignored) and is mounted into
every container for that project at `/home/node/.m2/repository` —
regardless of which worktree/branch started that container. Since the
mount point is always anchored at the *main repo root* (not the worktree),
a dependency downloaded while working on one branch is immediately
available to a container started from a different worktree of the same
project. This composes with the `MAVEN_OPTS` FS-safe file-locking already
baked into the base image (`-Daether.syncContext.named.factory=file-lock`),
which exists specifically to make concurrent Maven processes safe against
a shared, bind-mounted repository.

Projects without a `claude-task.json` keep using the global
`~/.claude-m2-cache`, exactly as before.

## `--done` safety checks

`claude-task --done <branch>` refuses to remove a worktree that has:
- **uncommitted changes** (`git status --porcelain` is non-empty), or
- **commits not yet pushed** to its upstream (if it has one).

In either case it prints the worktree path and exits non-zero without
touching anything — pass `--force` to remove it anyway. A branch with no
upstream configured skips the push check (there's nothing to compare
against) but still enforces the clean-worktree check. The branch itself is
never deleted, only the worktree and its container; delete the branch
manually once you're done with it.

## Known limitations

- **Gradle cache** isn't mounted yet — only `.m2/repository` is handled.
  A project with `"buildTool": "gradle"` gets Gradle installed via SDKMAN
  in its image, but Gradle's own cache directory isn't shared across
  worktrees the way Maven's is.
- **SDKMAN candidate resolution** (mapping e.g. `21` + `corretto` to a
  concrete SDKMAN candidate id like `21.0.5-amzn`) happens at `docker
  build` time via `sdk list java` parsing, since candidate ids drift with
  patch releases. This has not been verified against real SDKMAN output in
  every environment — if an image build fails at the "No SDKMAN candidate
  found" step, check `sdk list java` output inside a throwaway container
  and adjust the grep pattern in `render_dockerfile()` if the format has
  changed.
- **Bare-repository worktree layouts** are treated as best-effort, not a
  UX priority — the common case (a normal `git clone`) is what's tested.
