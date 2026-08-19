#!/usr/bin/env bash
set -e

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
CLI_TARGET="$BIN_DIR/omameet"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Installing omameet plugin for Omarchy..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Ensure executable permissions
chmod +x "$PLUGIN_DIR/scripts/omameet-sync.py"
chmod +x "$PLUGIN_DIR/scripts/omameet"

# 2. Create ~/.local/bin if not exists
mkdir -p "$BIN_DIR"

# 3. Create global symlink for omameet CLI
ln -sf "$PLUGIN_DIR/scripts/omameet" "$CLI_TARGET"
echo "✓ CLI command 'omameet' linked to $CLI_TARGET"

# 4. Enforce secure owner-only permissions on state directory & files (0700/0600)
STATE_DIR="$HOME/.local/state/omarchy/omameet"
mkdir -p -m 700 "$STATE_DIR"
chmod 700 "$STATE_DIR" 2>/dev/null || true
if [ -f "$STATE_DIR/config.json" ]; then
    chmod 600 "$STATE_DIR/config.json" 2>/dev/null || true
fi
if [ -f "$STATE_DIR/state.json" ]; then
    chmod 600 "$STATE_DIR/state.json" 2>/dev/null || true
fi

# 5. Initialize initial state (enforcing secure permissions)
"$PLUGIN_DIR/scripts/omameet" sync > /dev/null 2>&1 || true

# 6. Notify Omarchy Shell to discover plugin
if command -v omarchy-shell > /dev/null 2>&1; then
    echo "✓ Rescanning Omarchy Shell plugins..."
    omarchy-shell shell rescanPlugins 2>/dev/null || true
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Installation completed successfully!"
echo "• To add the widget to your bar:"
echo "  omarchy bar move dorneles.omameet --section right"
echo "• To use the CLI:"
echo "  omameet --help"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
