# Patch für bin/claude-task (aktueller main-Stand, 823 Zeilen)

Basiert auf dem Commit, der gerade auf `main` liegt. Betrifft vier Stellen:
Kopf-Kommentar, `usage()`, eine neue Funktion `cmd_sync()`, und den Dispatch
in `main()`. Reuse-Prinzip: `--sync` nutzt exakt dieselbe Image-/Cache-/
Mount-Logik wie `cmd_start`, führt aber statt `claude` einen festen Shell-
Befehl im Container aus — kein interaktiver Claude nötig für den mechanischen
Teil.

## 1. Kopf-Kommentar (Zeile 4–11) — Zeile ergänzen

```diff
 #   claude-task <branch>       Start (or attach to) a Claude Code session for <branch>.
 #   claude-task --plan <branch>    Same, but start Claude explicitly in plan mode.
 #   claude-task --shell <branch>   Open a zsh debug shell instead of Claude.
+#   claude-task --sync <branch>    Rebase onto origin/main, run tests, push, open/update PR.
 #   claude-task --done <branch>    Stop the container and clean up the worktree.
 #   claude-task --init [--force]   Scaffold a project-specific container config.
 #   claude-task --update           Self-update to the latest release.
```

## 2. `usage()` (Zeile ~34–41) — Zeile ergänzen

```diff
   claude-task --shell <branch>    Open a zsh debug shell instead of Claude.
+  claude-task --sync <branch>     Rebase onto origin/main, test, push, open/update PR.
   claude-task --done <branch>     Stop the container and clean up the worktree.
```

## 3. Neue Funktion `cmd_sync()` — direkt nach `cmd_done()` einfügen

Einfügepunkt: nach der schließenden `}` von `cmd_done()` (Zeile 365), vor dem
Kommentarblock `# --- --init scaffolding ---` (Zeile 367).

```bash
# --- --sync: rebase onto origin/main, test, push, open/update PR -----------
#
# Runs entirely inside the same per-project (or global) image/cache/mount
# setup as cmd_start — GH_TOKEN and git identity are already wired into the
# container via build_run_args, so push and `gh pr create` work from in
# here. No interactive Claude session is started; this runs a fixed shell
# command instead. Rebase conflicts are NOT auto-resolved — they're handed
# back to an interactive session (`claude-task <branch>`), since resolving
# them needs judgment a fixed script doesn't have.

cmd_sync() {
  local branch=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --*) die "Unknown flag for this command: $1" ;;
      *) branch="$1" ;;
    esac
    shift
  done
  [[ -n "$branch" ]] || die "Usage: claude-task --sync <branch>"

  require_git_repo
  local main_repo_root project worktree
  main_repo_root="$(resolve_main_repo_root)"
  project="$(project_name "$main_repo_root")"
  worktree="$(worktree_path "$main_repo_root" "$branch")"

  worktree_exists "$main_repo_root" "$worktree" \
    || die "No worktree found for branch '$branch' at $worktree"

  local dirty
  dirty="$(git -C "$worktree" status --porcelain)"
  [[ -z "$dirty" ]] || die "Worktree has uncommitted changes — commit them first (e.g. via 'claude-task $branch'):
  $worktree"

  local image_tag cache_dir firewall container_name build_tool test_cmd
  container_name="$(container_name_for "$project" "${branch}-sync")"

  if has_project_config "$worktree"; then
    local cfg; cfg="$(config_path "$worktree")"
    firewall="$(cfg_get "$cfg" '.firewall' 'allowlist')"
    build_tool="$(cfg_get "$cfg" '.buildTool' 'maven')"
    image_tag="$(image_tag_for_project "$project")"
    cache_dir="${main_repo_root}/.devcontainer/m2-cache"
    build_project_image "$worktree" "$image_tag" 0
  else
    firewall="allowlist"
    build_tool="maven"
    image_tag="$(ensure_global_image "$main_repo_root")"
    cache_dir="$GLOBAL_M2_CACHE"
  fi

  case "$build_tool" in
    maven)  test_cmd="./mvnw -q -ntp clean verify" ;;
    gradle) test_cmd="./gradlew -q clean check" ;;
    none)   test_cmd=":" ;;
    *) die "Unknown build tool: $build_tool" ;;
  esac

  local -a RUN_ARGS
  build_run_args "$worktree" "$image_tag" "$container_name" "$cache_dir" "$firewall" "$main_repo_root"

  RUN_ARGS+=("$image_tag" /bin/bash -lc "
    set -euo pipefail
    git fetch origin --quiet
    if ! git rebase origin/main; then
      echo 'CONFLICT: resolve interactively via: claude-task ${branch}' >&2
      exit 10
    fi
    ${test_cmd}
    git push --force-with-lease
    if gh pr view '${branch}' >/dev/null 2>&1; then
      echo 'PR already exists — branch is now up to date.'
    else
      gh pr create --fill
    fi
  ")

  info "Syncing '$branch' against origin/main (rebase + test + push + PR)..."
  local rc=0
  docker "${RUN_ARGS[@]}" || rc=$?

  if [[ "$rc" == 10 ]]; then
    die "Rebase conflict — resolve interactively: 'claude-task $branch', then re-run 'claude-task --sync $branch'."
  elif [[ "$rc" != 0 ]]; then
    die "Sync failed (exit $rc) — see output above."
  fi

  info "Sync complete: '$branch' is up to date with origin/main, tests passed, PR is current."
}
```

