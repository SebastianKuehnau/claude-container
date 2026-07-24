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
