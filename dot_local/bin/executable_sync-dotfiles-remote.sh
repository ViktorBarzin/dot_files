#!/bin/bash
# Sync dotfiles to remote machine without chezmoi
# Usage: ./sync-dotfiles-remote.sh user@host

set -e

REMOTE="${1:?Usage: $0 user@host}"
LOCAL_HOME="$HOME"

echo "Creating dotfiles archive..."
chezmoi archive --output=/tmp/dotfiles.tar.gz

echo "Creating Claude marketplaces archive..."
tar -czf /tmp/claude-marketplaces.tar.gz -C ~/.claude/plugins marketplaces

echo "Copying to $REMOTE..."
scp /tmp/dotfiles.tar.gz /tmp/claude-marketplaces.tar.gz "$REMOTE":/tmp/

echo "Extracting dotfiles..."
ssh "$REMOTE" 'cd ~ && tar -xzf /tmp/dotfiles.tar.gz && rm /tmp/dotfiles.tar.gz'

echo "Extracting Claude marketplaces..."
ssh "$REMOTE" 'mkdir -p ~/.claude/plugins && tar -xzf /tmp/claude-marketplaces.tar.gz -C ~/.claude/plugins && rm /tmp/claude-marketplaces.tar.gz'

echo "Fixing paths for remote home directory..."
# Fix paths in all Claude plugin JSON files
ssh "$REMOTE" "
  for f in ~/.claude/plugins/installed_plugins.json ~/.claude/plugins/known_marketplaces.json; do
    if [ -f \"\$f\" ]; then
      sed -i.bak 's|$LOCAL_HOME|\$HOME|g' \"\$f\"
      sed -i.bak \"s|\\\$HOME|\$HOME|g\" \"\$f\"
      rm -f \"\$f.bak\"
    fi
  done
"

echo "Done! Dotfiles and Claude marketplaces synced to $REMOTE"
