#!/bin/bash
# This script runs once after chezmoi apply on a new machine

set -e

# Check if claude is available
if ! command -v claude &> /dev/null; then
    echo "Claude CLI not found, skipping plugin installation"
    exit 0
fi

echo "Installing Claude marketplaces..."
claude /add-marketplace anthropics/claude-plugins-official 2>/dev/null || true
claude /add-marketplace anthropics/skills 2>/dev/null || true
claude /add-marketplace obra/superpowers-marketplace 2>/dev/null || true

echo "Installing Claude plugins..."
claude /install-plugin code-simplifier@claude-plugins-official 2>/dev/null || true
claude /install-plugin ralph-loop@claude-plugins-official 2>/dev/null || true
claude /install-plugin superpowers@claude-plugins-official 2>/dev/null || true

echo "Claude plugins installed successfully"
