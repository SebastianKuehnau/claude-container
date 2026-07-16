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

# Show Playwright version from VERSION file
if [[ -f /opt/playwright-browsers/VERSION ]]; then
    PW_VER=$(grep "^PLAYWRIGHT_VERSION=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    CHROMIUM_BUILD=$(grep "^CHROMIUM_BUILD=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    MCP_PKG_VER=$(grep "^MCP_PACKAGE_VERSION=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    MCP_PW_VER=$(grep "^MCP_PLAYWRIGHT_VERSION=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    MCP_CHROMIUM_BUILD=$(grep "^MCP_CHROMIUM_BUILD=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    CLI_PKG_VER=$(grep "^CLI_PACKAGE_VERSION=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    CLI_CHROMIUM_BUILD=$(grep "^CLI_CHROMIUM_BUILD=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    echo "  Playwright:   ${PW_VER} (${CHROMIUM_BUILD})"
    if [[ -n "${MCP_PW_VER}" ]]; then
        echo "  MCP:          @playwright/mcp@${MCP_PKG_VER} (${MCP_CHROMIUM_BUILD})"
    fi
    if [[ -n "${CLI_PKG_VER}" ]]; then
        echo "  Agent CLI:    @playwright/cli@${CLI_PKG_VER} (${CLI_CHROMIUM_BUILD})"
    fi
    echo "  Browsers:     ${PLAYWRIGHT_BROWSERS_PATH:-/opt/playwright-browsers}"
fi

# Show Java version
if command -v java &> /dev/null; then
    JAVA_VER=$(java -version 2>&1 | head -1 | cut -d'"' -f2)
    echo "  Java:         ${JAVA_VER}"
fi

echo "========================================"

# Show browser-automation hints. The Agent CLI is the recommended path; the
# MCP server is deprecated and printed only as a fallback for existing setups.
if [[ -f /opt/playwright-browsers/VERSION ]]; then
    CLI_PKG_VER=$(grep "^CLI_PACKAGE_VERSION=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    if [[ -n "${CLI_PKG_VER}" ]]; then
        echo ""
        echo "Playwright Agent CLI (recommended — faster, lower token use):"
        echo "  Skill pre-installed at ~/.claude/skills/playwright-cli — Claude loads it on demand."
        echo "  Drive a browser directly, e.g.: playwright-cli open && playwright-cli goto https://example.com"
    fi
    MCP_PKG_VER=$(grep "^MCP_PACKAGE_VERSION=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    if [[ -n "${MCP_PKG_VER}" ]]; then
        echo ""
        echo "Playwright MCP (DEPRECATED — prefer the Agent CLI above; will be removed in a future release)."
        echo "  .mcp.json (use pre-installed browsers):"
        echo '  "playwright": {'
        echo '    "command": "npx",'
        echo '    "args": ['
        echo "      \"@playwright/mcp@${MCP_PKG_VER}\","
        echo '      "--headless",'
        echo '      "--browser",'
        echo '      "chromium"'
        echo '    ]'
        echo '  }'
    fi
fi
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

# Start Claude Code in Plan mode by default (never bypass mode). Bypass mode
# cannot be set via settings anyway — it only activates through the
# --dangerously-skip-permissions CLI flag — so we just pin the default
# permission mode to "plan" on every start, preserving any other permissions.
CLAUDE_SETTINGS="${CLAUDE_CONFIG_DIR:-/home/node/.claude}/settings.json"
mkdir -p "$(dirname "${CLAUDE_SETTINGS}")"
if [[ -f "${CLAUDE_SETTINGS}" ]]; then
    UPDATED=$(jq '.permissions.defaultMode = "plan"' "${CLAUDE_SETTINGS}")
    echo "${UPDATED}" > "${CLAUDE_SETTINGS}"
else
    echo '{"permissions":{"defaultMode":"plan"}}' > "${CLAUDE_SETTINGS}"
fi
echo "Default permission mode set to: plan"

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

# Show Chrome DevTools remote debugging hint.
# Copy-paste instruction the user can hand to their coding agent (Claude/OpenCode)
# so it launches a browser you can attach DevTools to from your host.
echo "Chrome DevTools (CDP) remote debugging:"
echo "  Copy the block below and give it to your agent ----------------------------"
echo "  Launch the browser with CDP on a FIXED port. Two flags are mandatory:"
echo "    --remote-debugging-port=9222   (Playwright defaults to --remote-debugging-pipe,"
echo "                                    which exposes NO TCP port)"
echo "    --remote-allow-origins=*       (Chrome 111+ returns HTTP 403 on the DevTools"
echo "                                    WebSocket without it)"
echo "  Loopback bind is enough — no socat / 0.0.0.0 bridge: the port-forward rewrites the host."
echo "  - Playwright Agent CLI: put the flags in the config's browser.launchOptions.args, then"
echo "      playwright-cli open --config=<file>"
echo "  - Raw Playwright: chromium.launch({ args: ['--remote-debugging-port=9222','--remote-allow-origins=*'] })"
echo "  ---------------------------------------------------------------------------"
echo "  Then forward port 9222 to your machine and open chrome://inspect."
echo ""

# Execute the passed command (or default to zsh)
exec "$@"
