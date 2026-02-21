---
name: macos-provenance-xattr-deletion
description: |
  Fix for "Permission denied" when deleting empty directories on macOS created by
  sandboxed processes (e.g., Claude Code agents, git worktrees from sandboxed tools).
  Use when: (1) rm -rf fails with "Permission denied" on an empty directory,
  (2) chmod and xattr -d don't help, (3) the directory has com.apple.provenance
  extended attribute, (4) git worktree remove fails with "is not a .git file".
  Root cause: macOS sandbox provenance tracking marks directories as immutable
  to the sandboxed process. Only an unsandboxed terminal can delete them.
author: Claude Code
version: 1.0.0
date: 2026-02-21
---

# macOS com.apple.provenance Blocking Directory Deletion

## Problem
Directories created by sandboxed macOS processes (like Claude Code subagents
running in git worktrees) acquire a `com.apple.provenance` extended attribute.
This attribute prevents the sandboxed process from deleting the directories,
even when they are empty and owned by the current user. Standard remedies
like `chmod`, `xattr -d`, and `xattr -cr` all fail silently — the attribute
is enforced at the kernel level for sandboxed processes.

## Context / Trigger Conditions
- `rm -rf <directory>` fails with "Permission denied" on an empty directory
- `ls -la` shows the directory is owned by you with normal permissions
- `ls -la` shows an `@` flag on the directory (extended attributes present)
- `xattr -l <directory>` shows `com.apple.provenance:`
- `git worktree remove` fails with "is not a .git file, error code 2"
- The directory was created by a sandboxed subprocess (Claude Code agent,
  Xcode build, App Sandbox process)

## Solution

**You cannot delete these directories from within the sandboxed process.**

Run the cleanup manually in an unsandboxed terminal:

```bash
# Remove the stuck directory
rm -rf <path-to-directory>

# If it was a git worktree, also prune and delete the branch
git worktree prune
git branch -D <branch-name>
```

If running from a script that may be sandboxed, detect and warn:

```bash
if xattr -p com.apple.provenance "$DIR" &>/dev/null; then
    echo "Directory $DIR has provenance lock. Delete manually from an unsandboxed terminal."
    exit 1
fi
```

## Verification
```bash
# Confirm directory is gone
ls -la <path>  # Should show "No such file or directory"

# Confirm worktree is pruned
git worktree list  # Should not show the removed worktree
```

## Example

**Scenario**: Claude Code spawns two agents in git worktrees. After completing
work, the team lead tries to clean up:

```
$ rm -rf .worktrees/mobile
rm: .worktrees/mobile/frontend/node_modules: Permission denied
rm: .worktrees/mobile/.venv: Permission denied

$ xattr -l .worktrees/mobile/frontend/node_modules
com.apple.provenance:

$ xattr -d com.apple.provenance .worktrees/mobile/frontend/node_modules
# Silently fails — still can't delete

$ chmod -R u+w .worktrees/mobile
# Also doesn't help
```

**Fix**: Open a regular Terminal.app (unsandboxed) and run:
```bash
rm -rf .worktrees/mobile
git worktree prune
```

## Notes
- `com.apple.provenance` is a macOS security feature for App Sandbox tracking
- It tracks which sandboxed app created a file/directory
- The restriction only applies to the sandboxed process; unsandboxed terminals
  can delete freely
- This commonly affects: node_modules, .venv, build output directories
- The directories are often empty (contents were deleted successfully, but
  the directory itself can't be removed)
- `git worktree remove --force` also fails for the same reason
