# Task Spec: YOLO (bypass) as the default permission mode for claude-task

## Task

Make containerized Claude Code sessions run **uninterrupted by default**. Today a
`claude-task` session starts in Claude Code's `plan` permission mode, so Claude
keeps asking the user before reading sources or using libraries. Change the
default so that `claude-task <branch>` launches Claude Code with permission
prompts fully bypassed ("YOLO" / `--dangerously-skip-permissions`), letting it
work autonomously and only stop to consult the user for decisions that affect the
*solution* of the task — not for routine tool/source/library access.

The bypass must remain safe because it only removes *prompts*; it must not widen
what the sandbox allows. The existing safety layers (firewall allowlist, the
`permissions.deny` rules, no host filesystem access) stay fully in force.

Scope of the change:

1. `claude-task <branch>` (no modifier) → start Claude Code in **bypass** mode.
2. `claude-task --plan <branch>` → **unchanged**: deliberate plan-first review.
3. `claude-task --shell <branch>` → **unchanged**.
4. New optional, committed opt-out: a `permissionMode` field in
   `.devcontainer/claude-task.json` that lets a project override the no-modifier
   default per repository.
5. Remove the hard `defaultMode = "plan"` pin from the container entrypoint so
   the launch command (set by `claude-task`) is the single source of truth.

## Context

- **`bin/claude-task`** — the standalone per-branch/worktree launcher.
  - `cmd_start()` (around `bin/claude-task:370`) resolves the worktree, image and
    firewall, then builds `RUN_ARGS` and `exec docker …`.
  - The launch mapping is the `case "$mode"` block (`bin/claude-task:420-425`):
    `claude) … claude`, `plan) … claude --permission-mode plan`,
    `shell) … /bin/zsh`. This is where the bypass flag belongs.
  - Dispatch (`bin/claude-task:1084-1108`): `--plan`→`cmd_start plan`,
    `--shell`→`cmd_start shell`, default → `cmd_start claude`.
  - `usage()` text (`bin/claude-task:36-55`) documents the modes/modifiers.
  - `cfg_get()` (`bin/claude-task:161`) is the generic reader for
    `claude-task.json`; `firewall` and `buildTool` are read this way in
    `cmd_start`. The new `permissionMode` field is read the same way.
  - `--init` writes `claude-task.json` via the `jq -n` schema at
    `bin/claude-task:981-988` (`{version,name,variant,java,buildTool,firewall,
    mcpServers,plugins,passthroughEnv}`). `permissionMode` is added here.
  - `write_claude_settings()` (`bin/claude-task:869-880`) writes the per-project
    `.claude/settings.json` with the `permissions.deny` list
    (`Bash(rm -rf *)`, `Bash(curl * | *sh*)`, …). **These deny rules still block
    even under bypass** — the key safety property to preserve and verify.

- **`.devcontainer/scripts/entrypoint.sh`** — the base/dind entrypoint.
  - Lines **127-139** unconditionally pin `permissions.defaultMode = "plan"`
    into `~/.claude/settings.json` on every start, with the comment
    "never bypass mode". This block is what forces plan mode regardless of what
    `claude-task` passes, and must be removed/reversed.
  - `~/.claude` is a **persistent host bind mount**
    (`bin/claude-task:311`, `source=…/.claude-container/claude` in the
    `devcontainer*.json` files). So a previously-pinned
    `permissions.defaultMode: "plan"` **persists on the host** across `--rm`
    runs; the entrypoint must not leave a stale value that contradicts the
    launched mode.

- **Docs that mention the plan default / permission behavior**:
  `CLAUDE.md` (claude-task section), `docs/working-with-tasks.md`, and the
  entrypoint comment block. A `Stop` hook
  (`.claude/hooks/claude-md-sync.sh`) checks that code/config changes come with a
  `CLAUDE.md` update.

- **Non-goals** (explicitly out of scope):
  - OpenCode: `entrypoint-opencode.sh` has no plan pin and `claude-task` never
    launches OpenCode — leave it untouched.
  - `docker-compose.yml` / `devcontainer*.json` direct usage: after the pin is
    removed these start Claude in its built-in default (prompting) mode. They do
    **not** get automatic bypass (they lack the worktree-isolation model and
    dind runs privileged). No bypass wiring is added there.

## Implementation frame

Boundaries and constraints — the execution run makes its own detailed plan.

