#!/usr/bin/env python3
"""Claude Code hook: sync local SQLite ↔ remote PostgreSQL for claude-memory.

Used as SessionStart hook (full sync) and Stop hook (push pending).
Outputs additional context to stderr for the hook system.
Sends macOS notification on sync failure.
"""
import json
import os
import sqlite3
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

DB_PATH = os.path.expanduser("~/.claude/claude-memory/memory/memory.db")
MAX_LEN = 800

def get_api_config():
    """Read API key from ~/.claude.json SSE config."""
    config_path = os.path.expanduser("~/.claude.json")
    try:
        with open(config_path) as f:
            d = json.load(f)
        mc = d.get("mcpServers", {})
        cm = mc.get("claude_memory", mc.get("claude-memory", {}))
        headers = cm.get("headers", {})
        auth = headers.get("Authorization", "")
        key = auth.replace("Bearer ", "").strip()
        url = cm.get("url", "").replace("/mcp/sse", "").replace("/mcp/mcp", "")
        return url, key
    except Exception:
        return None, None


def api_request(api_base, api_key, method, path, body=None):
    url = f"{api_base}{path}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode())


def notify(title, msg):
    """Send macOS notification."""
    try:
        subprocess.run([
            "osascript", "-e",
            f'display notification "{msg}" with title "Memory Sync" subtitle "{title}" sound name "Basso"'
        ], capture_output=True, timeout=5)
    except Exception:
        pass


def truncate(content):
    if len(content) <= MAX_LEN:
        return content
    return content[:MAX_LEN - 15] + " [truncated]"


