#!/bin/sh
# install.sh — One-line installer for claude-session-recover
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/michaelcarwile/claude-session-recover/main/install.sh | sh
#
# What it does:
#   1. Creates a local marketplace if you don't have one
#   2. Adds claude-session-recover to it (if not already there)
#   3. Registers the marketplace with Claude Code (if not already registered)
#   4. Installs the plugin

set -e

MARKETPLACE_DIR="$HOME/.claude/local-marketplace"
MANIFEST="$MARKETPLACE_DIR/.claude-plugin/marketplace.json"
PLUGIN_NAME="claude-session-recover"
PLUGIN_URL="https://github.com/michaelcarwile/claude-session-recover.git"

echo "Installing ${PLUGIN_NAME}..."

# Step 1: Create local marketplace if it doesn't exist
if [ ! -f "$MANIFEST" ]; then
  echo "Creating local marketplace..."
  mkdir -p "$MARKETPLACE_DIR/.claude-plugin"
  cat > "$MANIFEST" << 'MANIFEST_EOF'
{
  "name": "local-marketplace",
  "owner": { "name": "local" },
  "plugins": []
}
MANIFEST_EOF
fi

# Step 2: Add plugin entry if not already present
if grep -q "$PLUGIN_NAME" "$MANIFEST" 2>/dev/null; then
  echo "Plugin already in marketplace manifest."
else
  echo "Adding plugin to marketplace..."
  # Insert the plugin entry into the plugins array
  # Works with both empty [] and existing entries
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json, sys
with open('$MANIFEST') as f:
    data = json.load(f)
data['plugins'].append({
    'name': '$PLUGIN_NAME',
    'description': 'Automatically recovers Claude Code sessions after a project directory is moved or renamed',
    'source': {'source': 'url', 'url': '$PLUGIN_URL'},
    'category': 'productivity'
})
with open('$MANIFEST', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
  elif command -v jq >/dev/null 2>&1; then
    tmp=$(mktemp)
    jq --arg name "$PLUGIN_NAME" --arg url "$PLUGIN_URL" \
      '.plugins += [{"name": $name, "description": "Automatically recovers Claude Code sessions after a project directory is moved or renamed", "source": {"source": "url", "url": $url}, "category": "productivity"}]' \
      "$MANIFEST" > "$tmp" && mv "$tmp" "$MANIFEST"
  else
    echo "Error: python3 or jq required to update marketplace manifest." >&2
    exit 1
  fi
fi

# Step 3: Register marketplace if not already registered
KNOWN="$HOME/.claude/plugins/known_marketplaces.json"
if [ -f "$KNOWN" ] && grep -q "local-marketplace" "$KNOWN" 2>/dev/null; then
  echo "Marketplace already registered."
else
  echo "Registering local marketplace..."
  claude plugin marketplace add "$MARKETPLACE_DIR" 2>/dev/null || true
fi

# Step 4: Install the plugin
echo "Installing plugin..."
claude plugin install "${PLUGIN_NAME}@local-marketplace"

echo ""
echo "Done! Start a new Claude Code session and run /session-recover:setup"
