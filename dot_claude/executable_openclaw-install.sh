#!/bin/bash
# Install Claude Code config for OpenClaw from the dotfiles repo.
#
# Usage:
#   # First time (clone + install):
#   curl -fsSL https://raw.githubusercontent.com/ViktorBarzin/dot_files/master/dot_claude/executable_openclaw-install.sh | bash
#
#   # Update (pull + reinstall):
#   ~/.openclaw/dotfiles/dot_claude/executable_openclaw-install.sh
#
# Environment:
#   OPENCLAW_HOME  - OpenClaw home directory (default: /home/node/.openclaw or ~/.openclaw)
#   DOTFILES_REPO  - Git repo URL (default: https://github.com/ViktorBarzin/dot_files.git)
#   DOTFILES_DIR   - Where to clone the repo (default: $OPENCLAW_HOME/dotfiles)

set -euo pipefail

log() { echo "[openclaw-install] $*"; }

# Detect environment
if [ -d "/home/node/.openclaw" ]; then
  OPENCLAW_HOME="${OPENCLAW_HOME:-/home/node/.openclaw}"
elif [ -d "$HOME/.openclaw" ]; then
  OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
else
  OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.claude}"
fi

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/ViktorBarzin/dot_files.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$OPENCLAW_HOME/dotfiles}"
SRC="$DOTFILES_DIR/dot_claude"

log "OPENCLAW_HOME=$OPENCLAW_HOME"
log "DOTFILES_DIR=$DOTFILES_DIR"

# Clone or pull
git config --global --add safe.directory "$DOTFILES_DIR" 2>/dev/null || true
if [ -d "$DOTFILES_DIR/.git" ]; then
  log "Pulling latest dotfiles..."
  git -C "$DOTFILES_DIR" pull --ff-only 2>/dev/null || git -C "$DOTFILES_DIR" pull --rebase || true
else
  log "Cloning dotfiles..."
  git clone --depth 1 "$DOTFILES_REPO" "$DOTFILES_DIR"
fi

# Install skills
if [ -d "$SRC/skills" ]; then
  mkdir -p "$OPENCLAW_HOME/skills"
  rsync -a --delete "$SRC/skills/" "$OPENCLAW_HOME/skills/"
  log "Installed $(ls "$OPENCLAW_HOME/skills/" | wc -l | tr -d ' ') skills"
fi

# Install agents
if [ -d "$SRC/agents" ]; then
  mkdir -p "$OPENCLAW_HOME/agents"
  rsync -a --delete "$SRC/agents/" "$OPENCLAW_HOME/agents/"
  log "Installed $(ls "$OPENCLAW_HOME/agents/" | wc -l | tr -d ' ') agents"
fi

# Install hooks (skip executable_ prefix renaming — OpenClaw doesn't use chezmoi)
if [ -d "$SRC/hooks" ]; then
  mkdir -p "$OPENCLAW_HOME/hooks"
  for f in "$SRC/hooks/"*; do
    base=$(basename "$f")
    # Strip chezmoi executable_ prefix if present
    dest="${base#executable_}"
    cp "$f" "$OPENCLAW_HOME/hooks/$dest"
    chmod +x "$OPENCLAW_HOME/hooks/$dest" 2>/dev/null || true
  done
  log "Installed $(ls "$OPENCLAW_HOME/hooks/" | wc -l | tr -d ' ') hooks"
fi

# Install commands
if [ -d "$SRC/commands" ]; then
  mkdir -p "$OPENCLAW_HOME/commands"
  rsync -a --delete "$SRC/commands/" "$OPENCLAW_HOME/commands/"
  log "Installed commands"
fi

# Install CLAUDE.md (global knowledge)
if [ -f "$SRC/CLAUDE.md" ]; then
  cp "$SRC/CLAUDE.md" "$OPENCLAW_HOME/CLAUDE.md"
  log "Installed CLAUDE.md"
fi

# Install settings — rewrite hardcoded Mac paths to OpenClaw paths
# Source has /Users/viktorbarzin/.claude/... paths from the Mac; replace with OpenClaw equivalents
if [ -f "$SRC/settings.json" ]; then
  sed -e "s|/Users/viktorbarzin/.claude|$OPENCLAW_HOME|g" \
      -e "s|/Users/viktorbarzin|$(dirname "$OPENCLAW_HOME")|g" \
      -e "s|{{CLAUDE_DIR}}|$OPENCLAW_HOME|g" \
      -e "s|{{HOME}}|$(dirname "$OPENCLAW_HOME")|g" \
      "$SRC/settings.json" > "$OPENCLAW_HOME/settings.json"
  log "Installed settings.json (paths rewritten)"
fi

# Fix ownership if running as root (init container)
if [ "$(id -u)" = "0" ]; then
  chown -R 1000:1000 "$OPENCLAW_HOME" 2>/dev/null || true
  log "Fixed ownership to UID 1000"
fi

log "Done. Installed to $OPENCLAW_HOME"
