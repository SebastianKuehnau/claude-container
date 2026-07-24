#!/bin/bash
# Entrypoint script for Claude Code container
# Initializes firewall and executes the provided command

set -e

# Display welcome message with version info
echo "========================================"
echo "  Claude Code Container"
echo "========================================"

# Show Claude version
if command -v claude &> /dev/null; then
    CLAUDE_VER=$(claude --version 2>/dev/null | head -1 || echo "unknown")
    echo "  Claude Code:  ${CLAUDE_VER}"
fi

# Show Java version
if command -v java &> /dev/null; then
    JAVA_VER=$(java -version 2>&1 | head -1 | cut -d'"' -f2)
    echo "  Java:         ${JAVA_VER}"
fi

echo "========================================"
echo ""

# Configure git identity if env vars are provided
if [[ -n "${GIT_USER_NAME:-}" ]]; then
    git config --global user.name "${GIT_USER_NAME}"
    echo "Git user.name configured: ${GIT_USER_NAME}"
fi
if [[ -n "${GIT_USER_EMAIL:-}" ]]; then
    git config --global user.email "${GIT_USER_EMAIL}"
    echo "Git user.email configured: ${GIT_USER_EMAIL}"
fi

# Configure Claude Code notification hooks if NOTIFICATION_URL is provided
if [[ -n "${NOTIFICATION_URL:-}" ]]; then
    CLAUDE_SETTINGS="${CLAUDE_CONFIG_DIR:-/home/node/.claude}/settings.json"
    mkdir -p "$(dirname "${CLAUDE_SETTINGS}")"

    # Build the hooks JSON
    # Enabled: idle_prompt (Claude waiting for input), permission_prompt (needs permission)
    # Additional matchers available: elicitation_dialog, auth_success
    # Additional hook events: Stop (every response), TaskCompleted
    HOOKS_JSON=$(cat <<HOOKEOF
{
  "hooks": {
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "curl -sf -d \"Claude is idle - waiting for input\" ${NOTIFICATION_URL}"
          }
        ]
      },
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "curl -sf -d \"Claude needs permission to proceed\" ${NOTIFICATION_URL}"
          }
        ]
      },
      {
        "matcher": "elicitation_dialog",
        "hooks": [
          {
            "type": "command",
            "command": "curl -sf -d \"Claude is waiting for your answer\" ${NOTIFICATION_URL}"
          }
        ]
      }
    ]
  }
}
HOOKEOF
    )

    # Merge hooks into existing settings.json (or create new one)
    if [[ -f "${CLAUDE_SETTINGS}" ]]; then
        MERGED=$(jq -s '.[0] * .[1]' "${CLAUDE_SETTINGS}" <(echo "${HOOKS_JSON}"))
        echo "${MERGED}" > "${CLAUDE_SETTINGS}"
    else
        echo "${HOOKS_JSON}" > "${CLAUDE_SETTINGS}"
    fi
    echo "Notification hooks configured for: ${NOTIFICATION_URL}"
fi

# Configure the Claude Code status line to match the host setup
# (model name + progress bar + context-window usage percentage).
# The command is baked into the image at /usr/local/bin/statusline-command.sh,
# so it works regardless of the mounted config volume. We merge it into
# settings.json without clobbering any existing keys, and only when the user
# has not already defined their own statusLine.
STATUSLINE_SCRIPT="/usr/local/bin/statusline-command.sh"
if [[ -x "${STATUSLINE_SCRIPT}" ]]; then
    CLAUDE_SETTINGS="${CLAUDE_CONFIG_DIR:-/home/node/.claude}/settings.json"
    mkdir -p "$(dirname "${CLAUDE_SETTINGS}")"

    STATUSLINE_JSON=$(cat <<STATUSEOF
{
  "statusLine": {
    "type": "command",
    "command": "${STATUSLINE_SCRIPT}"
  }
}
STATUSEOF
    )

    if [[ -f "${CLAUDE_SETTINGS}" ]]; then
        # Only add statusLine if the user hasn't configured one already.
        if [[ "$(jq 'has("statusLine")' "${CLAUDE_SETTINGS}")" != "true" ]]; then
            MERGED=$(jq -s '.[0] * .[1]' "${CLAUDE_SETTINGS}" <(echo "${STATUSLINE_JSON}"))
            echo "${MERGED}" > "${CLAUDE_SETTINGS}"
            echo "Status line configured (model + progress bar + context %)."
        fi
    else
        echo "${STATUSLINE_JSON}" > "${CLAUDE_SETTINGS}"
        echo "Status line configured (model + progress bar + context %)."
    fi
fi

