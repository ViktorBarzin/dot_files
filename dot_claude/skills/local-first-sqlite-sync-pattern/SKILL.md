---
name: local-first-sqlite-sync-pattern
description: |
  Add offline-resilient local SQLite cache with background sync to a service that
  currently does direct HTTP calls to a remote API. Use when: (1) an MCP server or
  CLI tool makes synchronous HTTP calls that fail when the API is down, (2) you want
  reads to be instant (local) while writes eventually sync to a central server,
  (3) you need a pending_ops queue so writes survive API outages, (4) you want
  backward-compatible mode detection (SQLite-only / hybrid / HTTP-only). Covers
  the SyncEngine pattern, server_id mapping, soft delete for sync, try-sync-then-queue
  writes, and incremental pull via updated_at timestamps.
author: Claude Code
version: 1.0.0
date: 2026-03-14
---

# Local-First SQLite Cache with Background Sync

## Problem

A service makes direct HTTP calls to a remote API for every operation. When the API
goes down (deploy, network issue, DB failure), every call fails immediately. There's
no caching, no retry, no graceful degradation.

## Context / Trigger Conditions

- MCP server, CLI tool, or local service that talks to a remote API
- Reads should be fast regardless of network conditions
- Writes should not be lost during API outages
- Multiple clients need to eventually converge on the same data
- You need backward compatibility with existing direct-HTTP mode

## Solution

### 1. Three-Mode Detection (backward compatible)

```python
SYNC_DISABLED = os.environ.get("SYNC_DISABLE", "") == "1"
HYBRID_MODE = bool(API_KEY) and not SYNC_DISABLED   # local cache + sync
HTTP_ONLY = bool(API_KEY) and SYNC_DISABLED          # legacy direct HTTP
SQLITE_ONLY = not API_KEY                            # standalone local
```

This preserves existing behavior: no API key = local-only, API key + disable flag = direct HTTP.

### 2. Local SQLite Schema Additions

Add to the existing table:
```sql
ALTER TABLE items ADD COLUMN server_id INTEGER;
CREATE UNIQUE INDEX idx_items_server_id ON items(server_id);
```

Add sync infrastructure tables:
```sql
CREATE TABLE pending_ops (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    op_type TEXT NOT NULL,        -- 'store' or 'delete'
    payload TEXT NOT NULL,        -- JSON
    created_at TEXT NOT NULL
);

CREATE TABLE sync_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL           -- e.g., last_sync_ts
);
```

### 3. SyncEngine (background thread)

Key design decisions:
- **Own SQLite connection** with a threading lock (SQLite is not thread-safe by default)
- **Daemon thread** so it dies when the main process exits
- **Initial sync is blocking** (runs before first tool call to populate cache)
- **Background sync** runs every N seconds (configurable, default 60s)

```python
class SyncEngine:
    def __init__(self, db_path, api_base_url, api_key, sync_interval=60):
        self._conn = sqlite3.connect(db_path, check_same_thread=False)
        self._lock = threading.Lock()
        self._stop_event = threading.Event()

    def start(self):
        # 1. Initial sync (blocking) — populate cache before first use
        try:
            self._sync_once()
        except Exception:
            pass  # Start in offline mode
        # 2. Background daemon thread
        self._thread = threading.Thread(target=self._sync_loop, daemon=True)
        self._thread.start()

    def _sync_loop(self):
        while not self._stop_event.is_set():
            self._stop_event.wait(self.sync_interval)
            if self._stop_event.is_set():
                break
            self._sync_once()  # push then pull
```

### 4. Write Pattern: Try-Sync-Then-Queue

For writes, don't just queue blindly — try synchronous push first for lower latency:

```python
def try_sync_store(self, local_id, **data):
    try:
        result = self._api_request("POST", "/api/items", data)
        # Success: update server_id mapping
        self._conn.execute("UPDATE items SET server_id = ? WHERE id = ?",
                          (result["id"], local_id))
        return result["id"]
    except Exception:
        # Failure: queue for background sync
        self.enqueue_store(local_id, **data)
        return None
```

