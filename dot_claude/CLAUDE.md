# Claude Memory

## Instructions
- **When the user says "remember" something**: Always update the relevant knowledge file (global `~/.claude/CLAUDE.md` for general preferences, or project `.claude/CLAUDE.md` for project-specific info) so it persists across sessions.

## Preferences

### Chezmoi Sync
When making changes to dotfiles (including Claude files in `~/.claude/`), sync with chezmoi **only if it is installed** (`command -v chezmoi`):
1. Sync with chezmoi:
   - `chezmoi add <file>` for new files
   - `chezmoi re-add <file>` for updated files
2. Commit the changes in the chezmoi source directory:
   - `cd $(chezmoi source-path) && git add -A && git commit -m "<descriptive message>"`
If chezmoi is not installed, skip the sync steps and just make the changes directly.

### Claude Plugins
When installing new Claude plugins or marketplaces, update these files:
- `~/.local/bin/sync-dotfiles-remote.sh` - add new marketplace/plugin install commands
- `~/.local/share/chezmoi/run_once_after_install-claude-plugins.sh` - add to chezmoi run_once script
Then sync and commit both to chezmoi.
