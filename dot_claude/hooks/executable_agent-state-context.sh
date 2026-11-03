#!/bin/bash
# UserPromptSubmit hook: inject (1) beads in-progress + open tasks, and
# (2) other sessions' active presence claims. One consolidated block.
#
# Both sections come from the network — beads from the shared Dolt server
# presence from MySQL. Querying them inline put those round-trips
# on the critical path of every prompt: measured 0.8-40s, and the transcripts
# recorded 69 cancellations at the 5s hook budget (every recorded run of this
# hook), on which the block was discarded and the prompt still paid the 5s.
#
# So the prompt path now only reads a cache file, and a detached background
# process refreshes it when it ages past TTL. The block can be up to TTL
# seconds stale; both sections are advisory (presence conflicts are enforced by
# `presence claim` itself, which is a live call), and the previous behaviour
# already showed data up to 5s old or nothing at all.
#
# Tests: .claude/hooks/tests/test-agent-state-context.sh

set -euo pipefail

BD="${AGENT_STATE_BD:-/home/wizard/.local/bin/bd}"
BEADS_DIR="${AGENT_STATE_BEADS_DIR:-/home/wizard/code/.beads}"
PRESENCE="${AGENT_STATE_PRESENCE:-/usr/local/bin/presence}"
CACHE_DIR="${AGENT_STATE_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claude-agent-state}"
TTL="${AGENT_STATE_TTL:-60}"

# The cache holds the finished JSON payload, not the raw text, so the prompt
# path is a `cat` — no python interpreter start (~65ms) on every prompt.
# context.json is for a session holding no claims. A session of this user that
# holds claims gets context-<session uuid>.json, which leaves its own claims out
# of the "other sessions" list; the cache is shared by all of the user's
# sessions, so that split is made at refresh time, one file per such session.
CACHE="$CACHE_DIR/context.json"
LOCK="$CACHE_DIR/refresh.lock"
LOCK_MAX_AGE=300   # a lock older than this belonged to a refresh that died

mtime() { stat -c %Y "$1" 2>/dev/null || echo 0; }
age()   { echo $(( $(date +%s) - $(mtime "$1") )); }

# ---------------------------------------------------------------- refresh ---
# Runs detached, off the prompt path. Re-queries both backends and atomically
# replaces the cache. Writes an empty cache when there is nothing to say, so
# the prompt path can tell "nothing to report" from "never populated".
if [[ "${1:-}" == "--refresh" ]]; then
    trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
    CTX=""

    if [[ -x "$BD" && -d "$BEADS_DIR" ]]; then
        IN_PROG="$("$BD" --db "$BEADS_DIR" list --status in_progress 2>/dev/null || true)"
        # --limit rather than `| head`: head closes the pipe under `pipefail`,
        # which leaves bd writing into a closed fd.
        OPEN="$("$BD" --db "$BEADS_DIR" list --status open --limit 10 2>/dev/null || true)"
        if [[ -n "$IN_PROG$OPEN" ]]; then
            CTX+="Active beads tasks (from the shared Dolt server):
"
            [[ -n "$IN_PROG" ]] && CTX+="
IN PROGRESS:
$IN_PROG
"
            [[ -n "$OPEN" ]] && CTX+="
OPEN (available):
$OPEN
"
            CTX+="
Use beads for tracked TODO work (multi-step epics, things to remember,
work that blocks other tasks). Skip beads for small in-session changes.
"
        fi
    fi

    mkdir -p "$CACHE_DIR"
    CLAIMS="[]"
    if [[ -x "$PRESENCE" ]]; then
        CLAIMS="$("$PRESENCE" --json list --all 2>/dev/null || echo '[]')"
    fi

    # Writes context.json plus one context-<uuid>.json per session of this user
    # (ids are <user>@<host>@<uuid>) that holds a claim, and drops the per-session
    # files of sessions that no longer hold one. Nothing to report writes an
    # empty file: still a fresh mtime, but nothing for the prompt path to inject.
    printf '%s' "$CTX" | python3 -c '
import glob, json, os, re, sys
cache_dir, me, claims_json = sys.argv[1], sys.argv[2], sys.argv[3]
beads = sys.stdin.read()
try:
    rows = json.loads(claims_json)
except Exception:
    rows = []
if not isinstance(rows, list):
    rows = []

def render(skip_session):
    others = [r for r in rows if r.get("session_id") != skip_session]
    ctx = beads
    if others:
        ctx += "\nCurrently being mutated by OTHER sessions:\n"
        for r in others:
            label, sid = str(r.get("resource_label", "")), r.get("session_id", "")
            purpose, since = r.get("purpose", ""), r.get("claimed_at", "")
            ctx += f"  {label:<28} {sid} -- {purpose} (since {since})\n"
        ctx += ("\nIf any of these resources overlap with what you are about to mutate,\n"
                "DEFER and surface to the user. See CLAUDE.md, Agent presence rule.\n")
    if not ctx.strip():
        return ""
    return json.dumps({"hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit", "additionalContext": ctx}}) + "\n"

def write(name, body):
    path = os.path.join(cache_dir, name)
    tmp = f"{path}.{os.getpid()}"
    with open(tmp, "w") as f:
        f.write(body)
    os.replace(tmp, path)

keep = set()
for sid in {r.get("session_id", "") for r in rows}:
    if not sid.startswith(me + "@"):
        continue
    uuid = sid[len(me) + 1:]
    if not re.fullmatch(r"[A-Za-z0-9._-]+", uuid):
        continue
    name = f"context-{uuid}.json"
    write(name, render(sid))
    keep.add(name)
for old in glob.glob(os.path.join(cache_dir, "context-*.json")):
    if os.path.basename(old) not in keep:
        try:
            os.remove(old)
        except OSError:
            pass
write("context.json", render(None))
' "$CACHE_DIR" "$(id -un)@$(hostname -s)" "$CLAIMS"
    exit 0
fi

# ------------------------------------------------------------ prompt path ---
mkdir -p "$CACHE_DIR"

# Reclaim a lock whose refresh died, otherwise the cache would freeze forever.
if [[ -d "$LOCK" ]] && (( $(age "$LOCK") > LOCK_MAX_AGE )); then
    rmdir "$LOCK" 2>/dev/null || true
fi

# Refresh when the cache is missing or past TTL. mkdir is the mutex: atomic,
# and shared across the concurrent sessions on this box, so they don't stampede
# the Dolt server. Fully detached — inheriting stdout would keep Claude Code
# waiting on EOF and reintroduce the timeout this hook was fixed for.
if (( $(age "$CACHE") > TTL )); then
    if mkdir "$LOCK" 2>/dev/null; then
        if command -v setsid >/dev/null 2>&1; then
            setsid timeout 60 "$0" --refresh </dev/null >/dev/null 2>&1 &
        else
            timeout 60 "$0" --refresh </dev/null >/dev/null 2>&1 &
        fi
        disown 2>/dev/null || true
    fi
fi

# Serve what we have, picking this session's file when it holds claims. The
# session id is the first field of the hook input; text inside the prompt has
# its quotes escaped, so it cannot match the unescaped "session_id" key. A
# stale block still beats no block; an empty one (nothing to report) is not
# injected.
SID="$(grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')" || SID=""
SERVE="$CACHE"
if [[ "$SID" =~ ^[A-Za-z0-9._-]+$ && -e "$CACHE_DIR/context-$SID.json" ]]; then
    SERVE="$CACHE_DIR/context-$SID.json"
fi
[[ -s "$SERVE" ]] || exit 0
cat "$SERVE"
