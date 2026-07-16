#!/bin/bash
# Init script to install Vaadin Claude plugins on first container start
# This runs as part of the entrypoint if VAADIN_PLUGINS_INSTALLED flag is not set

set -e

MARKER_FILE="/home/node/.claude/.vaadin-plugins-installed"

# Check if already installed
if [ -f "$MARKER_FILE" ]; then
    echo "Vaadin plugins already installed."
    exit 0
fi

echo "Installing Vaadin Claude plugins..."

# Try to install the plugins
if command -v claude &> /dev/null; then
    # Method 1: Try to use Claude CLI directly (may require TTY)
    timeout 30 claude --eval "/plugin marketplace add vaadin/agent-marketplace" 2>/dev/null || true
    timeout 30 claude --eval "/plugin install vaadin-skills@vaadin-marketplace" 2>/dev/null || true

    # Create marker file to prevent repeated installation attempts
    mkdir -p "$(dirname "$MARKER_FILE")"
    touch "$MARKER_FILE"

    echo "✓ Vaadin plugins installation attempted."
    echo "  To verify or install manually, run:"
    echo "    /plugin"
    echo "  and check if vaadin-skills is listed."
else
    echo "⚠ Claude CLI not found. Skipping plugin installation."
fi