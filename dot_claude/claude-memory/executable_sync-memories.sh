#!/bin/bash
# Sync local SQLite ↔ remote PostgreSQL for claude-memory.
# Runs as a cron job — sends macOS notification on failure or drift.
# Usage: sync-memories.sh [--quiet]

set -uo pipefail

DB_PATH="$HOME/.claude/claude-memory/memory/memory.db"
API_BASE="https://claude-memory.viktorbarzin.me"
LOCK_FILE="/tmp/claude-memory-sync.lock"
LOG_FILE="$HOME/.claude/claude-memory/sync.log"
QUIET="${1:-}"

# Prevent concurrent runs
if [ -f "$LOCK_FILE" ]; then
  pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    exit 0
  fi
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
  [ "$QUIET" != "--quiet" ] && echo "$*" || true
}

notify_error() {
  local title="$1"
  local msg="$2"
  log "ERROR: $title — $msg"
  osascript -e "display notification \"$msg\" with title \"Memory Sync\" subtitle \"$title\" sound name \"Basso\"" 2>/dev/null || true
}

notify_info() {
  local msg="$1"
  log "INFO: $msg"
  [ "$QUIET" != "--quiet" ] && osascript -e "display notification \"$msg\" with title \"Memory Sync\" sound name \"Pop\"" 2>/dev/null || true
}

