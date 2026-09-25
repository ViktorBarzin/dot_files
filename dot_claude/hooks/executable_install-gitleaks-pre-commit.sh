#!/usr/bin/env bash
# install-gitleaks-pre-commit.sh — wires every git repo under a root dir to
# the shared gitleaks pre-commit hook.
#
# Idempotent. Three install modes:
#   1. No existing pre-commit: install a shim that exec's the shared hook.
#   2. Beads-managed pre-commit (has v1.0.0 BEGIN/END markers): append a
#      managed gitleaks block AFTER the beads section so both run.
#   3. Other existing pre-commit: skip with a CONFLICT warning.
#
# Usage:
#   ~/.claude/hooks/install-gitleaks-pre-commit.sh            # default: scans /home/wizard/code
#   ~/.claude/hooks/install-gitleaks-pre-commit.sh /some/path # custom root

set -euo pipefail

ROOT="${1:-/home/wizard/code}"
SHARED="/home/wizard/.claude/hooks/gitleaks-pre-commit.sh"

SHIM_CONTENT="#!/bin/sh
# Managed by ~/.claude/hooks/install-gitleaks-pre-commit.sh
# Delegates to the shared gitleaks pre-commit logic.
exec ${SHARED} \"\$@\"
"

GITLEAKS_BLOCK="# --- BEGIN GITLEAKS INTEGRATION v1.0.0 ---
# Managed by ~/.claude/hooks/install-gitleaks-pre-commit.sh. Do not edit.
${SHARED} \"\$@\" || exit \$?
# --- END GITLEAKS INTEGRATION v1.0.0 ---"

[[ -x "$SHARED" ]] || { echo "error: shared hook missing or not executable: $SHARED" >&2; exit 1; }

installed=0; skipped=0; appended=0; conflicts=0

while IFS= read -r gitdir; do
    repo=$(dirname "$gitdir")
    [[ -d "$gitdir" ]] || continue

    hooks_path=$(git -C "$repo" config --get core.hooksPath 2>/dev/null || echo "")
    if [[ -n "$hooks_path" ]]; then
        if [[ "$hooks_path" != /* ]]; then
            hooks_dir="$repo/$hooks_path"
        else
            hooks_dir="$hooks_path"
        fi
    else
        hooks_dir="$gitdir/hooks"
    fi
    mkdir -p "$hooks_dir"
    target="$hooks_dir/pre-commit"

    # Mode 1: no existing hook — install shim
    if [[ ! -f "$target" ]]; then
        printf '%s' "$SHIM_CONTENT" > "$target"
        chmod +x "$target"
        installed=$((installed + 1))
        echo "installed (shim): $repo"
        continue
    fi

    existing=$(cat "$target")

    # Already our standalone shim
    if [[ "$existing" == "$SHIM_CONTENT" ]]; then
        skipped=$((skipped + 1))
        continue
    fi

    # Older shim pointing at the shared script — refresh it
    if [[ "$existing" != *"BEADS INTEGRATION"* ]] && grep -Fq "$SHARED" "$target"; then
        printf '%s' "$SHIM_CONTENT" > "$target"
        chmod +x "$target"
        installed=$((installed + 1))
        echo "updated (shim): $repo"
        continue
    fi

    # Mode 2: beads-managed hook — append our gitleaks block if missing
    if [[ "$existing" == *"BEGIN BEADS INTEGRATION"* ]]; then
        if [[ "$existing" == *"BEGIN GITLEAKS INTEGRATION"* ]]; then
            skipped=$((skipped + 1))
            continue
        fi
        # Append the gitleaks block after the existing content
        { echo; echo "$GITLEAKS_BLOCK"; } >> "$target"
        chmod +x "$target"
        appended=$((appended + 1))
        echo "appended (beads+gitleaks): $repo"
        continue
    fi

    # Mode 3: unknown existing hook — conflict
    conflicts=$((conflicts + 1))
    echo "CONFLICT: $repo already has a non-managed pre-commit hook; skipping" >&2
done < <(find "$ROOT" -maxdepth 3 -name .git -print 2>/dev/null)

echo ""
echo "summary: installed=$installed, appended=$appended, skipped=$skipped, conflicts=$conflicts"
