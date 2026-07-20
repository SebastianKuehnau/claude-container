# Task Spec: Default env file + remove Playwright from the container

> This is a **task specification**. It is the single English source of truth
> for a later execution run. It contains **no implementation** — only what to
> build, the boundaries, and how "done" is proven. The execution run makes its
> own plan.

## 1. Task

Two independent changes to this container/devcontainer repository:

**A — Default env file (auto-seed instead of empty file).**
Today the devcontainer flow creates an **empty** `.devcontainer/devcontainer.env`
(`devcontainer.json` `initializeCommand` runs `touch …/devcontainer.env`), and
`bin/claude-task` only adds that path to `.gitignore` — it never creates or
consumes it. Change this so a **populated default** env file is seeded
(copy-if-missing) from a `devcontainer.env.example` template, both for this
repo's own devcontainer and for projects scaffolded by `bin/claude-task`.
Seeding must be idempotent and non-destructive (never overwrite a user's edited
file). The seeded file must be git-ignored everywhere it can appear.

**B — Remove Playwright completely from the container.**
Playwright is installed entirely in the shared `base-common` Dockerfile stage,
so every variant (`base`, `dind`, `opencode`, `opencode-dind`, and the
`claude-docker-host` service) inherits it. Remove Playwright **entirely** from
all images and perform a **full cleanup** of every downstream reference
(ports, firewall domains, helper script, entrypoint banners, devcontainer env,
docs, CI, `CLAUDE.md`). No variant keeps Playwright.

These two changes are unrelated; they are bundled only because they were
requested together. They may be implemented and committed independently.

## 2. Context

Repository: Docker image + VS Code dev container for running AI coding agents
(Claude Code / OpenCode) with Java/Vaadin tooling. Multi-stage Dockerfile:
`base-common` → `base`/`opencode`, then `dind` (from `base`) and
`opencode-dind` (from `opencode`).

### Part A — env file, affected code
- `/.devcontainer/devcontainer.json` — line 13 `initializeCommand` currently
  `touch`es an empty `devcontainer.env`; line 18 `runArgs` passes
  `--env-file …/devcontainer.env`.
- `/.devcontainer/devcontainer.env.example` — existing 3-line template
  (commented `GH_TOKEN`, `GIT_USER_NAME`, `GIT_USER_EMAIL`). This is the seed
  source; its content is used **as-is** (not enriched in this task).
- `/bin/claude-task`:
  - `build_run_args()` (~line 210) — the main `claude-task <branch>` run path;
    builds the `docker run` array and passes env as `-e` host variables
    (`TZ`, `GH_TOKEN`, `GIT_USER_NAME`, `GIT_USER_EMAIL`, `VAADIN_PRO_KEY`,
    `NOTIFICATION_URL`, …). It does **not** read any env file today.
  - `write_devcontainer_json()` (~line 464) — generated project devcontainer;
    currently has no `initializeCommand` and no `--env-file`.
  - `ensure_gitignore_entries()` (~line 650) — already appends
    `.devcontainer/devcontainer.env` to a scaffolded project's `.gitignore`.
  - `cmd_init()` (~line 655) — scaffolds a project's `.devcontainer/*`.
- `/.gitignore` (root) — ignores `.env`, `.env.local`, `.env.*.local` but
  **not** `.devcontainer/devcontainer.env`.

### Part B — Playwright, affected code (all references)
- `/.devcontainer/Dockerfile` — everything Playwright lives in `base-common`:
  - `ENV PLAYWRIGHT_BROWSERS_PATH` / `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD`
    (lines 21–22).
  - apt packages pulled in for Playwright: `procps`, `socat`, `libxcursor1`,
    `libgtk-3-0` (lines 48–54, with their comments).
  - `npm install -g playwright` + Chromium + `VERSION` file (lines 116–130).
  - `npm install -g @playwright/cli` + its Chromium + `VERSION` appends
    (lines 139–145).
  - chown/chmod of `/opt/playwright-browsers` (lines 149–152).
  - `su - node -c "playwright-cli install --skills claude"` (line 168).
  - zsh alias `playwright-info` (line 178).
  - Downstream stages `COPY playwright-info.sh …/playwright-info` and its
    `chmod`: `base` (218, 222), `opencode` (260, 262), `dind` (294, 302).
- `/.devcontainer/playwright-info.sh` — helper script (delete).
- `/.devcontainer/entrypoint.sh` and `entrypoint-opencode.sh` — read the
  `VERSION` file and print Playwright / CDP banner sections.
- `/docker-compose.yml` — port `9222:9222` in all five services;
  `/.devcontainer/docker-compose.yml` — port `9222:9222` in the `claude`
  service.
