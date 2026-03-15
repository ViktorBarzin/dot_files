# Claude Memory

## Instructions
- **When the user says "remember" something**: Always save to the **project** knowledge file (`.claude/CLAUDE.md` in the current repo) by default. Only save to global `~/.claude/CLAUDE.md` if the user explicitly says "remember globally" or the info clearly applies across all projects.
- **After updating any `.claude/` files**: Always commit them immediately (e.g., `git add .claude/ && git commit -m "update claude knowledge"`) to avoid building up unstaged changes. Use `[ci skip]` in commit messages since these are not infrastructure changes.

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

### Skills/Agents Sync
All Claude Code skills, agents, and hooks live in the **dotfiles repo** (`~/.local/share/chezmoi/dot_claude/`), synced via chezmoi.
- **Add new skill/agent**: Create in `~/.claude/skills/` or `~/.claude/agents/`, then `chezmoi add ~/.claude/skills/<name>` and commit
- **OpenClaw**: Init container clones dotfiles repo and runs `executable_openclaw-install.sh` on pod start — no manual sync needed
- **After modifying skills/hooks**: `chezmoi re-add ~/.claude/skills && cd $(chezmoi source-path) && git add -A && git commit -m "update skills" && git push`
