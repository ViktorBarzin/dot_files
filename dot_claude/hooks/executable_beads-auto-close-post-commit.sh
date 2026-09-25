#!/usr/bin/env bash
# Shared post-commit hook. Two responsibilities:
#   1. Auto-close beads tasks referenced via "Closes/Fixes/Resolves: code-X".
#   2. For Claude-authored commits, emit a session-checkpoint reminder so
#      Claude follows through on (a) saving relevant learnings to memory and
#      (b) updating any docs affected by the session's changes. The reminder
#      appears in the Bash tool output Claude sees after running `git commit`.
#
# Invoked by each subrepo's .git/hooks/post-commit (or core.hooksPath/post-commit)
# shim. Single source of truth — edit this file to change behavior everywhere.
#
# Never fails the commit. Warnings go to stderr, successes to stdout.

set -u

BD="${BD:-/home/wizard/.local/bin/bd}"
BEADS_DB="${BEADS_DB:-/home/wizard/code/.beads}"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

SHA=$(git rev-parse --short HEAD)
SUBJECT=$(git log -1 --pretty=%s)
MSG=$(git log -1 --pretty=%B)

# ---------- beads auto-close ----------
if [[ -x "$BD" && -d "$BEADS_DB" ]]; then
    IDS=$(printf '%s\n' "$MSG" \
        | grep -iE '^[[:space:]]*(Closes|Fixes|Resolves):[[:space:]]*code-[a-z0-9]+' \
        | grep -oiE 'code-[a-z0-9]+' \
        | tr '[:upper:]' '[:lower:]' \
        | sort -u)

    if [[ -n "$IDS" ]]; then
        REASON="Closed by commit ${SHA}: ${SUBJECT}"
        while IFS= read -r ID; do
            [[ -z "$ID" ]] && continue
            if OUTPUT=$("$BD" --db "$BEADS_DB" close "$ID" -r "$REASON" 2>&1); then
                echo "beads: ✓ closed $ID"
            else
                echo "beads: ⚠ failed to close $ID — $OUTPUT" >&2
            fi
        done <<< "$IDS"
    fi
fi

# ---------- Claude session checkpoint ----------
# Only fires for commits co-authored by Claude — keeps human commits quiet.
if printf '%s' "$MSG" | grep -qiE '^[[:space:]]*Co-Authored-By:.*Claude'; then
    DOC_FILES=$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null \
        | grep -iE '(^|/)(CLAUDE\.md|README(\.|$)|AGENTS\.md)|\.(md|mdx|rst)$' \
        | head -20 || true)

    echo ""
    echo "━━━ Claude session checkpoint ━━━"
    echo "Before ending the session, do the following (skip any that don't apply):"
    echo ""
    echo "  1. Save session learnings with \`homelab memory store\`: patterns"
    echo "     discovered, non-obvious gotchas, decisions and their rationale,"
    echo "     failed approaches worth avoiding next time. Skip trivial cleanups."
    echo ""
    echo "  2. Update docs affected by the session's changes — not just this"
    echo "     commit. Candidates: AGENTS.md (project + subdirs), README, skill"
    echo "     files, runbooks, architecture diagrams. If behavior, commands,"
    echo "     or invariants changed, the docs describing them must change too."
    if [[ -n "$DOC_FILES" ]]; then
        echo ""
        echo "     Doc-like files touched in this commit (verify still accurate):"
        printf '%s\n' "$DOC_FILES" | sed 's/^/       - /'
    fi
    echo "━━━"
fi

exit 0
