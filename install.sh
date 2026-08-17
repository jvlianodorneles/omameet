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

# 4. Initialize initial state
"$PLUGIN_DIR/scripts/omameet" sync > /dev/null 2>&1 || true

# 5. Notify Omarchy Shell to discover plugin
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