# Read API key from claude.json
API_KEY=$(python3 -c "
import json, os
with open(os.path.expanduser('~/.claude.json')) as f:
    d = json.load(f)
mc = d.get('mcpServers', {})
cm = mc.get('claude_memory', mc.get('claude-memory', {}))
h = cm.get('headers', {})
auth = h.get('Authorization', '')
print(auth.replace('Bearer ', ''))
" 2>/dev/null)

if [ -z "$API_KEY" ]; then
  notify_error "Config Error" "No API key found in ~/.claude.json"
  exit 1
fi

if [ ! -f "$DB_PATH" ]; then
  notify_error "DB Missing" "Local SQLite not found at $DB_PATH"
  exit 1
fi

# Run the sync — capture stdout (JSON result) and stderr (errors)
SYNC_OUTPUT=$(python3 - "$DB_PATH" "$API_BASE" "$API_KEY" << 'PYEOF'
import sqlite3, json, urllib.request, urllib.error, sys
from datetime import datetime, timezone

DB_PATH = sys.argv[1]
API_BASE = sys.argv[2]
API_KEY = sys.argv[3]
MAX_LEN = 800

errors = []
stats = {"pushed": 0, "pulled": 0, "deleted": 0, "skipped_dupes": 0, "truncated": 0}

def api_request(method, path, body=None):
    url = f"{API_BASE}{path}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())

def truncate(content):
    if len(content) <= MAX_LEN:
        return content, False
    return content[:MAX_LEN - 15] + " [truncated]", True

# Test connectivity + auth
try:
    api_request("GET", "/api/auth-check")
except urllib.error.HTTPError as e:
    if e.code in (401, 403):
        print(json.dumps({"error": f"auth_failed:{e.code}"}))
        sys.exit(0)
    print(json.dumps({"error": f"api_error:{e.code}"}))
    sys.exit(0)
except Exception as e:
    print(json.dumps({"error": f"unreachable:{e}"}))
    sys.exit(0)

conn = sqlite3.connect(DB_PATH, timeout=30.0)
conn.row_factory = sqlite3.Row

# Get remote state
try:
    remote = api_request("GET", "/api/memories/sync")
    remote_memories = remote.get("memories", [])
    remote_contents = {m["content"] for m in remote_memories}
    remote_ids = {m["id"] for m in remote_memories}
    server_time = remote.get("server_time")
except Exception as e:
    errors.append(f"fetch_remote:{e}")
    remote_memories = []
    remote_contents = set()
    remote_ids = set()
    server_time = None

# 1. Process pending deletes
pending_deletes = conn.execute("SELECT id, payload FROM pending_ops WHERE op_type='delete'").fetchall()
for op in pending_deletes:
    payload = json.loads(op["payload"])
    server_id = payload.get("server_id")
    if server_id:
        try:
            api_request("DELETE", f"/api/memories/{server_id}")
            stats["deleted"] += 1
        except urllib.error.HTTPError as e:
            if e.code != 404:
                errors.append(f"delete:{server_id}:HTTP{e.code}")
                continue
    conn.execute("DELETE FROM pending_ops WHERE id = ?", (op["id"],))
conn.commit()

# 2. Process pending stores
pending_stores = conn.execute("SELECT id, payload FROM pending_ops WHERE op_type='store'").fetchall()
for op in pending_stores:
    payload = json.loads(op["payload"])
    content = payload.get("content", "")
    local_id = payload.get("local_id")

    if content in remote_contents:
        stats["skipped_dupes"] += 1
        conn.execute("DELETE FROM pending_ops WHERE id = ?", (op["id"],))
        continue

    content_to_send, was_truncated = truncate(content)
    if was_truncated:
        stats["truncated"] += 1

    try:
        result = api_request("POST", "/api/memories", {
            "content": content_to_send,
            "category": payload.get("category", "facts"),
            "tags": payload.get("tags", ""),
            "expanded_keywords": payload.get("expanded_keywords", ""),
            "importance": payload.get("importance", 0.5),
        })
        server_id = result.get("id")
        if server_id and local_id:
            conn.execute("UPDATE memories SET server_id = ? WHERE id = ?", (server_id, local_id))
        remote_contents.add(content_to_send)
        stats["pushed"] += 1
        conn.execute("DELETE FROM pending_ops WHERE id = ?", (op["id"],))
    except Exception as e:
        errors.append(f"store_pending:{op['id']}:{e}")
conn.commit()

# 3. Push orphans
orphans = conn.execute(
    "SELECT id, content, category, tags, expanded_keywords, importance FROM memories WHERE server_id IS NULL"
).fetchall()
for orphan in orphans:
    if orphan["content"] in remote_contents:
        stats["skipped_dupes"] += 1
        for m in remote_memories:
            if m["content"] == orphan["content"]:
                conn.execute("UPDATE memories SET server_id = ? WHERE id = ?", (m["id"], orphan["id"]))
                break
        continue

    content_to_send, was_truncated = truncate(orphan["content"])
    if was_truncated:
        stats["truncated"] += 1

    try:
        result = api_request("POST", "/api/memories", {
            "content": content_to_send,
            "category": orphan["category"],
            "tags": orphan["tags"],
            "expanded_keywords": orphan["expanded_keywords"],
            "importance": orphan["importance"],
        })
        server_id = result.get("id")
        if server_id:
            conn.execute("UPDATE memories SET server_id = ? WHERE id = ?", (server_id, orphan["id"]))
            remote_contents.add(content_to_send)
            stats["pushed"] += 1
    except Exception as e:
        errors.append(f"push_orphan:{orphan['id']}:{e}")
conn.commit()

# 4. Full resync pull: remote → local
if remote_memories:
    try:
        remote = api_request("GET", "/api/memories/sync")
        remote_memories = remote.get("memories", [])
        remote_ids = {m["id"] for m in remote_memories}
        server_time = remote.get("server_time")
    except Exception as e:
        errors.append(f"refetch:{e}")

    local_rows = conn.execute("SELECT id, server_id FROM memories WHERE server_id IS NOT NULL").fetchall()
    for row in local_rows:
        if row["server_id"] not in remote_ids:
            conn.execute("DELETE FROM memories WHERE id = ?", (row["id"],))

    conn.execute("DELETE FROM memories WHERE server_id IS NULL")

    for mem in remote_memories:
        server_id = mem["id"]
        existing = conn.execute("SELECT id FROM memories WHERE server_id = ?", (server_id,)).fetchone()
        if existing:
            conn.execute(
                """UPDATE memories SET content=?, category=?, tags=?,
                   expanded_keywords=?, importance=?, is_sensitive=?,
                   updated_at=? WHERE server_id=?""",
                (mem["content"], mem["category"], mem.get("tags", ""),
                 mem.get("expanded_keywords", ""), mem["importance"],
                 1 if mem.get("is_sensitive") else 0,
                 mem.get("updated_at", ""), server_id))
        else:
            conn.execute(
                """INSERT INTO memories (content, category, tags, expanded_keywords,
                   importance, is_sensitive, created_at, updated_at, server_id)
                   VALUES (?,?,?,?,?,?,?,?,?)""",
                (mem["content"], mem["category"], mem.get("tags", ""),
                 mem.get("expanded_keywords", ""), mem["importance"],
                 1 if mem.get("is_sensitive") else 0,
                 mem.get("created_at", ""), mem.get("updated_at", ""), server_id))
            stats["pulled"] += 1

    if server_time:
        conn.execute("INSERT OR REPLACE INTO sync_meta (key, value) VALUES ('last_sync_ts', ?)", (server_time,))
    conn.commit()

# Final state
local_total = conn.execute("SELECT COUNT(*) as c FROM memories").fetchone()["c"]
remaining_ops = conn.execute("SELECT COUNT(*) as c FROM pending_ops").fetchone()["c"]
remaining_orphans = conn.execute("SELECT COUNT(*) as c FROM memories WHERE server_id IS NULL").fetchone()["c"]
conn.close()

remote_total = len(remote_memories)

print(json.dumps({
    "local": local_total,
    "remote": remote_total,
    "pushed": stats["pushed"],
    "pulled": stats["pulled"],
    "deleted": stats["deleted"],
    "truncated": stats["truncated"],
    "pending_ops": remaining_ops,
    "orphans": remaining_orphans,
    "errors": len(errors),
    "error_details": errors[:5],
    "in_sync": local_total == remote_total and remaining_ops == 0 and remaining_orphans == 0,
}))
PYEOF
)

# Parse the JSON output
if [ -z "$SYNC_OUTPUT" ]; then
  notify_error "Sync Failed" "No output from sync script"
  exit 1
fi

# Check for top-level error
ERROR=$(echo "$SYNC_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',''))" 2>/dev/null)
if [ -n "$ERROR" ]; then
  case "$ERROR" in
    auth_failed:*)
      notify_error "Auth Failed" "API key rejected (${ERROR#auth_failed:}) — update ~/.claude.json"
      ;;
    unreachable:*)
      notify_error "API Unreachable" "Cannot reach claude-memory API"
      ;;
    *)
      notify_error "API Error" "$ERROR"
      ;;
  esac
  exit 1
fi

# Parse sync results
LOCAL=$(echo "$SYNC_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('local',0))" 2>/dev/null)
REMOTE=$(echo "$SYNC_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('remote',0))" 2>/dev/null)
PUSHED=$(echo "$SYNC_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('pushed',0))" 2>/dev/null)
PULLED=$(echo "$SYNC_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('pulled',0))" 2>/dev/null)
SYNC_ERRORS=$(echo "$SYNC_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('errors',0))" 2>/dev/null)
IN_SYNC=$(echo "$SYNC_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('in_sync',False))" 2>/dev/null)

if [ "$IN_SYNC" = "True" ]; then
  if [ "$PUSHED" != "0" ] || [ "$PULLED" != "0" ]; then
    notify_info "Synced: +${PUSHED} pushed, +${PULLED} pulled ($LOCAL total)"
  else
    log "OK: In sync ($LOCAL memories)"
  fi
elif [ "$SYNC_ERRORS" != "0" ]; then
  notify_error "Sync Errors" "${SYNC_ERRORS} errors, local=$LOCAL remote=$REMOTE"
else
  notify_error "Drift" "Local=$LOCAL Remote=$REMOTE"
fi
