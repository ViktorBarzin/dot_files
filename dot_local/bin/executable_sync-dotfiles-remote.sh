#!/bin/bash
# Sync dotfiles to remote machine without chezmoi
# Usage: ./sync-dotfiles-remote.sh user@host

set -e

REMOTE="${1:?Usage: $0 user@host}"
LOCAL_HOME="$HOME"
TMPDIR="/tmp/dotfiles-sync-$$"

echo "Creating combined dotfiles archive..."
mkdir -p "$TMPDIR/.claude/plugins"
chezmoi archive --output=- | tar -xzf - -C "$TMPDIR"
cp -r ~/.claude/plugins/marketplaces "$TMPDIR/.claude/plugins/"

echo "Syncing to $REMOTE..."
tar -czf - -C "$TMPDIR" . | ssh "$REMOTE" "
  cd ~ && tar -xzf -
  for f in ~/.claude/plugins/installed_plugins.json ~/.claude/plugins/known_marketplaces.json; do
    [ -f \"\$f\" ] && sed -i.bak 's|$LOCAL_HOME|'\$HOME'|g' \"\$f\" && rm -f \"\$f.bak\"
  done
"

rm -rf "$TMPDIR"
echo "Done!"
