#!/bin/bash
# Entrypoint script for OpenCode container
# Initializes firewall and executes the provided command

set -e

# Display welcome message with version info
echo "========================================"
echo "  OpenCode Container"
echo "========================================"

# Show OpenCode version
if command -v opencode &> /dev/null; then
    OPENCODE_VER=$(opencode --version 2>/dev/null | head -1 || echo "unknown")
    echo "  OpenCode:     ${OPENCODE_VER}"
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
# (OpenCode supports MCP servers via opencode.json / ~/.config/opencode/config.json.)
if [[ -f /opt/playwright-browsers/VERSION ]]; then
    CLI_PKG_VER=$(grep "^CLI_PACKAGE_VERSION=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    if [[ -n "${CLI_PKG_VER}" ]]; then
        echo ""
        echo "Playwright Agent CLI (recommended — faster, lower token use):"
        echo "  Skill pre-installed at ~/.claude/skills/playwright-cli — OpenCode discovers it automatically."
        echo "  Drive a browser directly, e.g.: playwright-cli open && playwright-cli goto https://example.com"
    fi
    MCP_PKG_VER=$(grep "^MCP_PACKAGE_VERSION=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    if [[ -n "${MCP_PKG_VER}" ]]; then
        echo ""
        echo "Playwright MCP (DEPRECATED — prefer the Agent CLI above; will be removed in a future release)."
        echo "  Add to opencode.json mcp section:"
        echo '  "playwright": {'
        echo '    "type": "local",'
        echo '    "command": ["npx", "@playwright/mcp@'"${MCP_PKG_VER}"'", "--headless", "--browser", "chromium"]'
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

# Show Chrome DevTools remote debugging hint
echo "Chrome DevTools (CDT) remote debugging:"
echo "  Auto-proxy that tracks Playwright's random debug port to 0.0.0.0:9222:"
echo "  nohup cdp-proxy-monitor > /tmp/cdp-proxy.log 2>&1 &"
echo "  Then forward port 9222 to your machine and open chrome://inspect"
echo ""

# Execute the passed command (or default to zsh)
exec "$@"