def full_sync(api_base, api_key):
    """Full bidirectional sync. Returns (pushed, pulled, errors)."""
    if not os.path.exists(DB_PATH):
        return 0, 0, ["no_local_db"]

    conn = sqlite3.connect(DB_PATH, timeout=30.0)
    conn.row_factory = sqlite3.Row
    errors = []
    pushed = 0
    pulled = 0

    # Get remote state
    try:
        remote = api_request(api_base, api_key, "GET", "/api/memories/sync")
    except Exception as e:
        conn.close()
        return 0, 0, [f"fetch_failed:{e}"]

    remote_memories = remote.get("memories", [])
    remote_contents = {m["content"] for m in remote_memories}
    remote_ids = {m["id"] for m in remote_memories}
    server_time = remote.get("server_time")

    # Push pending deletes
    for op in conn.execute("SELECT id, payload FROM pending_ops WHERE op_type='delete'").fetchall():
        payload = json.loads(op["payload"])
        sid = payload.get("server_id")
        if sid:
            try:
                api_request(api_base, api_key, "DELETE", f"/api/memories/{sid}")
            except urllib.error.HTTPError as e:
                if e.code != 404:
                    errors.append(f"del:{sid}")
                    continue
        conn.execute("DELETE FROM pending_ops WHERE id = ?", (op["id"],))
        pushed += 1
    conn.commit()

    # Push pending stores
    for op in conn.execute("SELECT id, payload FROM pending_ops WHERE op_type='store'").fetchall():
        payload = json.loads(op["payload"])
        content = payload.get("content", "")
        local_id = payload.get("local_id")
        if content in remote_contents:
            conn.execute("DELETE FROM pending_ops WHERE id = ?", (op["id"],))
            continue
        try:
            result = api_request(api_base, api_key, "POST", "/api/memories", {
                "content": truncate(content),
                "category": payload.get("category", "facts"),
                "tags": payload.get("tags", ""),
                "expanded_keywords": payload.get("expanded_keywords", ""),
                "importance": payload.get("importance", 0.5),
            })
            sid = result.get("id")
            if sid and local_id:
                conn.execute("UPDATE memories SET server_id = ? WHERE id = ?", (sid, local_id))
            remote_contents.add(content)
            pushed += 1
            conn.execute("DELETE FROM pending_ops WHERE id = ?", (op["id"],))
        except Exception as e:
            errors.append(f"store:{op['id']}")
    conn.commit()

    # Push orphans
    for orphan in conn.execute(
        "SELECT id, content, category, tags, expanded_keywords, importance FROM memories WHERE server_id IS NULL"
    ).fetchall():
        if orphan["content"] in remote_contents:
            for m in remote_memories:
                if m["content"] == orphan["content"]:
                    conn.execute("UPDATE memories SET server_id = ? WHERE id = ?", (m["id"], orphan["id"]))
                    break
            continue
        try:
            result = api_request(api_base, api_key, "POST", "/api/memories", {
                "content": truncate(orphan["content"]),
                "category": orphan["category"],
                "tags": orphan["tags"],
                "expanded_keywords": orphan["expanded_keywords"],
                "importance": orphan["importance"],
            })
            sid = result.get("id")
            if sid:
                conn.execute("UPDATE memories SET server_id = ? WHERE id = ?", (sid, orphan["id"]))
                remote_contents.add(orphan["content"])
                pushed += 1
        except Exception as e:
            errors.append(f"orphan:{orphan['id']}")
    conn.commit()

    # Pull: re-fetch remote and do full resync
    try:
        remote = api_request(api_base, api_key, "GET", "/api/memories/sync")
        remote_memories = remote.get("memories", [])
        remote_ids = {m["id"] for m in remote_memories}
        server_time = remote.get("server_time")
    except Exception:
        pass

    # Remove stale local
    for row in conn.execute("SELECT id, server_id FROM memories WHERE server_id IS NOT NULL").fetchall():
        if row["server_id"] not in remote_ids:
            conn.execute("DELETE FROM memories WHERE id = ?", (row["id"],))
    conn.execute("DELETE FROM memories WHERE server_id IS NULL")

    # Upsert server records
    for mem in remote_memories:
        sid = mem["id"]
        existing = conn.execute("SELECT id FROM memories WHERE server_id = ?", (sid,)).fetchone()
        if existing:
            conn.execute(
                """UPDATE memories SET content=?, category=?, tags=?,
                   expanded_keywords=?, importance=?, is_sensitive=?,
                   updated_at=? WHERE server_id=?""",
                (mem["content"], mem["category"], mem.get("tags", ""),
                 mem.get("expanded_keywords", ""), mem["importance"],
                 1 if mem.get("is_sensitive") else 0,
                 mem.get("updated_at", ""), sid))
        else:
            conn.execute(
                """INSERT INTO memories (content, category, tags, expanded_keywords,
                   importance, is_sensitive, created_at, updated_at, server_id)
                   VALUES (?,?,?,?,?,?,?,?,?)""",
                (mem["content"], mem["category"], mem.get("tags", ""),
                 mem.get("expanded_keywords", ""), mem["importance"],
                 1 if mem.get("is_sensitive") else 0,
                 mem.get("created_at", ""), mem.get("updated_at", ""), sid))
            pulled += 1

    if server_time:
        conn.execute("INSERT OR REPLACE INTO sync_meta (key, value) VALUES ('last_sync_ts', ?)", (server_time,))
    conn.commit()

    local_total = conn.execute("SELECT COUNT(*) as c FROM memories").fetchone()["c"]
    conn.close()

    return pushed, pulled, errors


def main():
    api_base, api_key = get_api_config()
    if not api_base or not api_key:
        # No SSE config — nothing to sync
        sys.exit(0)

    # Quick connectivity + auth check
    try:
        api_request(api_base, api_key, "GET", "/api/auth-check")
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            notify("Auth Failed", f"Memory API key rejected (HTTP {e.code})")
            hook_output = {"additional_context": f"Memory sync auth failed (HTTP {e.code}). API key in ~/.claude.json may need updating."}
            print(json.dumps(hook_output))
            sys.exit(0)
        notify("API Error", f"Memory API returned HTTP {e.code}")
        sys.exit(0)
    except Exception as e:
        notify("Unreachable", "Cannot reach claude-memory API")
        hook_output = {"additional_context": "Memory sync failed: API unreachable. Local SQLite may be stale."}
        print(json.dumps(hook_output))
        sys.exit(0)

    pushed, pulled, errors = full_sync(api_base, api_key)

    if errors:
        notify("Sync Errors", f"{len(errors)} errors during memory sync")
        hook_output = {"additional_context": f"Memory sync completed with {len(errors)} errors. Pushed {pushed}, pulled {pulled}."}
        print(json.dumps(hook_output))
    elif pushed > 0 or pulled > 0:
        hook_output = {"additional_context": f"Memory sync: pushed {pushed}, pulled {pulled} memories."}
        print(json.dumps(hook_output))
    # If nothing changed, output nothing (silent success)


if __name__ == "__main__":
    main()