- **Permission-mode model.** Three underlying launch variants:
  - `bypass` → `claude --dangerously-skip-permissions`
  - `plan`   → `claude --permission-mode plan`
  - `ask`    → `claude` (Claude Code's built-in default, prompts as usual)
- **Effective mode resolution** for `cmd_start` (both the project-config and the
  global/no-config code paths share the `case` block, so resolution must cover
  both):
  1. `--plan` modifier → always `plan` (CLI intent wins).
  2. else `permissionMode` from `claude-task.json` (`bypass` | `plan` | `ask`).
  3. else built-in default → `bypass`.
  - An unknown `permissionMode` value must fail fast with a clear error, not
    silently fall through.
  - Accepted limitation (do not build around it): when a project pins
    `permissionMode: plan`/`ask` there is no per-invocation flag to force bypass
    for one run. Note it in the final report as a possible future `--yolo`
    override; do not implement it now.
- **Entrypoint.** Remove the plan-pin block. Because `~/.claude` is a persistent
  mount, the entrypoint must also ensure no stale, contradicting
  `permissions.defaultMode` survives (e.g. delete the key so the launched CLI
  flag is authoritative). Do not otherwise rewrite unrelated settings.
- **Config field.** `permissionMode` is optional; absent means `bypass`. `--init`
  scaffolds it (in the `jq -n` schema and/or documented default) so the opt-out
  is discoverable. An explicit empty/omitted field keeps the bypass default.
- **Safety invariants that must not change:** firewall allowlist behavior,
  `init-firewall.sh`, the `permissions.deny` list, and host isolation. Bypass
  removes prompts only.
- **`--dangerously-skip-permissions` viability:** Claude Code runs as the
  non-root `node` user in this image, so the root-refusal for that flag does not
  apply. The execution run must confirm empirically that the flag is accepted and
  suppresses prompts.
- Keep the change minimal and in the style of the surrounding bash (same quoting,
  `die`/`info` helpers, `cfg_get` usage). No new dependencies.

### Hard preconditions (check at the very start; abort and report if unmet)

- `docker` is available and the execution environment can build and run the
  project image. The end-to-end verification (below) requires launching a
  container; if Docker is unavailable, **abort and report** rather than shipping
  a half-verified change.
- `jq` is available (already a runtime dependency of `claude-task`).

## Procedure

1. **Plan first.** Produce a concrete implementation plan (files, exact
   mode-resolution logic, config-field wiring, entrypoint edit, doc updates) and
   **wait for explicit approval before writing any code.**
2. Implement in small steps; after each **verified** step make one commit
   (Conventional Commits, English, no push).
3. **Mid-task gate (single, mandatory).** After the launch-mapping change in
   `claude-task` and the entrypoint pin removal are in place, run the end-to-end
   smoke test and confirm empirically that:
   (a) a plain `claude-task <branch>` session starts with **no** permission
   prompt for a routine file read / library use, and
   (b) `claude-task --plan <branch>` still starts in plan mode.
   Report the observed behavior and wait for approval before proceeding to the
   `permissionMode` config field and documentation. This is the point where a
   wrong assumption about `--dangerously-skip-permissions` becomes expensive.
4. Finish the config field, `--init` scaffolding, and documentation; commit.

## Definition of Done

Each item is verifiable by a command, an inspection, or an artifact.

1. **Default is bypass.** For a no-modifier start with no `permissionMode` in
   config, the constructed launch command contains `claude
   --dangerously-skip-permissions`. Verify by inspecting the resolved
   `RUN_ARGS`/launch command and by an actual container run that reads a file /
   uses a library **without** any permission prompt.
2. **`--plan` unchanged.** `claude-task --plan <branch>` launches
   `claude --permission-mode plan`; a started session is in plan mode.
3. **Entrypoint pin removed.** `grep -n "defaultMode" .devcontainer/scripts/entrypoint.sh`
   no longer shows the hard `= "plan"` pin, and a freshly started container's
   `~/.claude/settings.json` does **not** carry `permissions.defaultMode: "plan"`
   (stale value from a prior run is cleaned up on start).
4. **Config opt-out honored.** With `permissionMode: "plan"` in
   `claude-task.json`, a no-modifier start launches in plan mode; `"ask"` starts
   in the prompting default; absent/`"bypass"` starts in bypass. An explicit
   `--plan` overrides the field. An invalid value aborts with a clear error.
5. **Deny rules survive bypass.** Under a bypass session, a denied command
   (e.g. matching `Bash(rm -rf *)`) is still blocked — confirmed by inspecting
   that `write_claude_settings` still emits the `permissions.deny` list and by a
   run showing the denied command is refused, not silently executed.
6. **Firewall unchanged.** `init-firewall.sh` and firewall wiring are untouched
   (`git diff` shows no changes there); a non-allowlisted domain is still blocked
   in a running container.
7. **`--init` scaffolds the field.** `claude-task --init` produces a
   `claude-task.json` whose schema includes/documents `permissionMode` with the
   bypass default; regenerating an existing config does not corrupt it.
8. **Syntax clean.** `bash -n bin/claude-task` and `bash -n
   .devcontainer/scripts/entrypoint.sh` pass.
9. **Docs in sync.** `usage()`, the `CLAUDE.md` claude-task section, and
   `docs/working-with-tasks.md` describe the new default and the `permissionMode`
   field; the `claude-md-sync` Stop hook reports no outstanding drift.

## Artifacts

- Committed: the code/config/doc changes above and this spec.
- Not committed / ignored: any smoke-test scratch worktrees, container logs, or
  temporary `claude-task.json` fixtures created for verification.

## Final report

The completion message must state:

- Which files changed and the final mode-resolution precedence
  (`--plan` > `permissionMode` > built-in `bypass`).
- The empirical result of the mid-task gate: proof that a default session runs
  without permission prompts and that `--plan` still plans (paste the observed
  evidence).
- Confirmation that the safety invariants held: `permissions.deny` still blocks
  under bypass, and the firewall allowlist is unchanged.
- The accepted limitation that a project pinned to `plan`/`ask` has no
  per-invocation bypass override, offered as a possible future `--yolo` flag
  (decision left to the user — do not implement unprompted).
- Any deviation from this spec, with the reason.
