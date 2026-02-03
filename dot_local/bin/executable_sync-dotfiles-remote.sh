#!/bin/bash
# Sync dotfiles to remote machine without chezmoi
# Usage: ./sync-dotfiles-remote.sh user@host

set -e

REMOTE="${1:?Usage: $0 user@host}"
LOCAL_HOME="$HOME"

echo "Creating archives..."
chezmoi archive --output=/tmp/dotfiles.tar.gz
tar -czf /tmp/claude-marketplaces.tar.gz -C ~/.claude/plugins marketplaces

# Combine into single archive
echo "Combining archives..."
mkdir -p /tmp/dotfiles-sync
tar -xzf /tmp/dotfiles.tar.gz -C /tmp/dotfiles-sync
mkdir -p /tmp/dotfiles-sync/.claude/plugins
tar -xzf /tmp/claude-marketplaces.tar.gz -C /tmp/dotfiles-sync/.claude/plugins

echo "Syncing to $REMOTE (single connection)..."
tar -czf - -C /tmp/dotfiles-sync . | ssh "$REMOTE" "
  set -e

  echo 'Extracting dotfiles...'
  cd ~ && tar -xzf -

  echo 'Fixing paths for home directory...'
  for f in ~/.claude/plugins/installed_plugins.json ~/.claude/plugins/known_marketplaces.json; do
    if [ -f \"\$f\" ]; then
      sed -i.bak 's|$LOCAL_HOME|'\$HOME'|g' \"\$f\"
      rm -f \"\$f.bak\"
    fi
  done

  echo 'Done!'
"

# Cleanup local temp files
rm -rf /tmp/dotfiles-sync /tmp/dotfiles.tar.gz /tmp/claude-marketplaces.tar.gz

echo "Dotfiles and Claude marketplaces synced to $REMOTE"
