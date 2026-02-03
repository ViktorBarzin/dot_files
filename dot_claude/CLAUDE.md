# Claude Memory

## Preferences

### Chezmoi Sync
When making changes to dotfiles (including Claude files in `~/.claude/`), always:
1. Sync with chezmoi:
   - `chezmoi add <file>` for new files
   - `chezmoi re-add <file>` for updated files
2. Commit the changes in the chezmoi source directory:
   - `cd $(chezmoi source-path) && git add -A && git commit -m "<descriptive message>"`
