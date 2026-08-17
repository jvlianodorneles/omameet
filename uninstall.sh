#!/usr/bin/env bash
set -e

PLUGIN_NAME="dorneles.omameet"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_NAME"
BIN_TARGET="$HOME/.local/bin/omameet"
STATE_DIR="$HOME/.local/state/omarchy/omameet"
SHELL_CONFIG="$HOME/.config/omarchy/shell.json"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🗑️  Uninstalling omameet plugin from Omarchy..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Remove CLI symlink
if [ -L "$BIN_TARGET" ] || [ -f "$BIN_TARGET" ]; then
    rm -f "$BIN_TARGET"
    echo "✓ Removed CLI command $BIN_TARGET"
fi

# 2. Remove state and cache directory
if [ -d "$STATE_DIR" ]; then
    rm -rf "$STATE_DIR"
    echo "✓ Removed state directory $STATE_DIR"
fi

# 3. Remove entry from shell.json if present
if [ -f "$SHELL_CONFIG" ]; then
    python3 -c "
import json, os
p = os.path.expanduser('$SHELL_CONFIG')
try:
    with open(p, 'r', encoding='utf-8') as f:
        d = json.load(f)
    b = d.get('bar', {})
    l = b.get('layout', b)
    modified = False
    for sec in ('left', 'center', 'right'):
        if sec in l and isinstance(l[sec], list):
            new_list = [x for x in l[sec] if not ((isinstance(x, dict) and x.get('id') in ('dorneles.omameet', 'omameet')) or x in ('dorneles.omameet', 'omameet'))]
            if len(new_list) != len(l[sec]):
                l[sec] = new_list
                modified = True
    if modified:
        with open(p, 'w', encoding='utf-8') as f:
            json.dump(d, f, indent=2, ensure_ascii=False)
        print('✓ Removed omameet widget from shell.json layout')
except Exception as e:
    pass
" 2>/dev/null || true
fi

# 4. Remove plugin source directory
if [ -d "$PLUGIN_DIR" ]; then
    rm -rf "$PLUGIN_DIR"
    echo "✓ Removed plugin directory $PLUGIN_DIR"
fi

# 5. Restart shell to reload changes
if command -v omarchy > /dev/null 2>&1; then
    echo "✓ Reloading Omarchy shell..."
    omarchy restart shell > /dev/null 2>&1 || true
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ omameet has been completely uninstalled."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