- Devcontainer JSONs — `forwardPorts:[9222]` + `portsAttributes` "Playwright
  CDP" in all four (`devcontainer.json`, `-dind`, `-opencode`,
  `-opencode-dind`); plus `containerEnv` `PLAYWRIGHT_*` in `devcontainer.json`,
  `-opencode`, `-opencode-dind`.
- `/.devcontainer/allowed-domains.conf` — Playwright download domains
  (lines 51–55). (`bin/claude-task`'s `write_allowed_domains` has no Playwright
  domains — nothing to change there.)
- `/bin/claude-task` — `-p "9222:9222"` in `build_run_args` (~line 230).
- `/README.md`, `/docs/container-capabilities.md`, `/CLAUDE.md` — Playwright
  documentation sections.
- `/.github/workflows/build.yml` — Playwright browser-launch and Agent-CLI/skill
  test steps (comment "base + opencode share the playwright layer").
- `/.github/dependabot.yml` — comment noting `playwright`/`@playwright/cli` are
  container-installed.

## 3. Implementation frame (boundaries, not steps)

**Part A**
- Seeding is **copy-if-missing** only (e.g. `cp -n` semantics): if
  `.devcontainer/devcontainer.env` already exists, it is left untouched. This
  is the non-destructive, idempotent contract.
- This repo's own `devcontainer.json` `initializeCommand` seeds from the
  existing `.devcontainer/devcontainer.env.example` instead of `touch`ing empty.
  Keep the rest of `initializeCommand` (the `~/.claude-m2-cache` /
  `~/.claude-container` setup) intact.
- `bin/claude-task` scaffolding: a project created by `--init` must (a) get a
  `.devcontainer/devcontainer.env.example` template, and (b) seed
  `.devcontainer/devcontainer.env` from it copy-if-missing, and (c) wire the
  generated `devcontainer.json` so the file is actually used
  (`initializeCommand` seed + `--env-file` in `runArgs`). The existing
  `ensure_gitignore_entries` already ignores the file — keep that.
- Add `.devcontainer/devcontainer.env` to the **root** `.gitignore` so this
  repo's own seeded file is never committed.
- **`build_run_args` env precedence is a plan gate (see §4).** The main
  `claude-task <branch>` path should be able to pick up the seeded
  `devcontainer.env`, but the exact wiring (whether/how `--env-file` is added
  and how it interacts with the existing `-e` host variables) must be approved
  before implementation, because it touches the primary run path and getting
  precedence wrong silently changes behavior for existing users. Default intent
  to propose at the gate: file provides defaults, explicitly-exported host
  variables win.
- Do **not** enrich `devcontainer.env.example` with new variables in this task,
  and do **not** switch the root `docker-compose.yml` to `env_file` — Part A is
  scoped to the devcontainer/`claude-task` `devcontainer.env` surface only.

**Part B**
- Remove Playwright from `base-common` so it disappears from every variant.
  There is no "keep it in one variant" — removal is total.
- The four apt packages (`procps`, `socat`, `libxcursor1`, `libgtk-3-0`) were
  added for Playwright per their inline comments. Remove them, but first
  **verify** (grep the repo + the image scripts) that nothing else depends on
  them; if a dependency is found, keep that package and note it in the final
  report. This verification is a required check, not a gate.
- Full cleanup covers all references listed in §2 Part B: Dockerfile, the
  helper script file, entrypoint banners, compose ports, devcontainer
  `forwardPorts`/`portsAttributes`/`containerEnv`, firewall domains,
  `claude-task` port mapping, README/docs/`CLAUDE.md`, and CI. After cleanup the
  only surviving mention of "playwright" anywhere in the tree may be in
  `tasks/` (this spec) — nothing else.
- `CLAUDE.md` update is mandatory (the repo's `Stop` hook enforces
  code↔`CLAUDE.md` sync): remove the "Playwright Setup" section and any
  Playwright bullets from the overview.

## 4. Procedure

1. **Preconditions (abort if unmet, report which):**
   - `docker` (and `docker-compose`/`docker compose`) available and able to
     build this repo's image locally.
   - Working tree clean at start.
2. **Plan first.** Produce a concrete implementation plan for both parts and
   **wait for explicit approval** before editing.
3. **Gate — `build_run_args` env wiring (Part A).** Within the plan, present
   the exact approach for how `bin/claude-task`'s run path consumes
   `devcontainer.env` and the resulting env-precedence rule. Do not implement
   the `build_run_args` change until this specific point is approved. (This is
   the only mid-task gate.)