## 4. Dispatch in `main()` (Zeile ~798–811) — Case ergänzen

```diff
     --shell)
       shift; cmd_start shell "$@" ;;
+    --sync)
+      shift; cmd_sync "$@" ;;
     --done)
       shift; cmd_done "$@" ;;
```

## Anmerkungen

- **`GH_TOKEN`-Scope prüfen**: Push + `gh pr create` brauchen ein Token mit
  `repo`-Schreibrechten. Falls dein aktuelles `GH_TOKEN` nur lesend
  eingerichtet ist (z. B. nur für private Repo-Reads via MCP), muss es dafür
  erweitert werden.
- **Konfliktfall bleibt bewusst manuell**: `--sync` rät nicht, es gibt bei
  einem Rebase-Konflikt exit code 10 zurück und verweist auf die normale,
  interaktive `claude-task <branch>`-Session — dort sieht Claude den
  Konfliktzustand über den gemeinsamen `.git`-Mount sofort via `git status`.
- **Testbefehl** kommt aus dem bereits vorhandenen `buildTool`-Feld in
  `claude-task.json` (`maven`/`gradle`/`none`) — keine Schema-Änderung nötig,
  nur Wiederverwendung.
- **Separater Containername** (`${branch}-sync`) verhindert eine Kollision,
  falls parallel noch eine normale `claude-task <branch>`-Session für denselben
  Branch läuft.

## Docs

In `docs/working-with-tasks.md`, Abschnitt "## `--done` safety checks"
davor einfügen:

```markdown
## `--sync`: rebase, test, push, PR

`claude-task --sync <branch>` bringt einen fertigen Branch auf den
aktuellen `origin/main`-Stand, ohne eine interaktive Claude-Session zu
starten:

1. Verweigert bei uncommitted changes (wie `--done`).
2. `git fetch origin` + `git rebase origin/main` — bei Konflikt: Abbruch,
   Verweis auf `claude-task <branch>` zur interaktiven Auflösung.
3. Testlauf passend zum konfigurierten `buildTool` (`maven`/`gradle`/`none`).
4. `git push --force-with-lease`.
5. `gh pr create --fill`, oder Hinweis falls schon ein PR existiert.

Läuft im selben Image/Cache-Setup wie `claude-task <branch>` — Push und PR
funktionieren, weil `GH_TOKEN` + Git-Identity bereits in jeden Container
gereicht werden (siehe container-capabilities.md, §8).
```
