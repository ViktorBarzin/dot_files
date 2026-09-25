#!/usr/bin/env bash
# install-beads-post-commit.sh — wires every git repo under a root dir to the
# shared beads auto-close post-commit hook.
#
# Idempotent: if the shim already matches, does nothing. If a different
# post-commit already exists, aborts for that repo and reports — user must
# resolve manually (rare).
#
# Usage:
#   ~/.claude/hooks/install-beads-post-commit.sh            # default: scans /home/wizard/code
#   ~/.claude/hooks/install-beads-post-commit.sh /some/path # custom root

set -euo pipefail

ROOT="${1:-/home/wizard/code}"
SHARED="/home/wizard/.claude/hooks/beads-auto-close-post-commit.sh"

SHIM_CONTENT="#!/bin/sh
# Managed by ~/.claude/hooks/install-beads-post-commit.sh
# Delegates to the shared beads auto-close logic.
exec ${SHARED} \"\$@\"
"

[[ -x "$SHARED" ]] || { echo "error: shared hook missing or not executable: $SHARED" >&2; exit 1; }

installed=0; skipped=0; conflicts=0

# maxdepth 3 catches /home/wizard/code/<subrepo>/.git and /home/wizard/code/.git
while IFS= read -r gitdir; do
    repo=$(dirname "$gitdir")
    # Resolve .git file (worktree) — skip those; main worktree already covers them
    [[ -d "$gitdir" ]] || continue

    hooks_path=$(git -C "$repo" config --get core.hooksPath 2>/dev/null || echo "")
    if [[ -n "$hooks_path" ]]; then
        # Relative path is resolved against the repo root
        if [[ "$hooks_path" != /* ]]; then
            hooks_dir="$repo/$hooks_path"
        else
            hooks_dir="$hooks_path"
        fi
    else
        hooks_dir="$gitdir/hooks"
    fi

    mkdir -p "$hooks_dir"
    target="$hooks_dir/post-commit"

    if [[ -e "$target" ]]; then
        # Already managed by us? Skip.
        if grep -q "Managed by ~/.claude/hooks/install-beads-post-commit.sh" "$target" 2>/dev/null; then
            skipped=$((skipped+1))
            echo "  = $repo (already installed)"
            continue
        fi
        conflicts=$((conflicts+1))
        echo "  ! $repo (existing post-commit not managed — skipped: $target)" >&2
        continue
    fi

    printf '%s' "$SHIM_CONTENT" > "$target"
    chmod +x "$target"
    installed=$((installed+1))
    echo "  + $repo -> $target"
done < <(find "$ROOT" -maxdepth 3 -name ".git" 2>/dev/null)

echo ""
echo "beads post-commit shim: installed=$installed skipped=$skipped conflicts=$conflicts"
