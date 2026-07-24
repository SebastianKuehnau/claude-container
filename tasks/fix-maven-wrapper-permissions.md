# Fix Maven/Gradle wrapper usability inside claude-task containers

## Task

Make the project build-tool wrappers `./mvnw` and `./gradlew` reliably usable
inside a `claude-task` container session, so an agent does not have to fall
back to the image-provided `mvn`/`gradle` by hand.

Observed symptom (host, real Java project via `claude-task <branch>`): `./mvnw`
is unusable due to wrapper permissions ("Wrapper-Rechte"); the manual
workaround is the image's system Maven in offline mode (`mvn -o`). The
`--sync` path already tolerates this with `if [[ -x ./mvnw ]]; then ./mvnw …;
else mvn …; fi` (`bin/claude-task:547`), but an **interactive** session gets no
equivalent safeguard, so the wrapper simply fails.

The fix must address the **root cause in the setup** (a change to
`claude-container`: the image entrypoint and/or `bin/claude-task`), not merely
document a workaround. It must not introduce a spurious `git status` change in
the target project's worktree.

## Context

- **Repository:** `claude-container` (this repo). It is the container/devcontainer
  setup for `claude-task`; it contains **no** Java project, no `pom.xml`, and no
  `mvnw`. The bug therefore reproduces only against a *separate* Java project run
  through `claude-task`, never against this repo's own tree.
- **How a session mounts the project:** `build_run_args` in `bin/claude-task`
  bind-mounts the host git worktree at `/workspace` with `:delegated`
  consistency (`bin/claude-task:314`); the container runs as user `node`.
- **Container entrypoint:** `.devcontainer/scripts/entrypoint.sh` is baked to
  `/usr/local/bin/entrypoint.sh` and is the `ENTRYPOINT` for the `base`/`dind`
  targets (`.devcontainer/Dockerfile:164,179,237`). It runs on every start as
  `node`, with `/workspace` already mounted, and ends with `exec "$@"`. This is
  the natural container-side hook point. The OpenCode variant has a **separate**
  entrypoint, `.devcontainer/scripts/entrypoint-opencode.sh`
  (`.devcontainer/Dockerfile:206`); any entrypoint-side change must keep the two
  in sync (shared sourced snippet, or the same logic in both).
- **Existing precedent to mirror:** the `-x ./mvnw` guard and system-tool
  fallback in `cmd_sync` (`bin/claude-task:546-551`), and `detect_build_tool`
  (`bin/claude-task:211-220`) which already recognizes `mvnw`/`pom.xml` and
  `gradlew`/`build.gradle`.
- **Why it matters:** interactive `claude-task` sessions on Java/Vaadin projects
  are the primary daily workflow (`docs/working-with-tasks.md`). A wrapper that
  silently fails wastes time on every session.

## Implementation frame

Boundaries and constraints — the execution run makes its own plan within these:

- **Scope of the fix:** both `mvnw` and `gradlew`. Treat them symmetrically.
- **All code changes live in `claude-container`** (this repo): `bin/claude-task`
  and/or `.devcontainer/scripts/*` and/or the generated templates. No changes to
  any target/fixture project are committed.
- **No spurious git diff.** Whatever restores wrapper usability must not turn a
  clean target worktree dirty. Git tracks a wrapper's executable bit in its mode
  (`100755` vs `100644`); blindly `chmod +x` a file that git tracks as `100644`
  would show as a modification. The fix must leave `git status --porcelain`
  empty in the target worktree after the wrappers have been used.
- **Idempotent and safe when absent.** Do nothing (no error) when the project has
  no `mvnw`/`gradlew`. Never touch files outside `/workspace`.
- **Entrypoint symmetry.** If the fix lives in the entrypoint, cover both
  `entrypoint.sh` and `entrypoint-opencode.sh` (or factor a shared snippet).
- **Preserve existing behavior.** The `cmd_sync` fallback, `detect_build_tool`,
  firewall init, and the rest of the entrypoint flow must keep working.
- **Do not weaken the firewall** except, if diagnosis proves the wrapper's Maven
  distribution download is the (or a) cause, by adding the specific
  already-relevant distribution host(s) to `allowed-domains.conf`. Do not open
  broad ranges.

### Open question — decided at the plan gate (root-cause gate), not now

**Where the fix lives** depends on the confirmed root cause and is the single
design decision deferred to the plan gate:

- **container-side** (entrypoint restores the wrapper's executable bit for
  `/workspace/{mvnw,gradlew}` when present), vs.
- **host-side** (`bin/claude-task` normalizes the wrapper mode right after
  `find_or_create_worktree`, before `docker run`), vs.
- a **distribution/firewall** adjustment, if the cause turns out to be the
  wrapper's Maven download being blocked rather than a permission bit.

Do not pre-decide this in the plan; decide it after Gate 1 (below) has
confirmed the actual cause against a reproduction.

## Preconditions (hard — check first, abort and report if unmet)

