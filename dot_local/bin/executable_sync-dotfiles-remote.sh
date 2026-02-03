#!/bin/bash
# Sync dotfiles to remote machine without chezmoi
# Usage: ./sync-dotfiles-remote.sh user@host

set -e

REMOTE="${1:?Usage: $0 user@host}"
LOCAL_HOME="$HOME"

echo "Creating archives..."
chezmoi archive --output=/tmp/dotfiles.tar.gz
tar -czf /tmp/claude-marketplaces.tar.gz -C ~/.claude/plugins marketplaces

echo "Copying to $REMOTE..."
scp /tmp/dotfiles.tar.gz /tmp/claude-marketplaces.tar.gz "$REMOTE":/tmp/

echo "Extracting and configuring on remote..."
ssh "$REMOTE" "
  set -e

  echo 'Extracting dotfiles...'
  cd ~ && tar -xzf /tmp/dotfiles.tar.gz

  echo 'Extracting Claude marketplaces...'
  mkdir -p ~/.claude/plugins
  tar -xzf /tmp/claude-marketplaces.tar.gz -C ~/.claude/plugins

  echo 'Fixing paths for home directory...'
  for f in ~/.claude/plugins/installed_plugins.json ~/.claude/plugins/known_marketplaces.json; do
    if [ -f \"\$f\" ]; then
      sed -i.bak 's|$LOCAL_HOME|'\$HOME'|g' \"\$f\"
      rm -f \"\$f.bak\"
    fi
  done

  echo 'Cleaning up...'
  rm -f /tmp/dotfiles.tar.gz /tmp/claude-marketplaces.tar.gz

  echo 'Done!'
"

echo "Dotfiles and Claude marketplaces synced to $REMOTE"