4. Implement in small, verified steps. **Commit after every verified step**
   using Conventional Commits (`feat:`, `refactor:`, `docs:`, `chore:`).
   **No push.** Suggested commit boundaries (adjust as the plan dictates):
   - `feat: seed default devcontainer.env from example (repo devcontainer)`
   - `feat: seed and wire devcontainer.env in claude-task scaffolding`
   - `chore: gitignore .devcontainer/devcontainer.env`
   - `refactor: remove Playwright install from base-common image`
   - `chore: drop Playwright ports/domains/helper across variants`
   - `docs: remove Playwright references from README, docs, CLAUDE.md`
   - `ci: drop Playwright test steps from build workflow`
5. Run the Definition-of-Done checks; capture command output as evidence.

## 5. Definition of Done

Every item is verifiable by a command or artifact.

**Part A — env**
1. `git grep -n "touch .*devcontainer.env" .devcontainer/devcontainer.json`
   returns **nothing**; the `initializeCommand` instead performs a
   copy-if-missing seed from `.devcontainer/devcontainer.env.example`.
2. Fresh-seed test: with no `.devcontainer/devcontainer.env` present, running
   the repo's `initializeCommand` (or `devcontainer up --workspace-folder .`)
   creates `.devcontainer/devcontainer.env` whose contents equal
   `.devcontainer/devcontainer.env.example` (`diff` shows no differences).
3. Non-destructive test: write a sentinel line into
   `.devcontainer/devcontainer.env`, re-run the seed, confirm the sentinel is
   still present (file not overwritten).
4. `git check-ignore .devcontainer/devcontainer.env` succeeds (file is ignored)
   using the **root** `.gitignore`.
5. `bin/claude-task --init` in a throwaway git repo produces
   `.devcontainer/devcontainer.env.example`, a seeded
   `.devcontainer/devcontainer.env`, a generated `devcontainer.json` that
   references it (`--env-file` in `runArgs` and a seeding `initializeCommand`),
   and a `.gitignore` entry for it. Verify by inspecting the generated files.
6. `bash -n bin/claude-task` passes (script still parses).
7. The `build_run_args` change matches exactly what was approved at the §4 gate
   (verify by reading the diff against the gate decision).

**Part B — Playwright removed**
8. `git grep -in playwright -- ':!tasks/'` returns **no matches** anywhere in
   the tree (Dockerfile, scripts, compose, devcontainer JSONs, docs, CI,
   `CLAUDE.md`). Any surviving hit fails this item.
9. `git grep -n 9222` returns **no matches** outside `tasks/`.
10. `.devcontainer/playwright-info.sh` no longer exists
    (`test ! -e .devcontainer/playwright-info.sh`).
11. Image builds cleanly: `docker compose build claude` (base variant)
    succeeds.
12. Playwright is absent at runtime in the built base image:
    `docker compose run --rm claude bash -lc 'command -v playwright-cli; command -v playwright; ls /opt/playwright-browsers'`
    finds none of them (all three checks fail/empty inside the container).
13. Firewall allowlist has no Playwright download domains:
    `grep -in playwright .devcontainer/allowed-domains.conf` returns nothing.
14. CI workflow no longer contains Playwright steps:
    `git grep -in playwright -- .github/` returns nothing; the workflow YAML is
    still valid (e.g. parses / no orphaned steps).
15. `CLAUDE.md` no longer documents Playwright (covered by item 8) and the repo
    `Stop` sync hook does not flag an out-of-sync `CLAUDE.md`.

**Both**
16. Working tree is clean after the final commit; every change is committed via
    Conventional Commits; nothing pushed.

## 6. Final report

The completion message must state:
- Which commits were made (hashes + subjects), for Part A and Part B.
- Evidence for the key DoD checks: the two seed tests (fresh + non-destructive),
  the `git grep -in playwright` / `git grep -n 9222` empty results, and the
  runtime absence check inside the built image (item 12), with the actual
  command output.
- The image size before/after (if measurable) as evidence of the Playwright
  layer removal.
- The **approved** `build_run_args` env-precedence decision from the §4 gate,
  restated.
- The result of the apt-package dependency check (§3 Part B): whether
  `procps`/`socat`/`libxcursor1`/`libgtk-3-0` were removed or any kept, and why.
- **Deliberately left to the user (do not automate):**
  - Whether to publish/rebuild and push the GHCR base image after the
    Playwright removal (image publishing is out of scope here).
  - Whether a follow-up task should enrich `devcontainer.env.example` with the
    broader variable set (`TZ`, `VAADIN_PRO_KEY`, `NOTIFICATION_URL`, …) — noted
    as out of scope for this task.
  - Any push / PR creation.

## 7. Out of scope
- Enriching `devcontainer.env.example` content (kept as-is).
- Switching `docker-compose.yml` to `env_file`.
- Rebuilding/publishing the GHCR base image; any `git push` or PR.
- Reintroducing Playwright as a separate optional variant (explicitly not
  wanted — removal is total).
