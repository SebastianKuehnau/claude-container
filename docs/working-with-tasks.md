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

## Spec and implement in one session

You do **not** need one session to author a task spec on `main` and a second
to implement it. Because `claude-task <branch>` creates the worktree off the
current `HEAD` when the branch doesn't exist yet, a single session can do both:

```bash
claude-task feature/my-task     # (or --plan) — new worktree off HEAD
```

Inside that session you co-author the spec with Claude, prove its feasibility,
discuss it, and — after the plan gate — implement it straight away, all on the
feature branch. The spec is **committed to this branch** (it belongs in the
branch history and can be reviewed), but it never reaches `main`: `claude-task
--sync` strips the whole `tasks/` directory in a dedicated commit
(`chore: strip task spec before merge`) right before it pushes, so the branch
tip that opens the PR is spec-free while the spec stays reachable through the
branch's earlier commits.

Notes:
- The `task-spec` skill drives exactly this single-session flow (spec →
  feasibility → plan gate → implement) on the feature branch. Run it here.
- `tasks/` is intentionally **not** gitignored, so `git add tasks/<name>.md`
  works normally. You don't need `git add -f`, and you should not hand-carry
  the spec onto `main` — the strip-before-merge step in `--sync` is what keeps
  `main` clean.

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

**Host env passthrough:** the optional `passthroughEnv` array in
`claude-task.json` lists host environment variable *names* to forward into the
container. Each is passed via `-e NAME=$NAME` only when set and non-empty on the
host, so values stay in your shell and never get committed. When the field is
absent (or there is no config), the default set `OPENAI_API_KEY`,
`ANTHROPIC_API_KEY` is forwarded; an empty array (`[]`) forwards nothing.
`--init` seeds the field with the two defaults. This is a runtime concern and,
like the firewall profile, is excluded from the image hash. Forwarding a
non-default provider key may also require allowlisting its domain in
`allowed-domains.conf`.

**Container naming:** `claude-<name>-<branch>` (and the project image is
`claude-task-<name>:latest`). Both `<name>` and `<branch>` are sanitized
(lowercased, disallowed characters collapsed to `-`) to satisfy Docker's
naming rules — this is why a branch like `Feature/Foo_Bar` becomes
`feature-foo_bar` in the container name.

`<name>` resolves in this precedence:

1. **`CLAUDE_TASK_NAME`** in the git-ignored `.devcontainer/devcontainer.env`
   (read from the *main repo root*, so every worktree of the project resolves
   the same name) — a per-developer **local override**;
2. the committed **`name`** field in `.devcontainer/claude-task.json` — the
   team-canonical source, written by `claude-task --init`;
3. the **repository directory name** — the historical default.

With no override and no `name` field, resolution is byte-identical to the
old directory-derived behavior, so unconfigured projects are unaffected.

> **Caveat:** because the name is resolved fresh on every invocation,
> changing `CLAUDE_TASK_NAME` (or the config `name`) while a container is
> running orphans that container — its old name no longer resolves, so
> `claude-task --shell`/`--done` won't find it. Stop the session first
> (`claude-task --done <branch>`), then change the name. There is no
> auto-recovery.

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

### Build-tool wrapper exec bits

A git worktree is created on the host and bind-mounted into the container
(`:delegated`). The executable bit on the build-tool wrappers `mvnw` / `gradlew`
can be lost crossing that mount, so `./mvnw` fails and you'd have to fall back to
the image's `mvn`/`gradle` by hand. On every start the container entrypoint
restores that bit for `/workspace/mvnw` and `/workspace/gradlew` — but only for
wrappers git itself records as executable (index mode `100755`), so it never
turns a clean worktree dirty. A wrapper git tracks as non-executable is left
untouched (that project is meant to use the system `mvn`/`gradle`). The `--sync`
path already guards this independently with `if [[ -x ./mvnw ]]; then ./mvnw …;
else mvn …; fi`.

## `--sync`: rebase, test, push, PR

`claude-task --sync <branch>` brings a finished branch up to date with the
current `origin/main` state without starting an interactive Claude session:

1. Refuses on uncommitted changes (like `--done`), and fails early if
   `GH_TOKEN` is unset (push and `gh pr create` both need it).
2. `git fetch origin` + `git rebase origin/main` — on conflict it aborts
   with exit code 10 and points you at `claude-task <branch>` for
   interactive resolution. The in-progress rebase persists (the main repo's
   `.git` is bind-mounted), so that session sees the conflict via
   `git status` immediately.
3. A test run matching the configured `buildTool` (`maven`/`gradle`/`none`).
   Projects without a `claude-task.json` get the build tool auto-detected
   from the worktree (`mvnw`/`pom.xml` → maven, `gradlew`/`build.gradle` →
   gradle, otherwise skipped).
4. **Strip the task spec before merge:** if `tasks/` is tracked, `git rm -r
   tasks/` + a dedicated `chore: strip task spec before merge` commit. The
   spec stays in the branch history (earlier commits) but is absent from the
   pushed tip, so it never lands in `main`. No-op if `tasks/` isn't tracked.
5. `git push --force-with-lease` (or `git push -u origin HEAD` for a branch
   that was never pushed).
6. `gh pr create --fill`, or a note if a PR already exists.

It runs in the same image/cache setup as `claude-task <branch>` — push and
PR work because `GH_TOKEN` + git identity are passed into every container
(see container-capabilities.md, `## 8. Persistent authentication & state`).
Unlike an interactive session it runs headless: no TTY is allocated, so
`--sync` can run alongside a live session for the same or another branch.

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