# The permission mode is decided by the launch command that the caller passes
# (e.g. `claude --dangerously-skip-permissions` for the default YOLO mode, or
# `claude --permission-mode plan` for a plan-first review) — see bin/claude-task.
# Because ~/.claude is a persistent host bind mount, a previously pinned
# defaultMode could otherwise linger and contradict the launched mode, so we drop
# that key on every start and let the CLI flag be the single source of truth.
CLAUDE_SETTINGS="${CLAUDE_CONFIG_DIR:-/home/node/.claude}/settings.json"
if [[ -f "${CLAUDE_SETTINGS}" ]]; then
    UPDATED=$(jq 'if .permissions | type == "object" then .permissions |= del(.defaultMode) else . end' "${CLAUDE_SETTINGS}")
    echo "${UPDATED}" > "${CLAUDE_SETTINGS}"
    echo "Cleared any pinned permission defaultMode; the launch command is authoritative."
fi

# Apply the language policy to the user-level CLAUDE.md (global memory):
# converse in German, but keep code, comments and docs in English.
# The policy text is baked into the image; we install it into a managed,
# marker-delimited block so any user-authored CLAUDE.md content is preserved
# and the block is refreshed on every start.
LANG_POLICY_SRC="/usr/local/etc/claude-language-policy.md"
if [[ -f "${LANG_POLICY_SRC}" ]]; then
    CLAUDE_MD="${CLAUDE_CONFIG_DIR:-/home/node/.claude}/CLAUDE.md"
    BEGIN_MARK="<!-- BEGIN claude-container language policy (managed) -->"
    END_MARK="<!-- END claude-container language policy (managed) -->"
    mkdir -p "$(dirname "${CLAUDE_MD}")"

    # Preserve any user content outside the managed block.
    if [[ -f "${CLAUDE_MD}" ]]; then
        REST=$(awk -v b="${BEGIN_MARK}" -v e="${END_MARK}" '
            $0==b {skip=1; next}
            $0==e {skip=0; next}
            !skip {print}
        ' "${CLAUDE_MD}")
    else
        REST=""
    fi

    {
        # Keep existing user content first, then the managed policy block.
        if [[ -n "${REST//[$'\n\t ']/}" ]]; then
            printf '%s\n\n' "${REST}"
        fi
        printf '%s\n' "${BEGIN_MARK}"
        cat "${LANG_POLICY_SRC}"
        printf '%s\n' "${END_MARK}"
    } > "${CLAUDE_MD}.tmp" && mv "${CLAUDE_MD}.tmp" "${CLAUDE_MD}"
    echo "Language policy applied to ${CLAUDE_MD} (German chat, English code/docs)."
fi

# Initialize firewall if we have the capability (unless SKIP_FIREWALL is set)
# This requires NET_ADMIN capability to be set
if [[ "${SKIP_FIREWALL:-0}" == "1" ]]; then
    echo "SKIP_FIREWALL=1 detected, skipping firewall initialization."
    echo ""
elif command -v iptables &> /dev/null; then
    echo "Initializing firewall..."
    if sudo /usr/local/bin/init-firewall.sh; then
        echo "Firewall initialized successfully."
    else
        echo "Warning: Firewall initialization failed. Continuing without firewall."
    fi
    echo ""
fi

# Initialize Vaadin plugins if not already done
if command -v /usr/local/bin/init-vaadin-plugins.sh &> /dev/null; then
    /usr/local/bin/init-vaadin-plugins.sh
fi

# Restore build-tool wrapper executable bits that can be lost when the host git
# worktree is bind-mounted into the container. Only wrappers that git itself
# records as executable (index mode 100755) are repaired, so this can never
# introduce a spurious `git status` change; a wrapper git tracks as
# non-executable is left untouched (use the image-provided mvn/gradle instead).
# No-op when /workspace is not a git repo or the wrapper is absent.
restore_wrapper_exec_bits() {
    command -v git &> /dev/null || return 0
    git -C /workspace rev-parse --is-inside-work-tree &> /dev/null || return 0
    local w mode
    for w in mvnw gradlew; do
        [[ -f "/workspace/${w}" ]] || continue
        mode=$(git -C /workspace ls-files -s -- "$w" 2>/dev/null | awk '{print $1}')
        if [[ "$mode" == "100755" && ! -x "/workspace/${w}" ]]; then
            chmod +x "/workspace/${w}" 2>/dev/null \
                && echo "Restored executable bit on ./${w} (git-tracked as executable)." \
                || true
        fi
    done
    return 0
}
restore_wrapper_exec_bits

# Execute the passed command (or default to zsh)
exec "$@"
