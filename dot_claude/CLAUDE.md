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

### CC Config Sync
Claude Code config is synced across machines via `~/.claude/cc-config/` (git repo backed by NFS bare repo on TrueNAS at `/mnt/main/openclaw/cc-config/cc-config.git`).
- **Push**: `~/.claude/cc-config/sync.sh push` — exports CLAUDE.md, skills, settings (templated), claude-memory data, project memory
- **Pull**: `~/.claude/cc-config/sync.sh pull` — imports and renders templates with local paths
- **OpenClaw**: `sync.sh apply-openclaw` — copies shared config to OpenClaw NFS home (runs in init container on pod start)
- **Automation**: launchd runs `push` every 30 min (`com.cc-config.sync` plist)
- Settings and installed_plugins use `{{HOME}}`/`{{CLAUDE_DIR}}` placeholders for path portability
- After modifying skills, hooks, or CLAUDE.md, run `sync.sh push` to share changes
