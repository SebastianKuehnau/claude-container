# Task
Extend `claude-task` with a project scaffolding command: running `claude-task
--init` inside a fresh project interactively sets up an individual, committed
container configuration (Java version, build tool, firewall profile, MCP
servers, skills, plugins) — and afterwards the existing daily workflow
(`claude-task <branch>`) automatically uses that project-specific setup.
Additionally, solve the distribution problem: `claude-task` must be
installable on a new machine without cloning the claude-container repository,
documented in a README.

This is an exploration-first (L-class) task: several mechanisms need to be
evaluated against the real tooling before implementation. Run the exploration
in plan mode and present the findings and your chosen approach as the plan.

# Context
- Repository: claude-container (home of the `claude-task` script, the base
  image Dockerfile, and the docs).
- Current state: one global base image (`IMAGE=` variable in the script),
  global Maven cache `~/.claude-m2-cache`, shared Claude auth state in
  `~/.claude-container/` (must stay global — auth is account state, not
  project state).
- Established principle: project-individual Claude configuration (skills,
  commands, settings, `.mcp.json`, CLAUDE.md, project-scoped plugins) lives
  as files in the project repo and needs no image customization. `--init`
  scaffolds these files; the container only provides the toolchain.

# Exploration questions (answer these in the plan, with evidence)
1. **Per-project image mechanism:** generated project Dockerfile
   (`FROM <base-image>` + SDKMAN/apt for the chosen Java/build tool) built
   via plain `docker build`, versus using the devcontainers CLI so the
   project's `devcontainer.json` features (e.g.
   `ghcr.io/devcontainers/features/java` with version + Maven/Gradle options)
   are honored. Evaluate: startup latency, IntelliJ compatibility of the
   resulting `devcontainer.json`, complexity added to the script. Recommend
   one; the other may be noted as future option.
2. **Interactive prompts:** which questions, which defaults (suggest: Java
   17/21/25, Maven/Gradle, firewall open/allowlist, MCP servers from a small
   curated list, plugins as marketplace references for project scope). Keep
   it answerable in under a minute.
3. **Distribution:** how to install `claude-task` standalone — e.g. a
   one-line install via `curl` from the repository's raw URL or a tagged
   release into `~/.local/bin`, with a `claude-task --update` self-update.
   Evaluate against Homebrew tap (probably overkill) and document the chosen
   path.
4. **Worktree-safe project cache:** the Maven cache moves to
   `$MAIN_REPO/.devcontainer/m2-cache`, shared by all worktrees of that
   project but isolated between projects. Verify how to resolve the main
   repo path from inside a worktree (`git rev-parse --git-common-dir` or
   equivalent) so the mount is identical for main checkout and worktrees.

# Implementation frame
1. `claude-task --init`:
   - Asks the interactive questions; generates and stages (not commits):
     `.devcontainer/devcontainer.json` (+ Dockerfile if that approach wins),
     `.devcontainer/init-firewall.sh` per chosen profile, `.mcp.json`,
     `.claude/settings.json` skeleton (permissions incl. the deny-list
     baseline), `CLAUDE.md` skeleton, `tasks/` directory, and `.gitignore`
     entries (`.devcontainer/m2-cache/`, `.devcontainer/devcontainer.env`).
   - Prints a summary and the commit command; does not commit on its own.
   - Is idempotent: re-running on an initialized project must not overwrite
     existing files without an explicit `--force`.
2. Project-aware start: `claude-task <branch>` detects a project config,
   builds the project image on first use (image and container names carry
   the project name, e.g. `claude-task-<project>` /
   `claude-<project>-<branch>`), rebuilds when the config changed
   (checksum or `--rebuild` flag — decide in the plan), and mounts the
   project cache from the main repo path. Projects **without** a config
   keep the current behavior (global image, global cache) — full backwards
   compatibility.
3. Auth, `--plan`, `--shell`, `--done` behavior unchanged.
4. Documentation:
   - README section "Install" — standalone install without cloning the repo,
     one command, plus update path.
   - README section "New project" — `claude-task --init` walkthrough with
     the questions and the generated files explained.
   - Update docs/working-with-tasks.md and the runbook only where behavior
     changed (project image, project cache); no duplication.

# Procedure
1. Exploration in plan mode; present findings + chosen approach as the plan.
   Wait for my explicit approval before any file changes.
2. Implement in verified steps, committing after each (Conventional Commits,
   no push): (a) project cache + project-aware start, (b) `--init`
   scaffolding, (c) distribution/install, (d) docs.
3. Verify autonomously against the Definition of Done before reporting done.

# Definition of Done
- In a fresh throwaway test project: `claude-task --init` (answering e.g.
  Java 21 + Maven) produces the files listed above; `git status` shows them
  staged; nothing outside the project was modified.
- `claude-task test/init-smoke` in that project builds/uses an image named
  after the project, and inside the container `java -version` and the chosen
  build tool match the `--init` answers.
- The Maven cache lands in `<main-repo>/.devcontainer/m2-cache` and a second
  worktree of the same project reuses it (verify: artifact downloaded in
  worktree A is present in a container for worktree B without re-download).
- A project without `.devcontainer` config still starts with the global
  image and global cache (regression check).
- Re-running `--init` without `--force` refuses to overwrite and says why.
- Install path verified: on a simulated clean setup (e.g. temp HOME or a
  container), the documented one-line install yields a working `claude-task`
  in `~/.local/bin` without cloning the repository.
- `bash -n` and shellcheck clean; README sections exist and match the
  actually implemented behavior.

# Final report
Commits with one-liners; the answers to the four exploration questions and
what tipped each decision; the exact install one-liner; a transcript snippet
or file listing proving the worktree cache reuse; open questions (e.g.
Gradle cache handling, Homebrew tap later, team image consolidation with
Petri's/Stefan's templates).