The caller always writes to local SQLite first, then calls `try_sync_store`:
```python
def store(self, args):
    result = self._sqlite_store(...)  # Always succeeds
    if HYBRID_MODE:
        self.sync_engine.try_sync_store(local_id, ...)
    return result
```

### 5. Server-Side: Soft Delete for Sync

Change `DELETE` to soft delete so sync clients can detect deletions:

```sql
-- Instead of: DELETE FROM items WHERE id = $1
UPDATE items SET deleted_at = NOW(), updated_at = NOW() WHERE id = $1
```

Add `deleted_at IS NULL` to ALL read queries (list, recall, secret, etc.).

### 6. Incremental Sync Endpoint

```
GET /api/items/sync?since=<iso_timestamp>
```

- **With `since`**: Returns all items with `updated_at > since` (including soft-deleted)
- **Without `since`**: Returns full dump of non-deleted items (initial sync)
- Response includes `server_time` for the client to use as next `since` value

### 7. Pull Logic: Server Wins

```python
def _pull_changes(self):
    params = f"?since={self.last_sync_ts}" if self.last_sync_ts else ""
    result = self._api_request("GET", f"/api/items/sync{params}")

    for item in result["memories"]:
        if item.get("deleted_at"):
            self._conn.execute("DELETE FROM items WHERE server_id = ?", (item["id"],))
        else:
            # UPSERT by server_id
            existing = self._conn.execute(
                "SELECT id FROM items WHERE server_id = ?", (item["id"],)
            ).fetchone()
            if existing:
                self._conn.execute("UPDATE items SET ... WHERE server_id = ?", ...)
            else:
                self._conn.execute("INSERT INTO items (..., server_id) VALUES (...)", ...)

    self.last_sync_ts = result["server_time"]
```

### 8. Push Logic: Clear Queue on Success

```python
def _push_pending_ops(self):
    ops = self._conn.execute("SELECT * FROM pending_ops ORDER BY id").fetchall()
    for op in ops:
        try:
            if op["op_type"] == "store":
                self._api_request("POST", "/api/items", json.loads(op["payload"]))
            elif op["op_type"] == "delete":
                server_id = json.loads(op["payload"])["server_id"]
                self._api_request("DELETE", f"/api/items/{server_id}")
            self._conn.execute("DELETE FROM pending_ops WHERE id = ?", (op["id"],))
        except Exception:
            raise  # Stop pushing, retry next cycle
```

Important: if a delete returns 404, treat it as success (already deleted on server).

## Verification

1. **Hybrid mode**: Set API key, start server, store a memory, verify it appears in both
   local SQLite and the remote API
2. **Offline resilience**: Kill the API, store/recall — should work via local cache.
   Check `pending_ops` table has queued writes. Restart API, wait 60s, verify queue drained.
3. **Sync correctness**: Store via API directly, wait 60s, verify local cache has it.
   Delete on server, wait 60s, verify local cache removed it.
4. **Backward compat**: No API key = pure SQLite (unchanged). API key + SYNC_DISABLE=1 =
   pure HTTP (unchanged).

## Notes

- `_init_sqlite` must return both `(conn, db_path)` if the SyncEngine needs the resolved
  path to create its own connection
- Use `threading.Event.wait(interval)` instead of `time.sleep()` for the sync loop — it
  allows clean shutdown via `_stop_event.set()`
- The SyncEngine's SQLite connection must use `check_same_thread=False` since it's accessed
  from the background thread
- Always add the `server_id` column migration to the SQLite init (not just the SyncEngine
  init) so the main connection's schema is consistent
- For secrets or sensitive data, prefer API-first reads with local fallback rather than
  caching sensitive content locally
- The `updated_at` index on the server is essential for incremental sync performance:
  `CREATE INDEX idx_items_updated ON items(updated_at)`