1. **Working Docker.** `docker info` must succeed and the environment must be
   able to build the base image and run containers. A plain `base` container has
   no Docker daemon — if that is where execution landed, stop and report that
   this task must run on the host (or in a Docker-host/`dind`-capable
   environment). Do not attempt a partial, unverifiable fix.
2. **Base image buildable.** `docker build -f .devcontainer/Dockerfile --target
   base …` (as `ensure_global_image` does) must succeed, so the fix can be baked
   and exercised.

If either precondition is unmet, abort before any code change and report exactly
what is missing.

## Procedure

1. **Plan first.** Produce a step-by-step plan and **wait for explicit
   approval** before touching any file.
2. **Gate 1 — root cause (mandatory approval gate).** Before choosing the fix
   location:
   - Build a **minimal throwaway fixture** (see Fixture policy) as a standalone
     git repo on the host, containing a minimal Maven project with a working
     `./mvnw` and a minimal Gradle project (or combined project) with a working
     `./gradlew`.
   - Run it through `claude-task` and **reproduce the failing state** inside the
     container (capture the exact command and its output — e.g. `./mvnw
     -version` failing, and `ls -l mvnw` / `stat` showing the mode/owner). If the
     environment does not reproduce it naturally, establish a **deterministic
     failing baseline** by simulating the reported condition (e.g. committing/
     setting the wrapper mode to non-executable) and record that this was
     simulated.
   - State the confirmed root cause in one or two sentences and **wait for
     approval** of the chosen fix location. A wrong choice here is expensive
     (image rebuild + re-verification), which is why this gate exists.
3. **Implement** the approved fix, with a **commit after every verified step**
   (Conventional Commits, English, **no push**). Rebuild the base image and
   re-run the fixture to verify each behavioral change.
4. **Update docs** in the same run: `CLAUDE.md` and
   `docs/working-with-tasks.md` to describe the new wrapper-usability behavior
   (the `Stop` hook expects `CLAUDE.md` to stay in sync).

## Fixture policy

- The fixture is a **standalone throwaway git repo** created in a temp location
  on the host (e.g. `mktemp -d`), **never committed to `claude-container`** and
  never added to this repo's tree.
- It must contain real, runnable wrappers: `mvnw` + `.mvn/wrapper/…` and
  `gradlew` + `gradle/wrapper/…`. Generating them via the wrapper tooling
  (`mvn -N wrapper:wrapper`, `gradle wrapper`) inside a container is acceptable;
  the exact generation mechanism is the execution run's choice.
- Verification logs are **date-stamped** (e.g. `verify-YYYY-MM-DD.log`), written
  outside this repo or under a gitignored path, and **not committed**. Re-runs
  overwrite the same-day file (idempotent).

## Definition of Done

Every item is checkable by a command or an artifact. All are unconditional
(the preconditions above already guaranteed availability).

1. **Wrappers work unattended.** In a freshly started `claude-task` container
   for the fixture project, `./mvnw -version` **and** `./gradlew --version` both
   exit `0` **without any manual `chmod`**. Captured in the date-stamped
   verification log.
2. **No spurious git diff.** After running both wrappers in that session,
   `git -C <fixture-worktree> status --porcelain` prints nothing (the fix
   introduces no tracked-file mode change).
3. **Root cause recorded.** The completion report names the confirmed root
   cause and whether reproduction was natural or simulated, quoting the observed
   failing-baseline output.
4. **No-op when absent.** Starting a container for a project with **no**
   `mvnw`/`gradlew` produces no error from the new logic and no change to
   `git status` (verify against this repo's own worktree, which has neither).
5. **Existing paths intact.** `cmd_sync`'s `-x ./mvnw` fallback
   (`bin/claude-task:547`) and `detect_build_tool` are unchanged in behavior;
   confirm by inspection and, if `--sync` is exercised, a green run.
6. **Entrypoint symmetry** (only if the fix is entrypoint-side): the wrapper
   logic is present for **both** the `base` and the `opencode` entrypoints;
   confirm by `grep`.
7. **Scripts parse.** `bash -n` is clean on every changed shell script
   (`bin/claude-task` and any `.devcontainer/scripts/*` touched).
8. **Docs updated.** `CLAUDE.md` and `docs/working-with-tasks.md` describe the
   new behavior; confirm by `git diff`.

## Final report

The completion message must contain:

- The **confirmed root cause** (one to two sentences) and whether the failing
  baseline was reproduced naturally or simulated, with the quoted observed
  output.
- The **fix location chosen at Gate 1** and why (container entrypoint vs.
  host-side `claude-task` vs. distribution/firewall).
- The DoD checklist with the exact command output proving items 1, 2, 4, 7
  (and 5/6 where applicable), plus the path to the date-stamped verification log.
- The list of committed changes (files + commit subjects), and an explicit note
  that nothing was pushed.
- **Decisions deferred to the maintainer:** whether to backport the same
  guard/behavior into `cmd_sync` for full symmetry, and whether a follow-up is
  warranted for Gradle cache sharing (a separate known limitation in
  `docs/working-with-tasks.md`) — list these, do not act on them.
