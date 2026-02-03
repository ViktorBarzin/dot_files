#!/bin/bash
# Sync dotfiles to remote machine without chezmoi
# Usage: ./sync-dotfiles-remote.sh user@host

set -e

REMOTE="${1:?Usage: $0 user@host}"

echo "Creating dotfiles archive..."
chezmoi archive --output=/tmp/dotfiles.tar.gz

echo "Copying to $REMOTE..."
scp /tmp/dotfiles.tar.gz "$REMOTE":/tmp/

echo "Extracting and setting up Claude plugins..."
ssh "$REMOTE" 'cd ~ && tar -xzf /tmp/dotfiles.tar.gz && rm /tmp/dotfiles.tar.gz && if command -v claude &>/dev/null; then claude /add-marketplace anthropics/claude-plugins-official 2>/dev/null || true; claude /add-marketplace anthropics/skills 2>/dev/null || true; claude /add-marketplace obra/superpowers-marketplace 2>/dev/null || true; claude /install-plugin code-simplifier@claude-plugins-official 2>/dev/null || true; claude /install-plugin ralph-loop@claude-plugins-official 2>/dev/null || true; claude /install-plugin superpowers@claude-plugins-official 2>/dev/null || true; echo "Claude plugins installed"; else echo "Claude CLI not found, skipping plugins"; fi'

echo "Done!"
