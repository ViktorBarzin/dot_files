#!/bin/bash
# Create a portable dotfiles archive that can be extracted on any machine
# Usage: ./create-dotfiles-archive.sh [output.tar.gz]

set -e

OUTPUT="${1:-dotfiles-portable.tar.gz}"
TMPDIR="/tmp/dotfiles-archive-$$"
LOCAL_HOME="$HOME"

echo "Creating portable dotfiles archive..."
mkdir -p "$TMPDIR/.claude/plugins"

# Extract chezmoi dotfiles
chezmoi archive --output=- | tar -xzf - -C "$TMPDIR"

# Add marketplaces
cp -r ~/.claude/plugins/marketplaces "$TMPDIR/.claude/plugins/"

# Replace home path with placeholder in JSON files
for f in "$TMPDIR/.claude/plugins/installed_plugins.json" "$TMPDIR/.claude/plugins/known_marketplaces.json"; do
  if [ -f "$f" ]; then
    sed -i.bak "s|$LOCAL_HOME|__HOME__|g" "$f"
    rm -f "$f.bak"
  fi
done

# Create setup script
cat > "$TMPDIR/setup-dotfiles.sh" << 'SETUP'
#!/bin/bash
# Run this after extracting to fix paths for your home directory
set -e
cd ~
for f in ~/.claude/plugins/installed_plugins.json ~/.claude/plugins/known_marketplaces.json; do
  if [ -f "$f" ]; then
    sed -i.bak "s|__HOME__|$HOME|g" "$f"
    rm -f "$f.bak"
  fi
done
echo "Dotfiles setup complete!"
rm -f ~/setup-dotfiles.sh
SETUP
chmod +x "$TMPDIR/setup-dotfiles.sh"

# Create the archive
tar -czf "$OUTPUT" -C "$TMPDIR" .

rm -rf "$TMPDIR"
echo "Created: $OUTPUT"
echo ""
echo "To use on remote machine:"
echo "  1. Copy $OUTPUT to the remote"
echo "  2. cd ~ && tar -xzf $OUTPUT && ./setup-dotfiles.sh"
