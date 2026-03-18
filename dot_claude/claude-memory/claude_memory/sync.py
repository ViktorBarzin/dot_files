"""Background sync between local SQLite cache and remote API.

Uses only stdlib — no pip install required.
"""

import json
import logging
import sqlite3
import threading
import urllib.error
import urllib.parse
import urllib.request
from typing import Any
from datetime import datetime, timezone
from pathlib import Path

logger = logging.getLogger(__name__)

# Max retries before an individual pending op is permanently skipped
MAX_OP_RETRIES = 5

# Full resync every N sync cycles (~10 min at 60s interval)
FULL_RESYNC_EVERY = 10


class SyncEngine:
    """Background sync between local SQLite cache and remote API."""

    def __init__(self, db_path: str, api_base_url: str, api_key: str, sync_interval: int = 60):
        self.db_path = db_path
        self.api_base_url = api_base_url.rstrip("/")
        self.api_key = api_key
        self.sync_interval = sync_interval

        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None
        self._last_sync_success = False
        self._auth_failed = False

        # Own connection for thread safety
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(db_path, timeout=30.0, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA busy_timeout=30000")
        self._lock = threading.Lock()

        self._init_sync_tables()

    def _init_sync_tables(self) -> None:
        """Create sync-specific tables if they don't exist."""
        with self._lock:
            self._conn.executescript("""
                CREATE TABLE IF NOT EXISTS pending_ops (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    op_type TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    retry_count INTEGER DEFAULT 0
                );

                CREATE TABLE IF NOT EXISTS sync_meta (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );
            """)
            # Add server_id column to memories if missing
            cursor = self._conn.execute("PRAGMA table_info(memories)")
            columns = {row["name"] for row in cursor.fetchall()}
            if "server_id" not in columns:
                self._conn.execute("ALTER TABLE memories ADD COLUMN server_id INTEGER")
                self._conn.execute(
                    "CREATE UNIQUE INDEX IF NOT EXISTS idx_memories_server_id ON memories(server_id)"
                )

            # Add retry_count column to pending_ops if missing (migration)
            cursor = self._conn.execute("PRAGMA table_info(pending_ops)")
            po_columns = {row["name"] for row in cursor.fetchall()}
            if "retry_count" not in po_columns:
                self._conn.execute("ALTER TABLE pending_ops ADD COLUMN retry_count INTEGER DEFAULT 0")

            self._conn.commit()

    @property
    def last_sync_ts(self) -> str | None:
        with self._lock:
            cursor = self._conn.execute(
                "SELECT value FROM sync_meta WHERE key = 'last_sync_ts'"
            )
            row = cursor.fetchone()
            return row["value"] if row else None

    @last_sync_ts.setter
    def last_sync_ts(self, value: str) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT OR REPLACE INTO sync_meta (key, value) VALUES ('last_sync_ts', ?)",
                (value,),
            )
            self._conn.commit()

    @property
    def api_available(self) -> bool:
        return self._last_sync_success

    def start(self) -> None:
        """Start background sync thread. Runs a full resync on startup."""
        # Full sync on startup (blocking, before background thread)
        try:
            self._full_resync()
            self._last_sync_success = True
            self._auth_failed = False
        except Exception as e:
            logger.warning("Startup full sync failed: %s", e)

        self._thread = threading.Thread(target=self._sync_loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        """Signal background thread to stop and wait."""
        self._stop_event.set()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=5)
        self._conn.close()

    def _sync_loop(self) -> None:
        """Periodic sync loop running in background thread."""
        cycle = 0
        while not self._stop_event.is_set():
            self._stop_event.wait(self.sync_interval)
            if self._stop_event.is_set():
                break
            cycle += 1
            try:
                # If auth previously failed, try a lightweight check first
                if self._auth_failed:
                    if not self._check_auth():
                        continue  # Still failing, skip this cycle

                if cycle % FULL_RESYNC_EVERY == 0:
                    self._full_resync()
                else:
                    self._sync_once()
                self._last_sync_success = True
            except Exception as e:
                logger.warning("Sync cycle failed: %s", e)
                self._last_sync_success = False

    def _check_auth(self) -> bool:
        """Lightweight auth check. Returns True if auth is OK."""
        try:
            self._api_request("GET", "/api/auth-check")
            self._auth_failed = False
            logger.info("Auth check passed — resuming sync")
            return True
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                logger.warning(
                    "Auth still failing (HTTP %d) — API key mismatch. "
                    "Update MEMORY_API_KEY in ~/.claude.json", e.code
                )
                return False
            # Non-auth error (e.g. 500) — try the auth-check endpoint might not exist,
            # fall back to /health
            pass
        except Exception:
            pass

        # Fallback: try /health (unauthenticated)
        try:
            url = f"{self.api_base_url}/health"
            req = urllib.request.Request(url, method="GET")
            with urllib.request.urlopen(req, timeout=5):
                pass
            # Server is reachable but auth-check failed — auth is still broken
            return False
        except Exception:
            # Server unreachable — not an auth problem
            return False

    def _sync_once(self) -> None:
        """Push pending ops, then pull remote changes. Both run independently."""
        push_ok = self._push_pending_ops()
        pull_ok = self._pull_changes()
        if not push_ok and not pull_ok:
            raise RuntimeError("Both push and pull failed")

    def _full_resync(self) -> None:
        """Full cache replacement from server — handles drift, deletes, schema changes."""
        # Step 1: Push orphaned local-only records (deduplicated)
        self._push_orphans()

        # Step 2: Pull everything from server (no since filter = non-deleted only)
        result = self._api_request("GET", "/api/memories/sync")
        memories = result.get("memories", [])
        server_time = result.get("server_time")
        server_ids = {m["id"] for m in memories}

        with self._lock:
            # Delete local records whose server_id no longer exists on server
            local_rows = self._conn.execute(
                "SELECT id, server_id FROM memories WHERE server_id IS NOT NULL"
            ).fetchall()
            for row in local_rows:
                if row["server_id"] not in server_ids:
                    self._conn.execute("DELETE FROM memories WHERE id = ?", (row["id"],))

            # Delete remaining orphans (already pushed or duplicates)
            self._conn.execute("DELETE FROM memories WHERE server_id IS NULL")

            # Upsert all server records
            for mem in memories:
                server_id = mem["id"]
                existing = self._conn.execute(
                    "SELECT id FROM memories WHERE server_id = ?", (server_id,)
                ).fetchone()

                if existing:
                    self._conn.execute(
                        """UPDATE memories SET content=?, category=?, tags=?,
                           expanded_keywords=?, importance=?, is_sensitive=?,
                           updated_at=? WHERE server_id=?""",
                        (
                            mem["content"], mem["category"], mem.get("tags", ""),
                            mem.get("expanded_keywords", ""), mem["importance"],
                            1 if mem.get("is_sensitive") else 0,
                            mem.get("updated_at", ""), server_id,
                        ),
                    )
                else:
                    self._conn.execute(
                        """INSERT INTO memories (content, category, tags, expanded_keywords,
                           importance, is_sensitive, created_at, updated_at, server_id)
                           VALUES (?,?,?,?,?,?,?,?,?)""",
                        (
                            mem["content"], mem["category"], mem.get("tags", ""),
                            mem.get("expanded_keywords", ""), mem["importance"],
                            1 if mem.get("is_sensitive") else 0,
                            mem.get("created_at", ""), mem.get("updated_at", ""), server_id,
                        ),
                    )

            self._conn.commit()

        if server_time:
            self.last_sync_ts = server_time

    def _push_orphans(self) -> None:
        """Push local-only records to server, skipping content duplicates."""
        with self._lock:
            orphans = self._conn.execute(
                "SELECT id, content, category, tags, expanded_keywords, importance "
                "FROM memories WHERE server_id IS NULL"
            ).fetchall()

        if not orphans:
            return

        # Get all server content for dedup comparison
        result = self._api_request("GET", "/api/memories/sync")
        server_contents = {m["content"] for m in result.get("memories", [])}

        for orphan in orphans:
            if orphan["content"] in server_contents:
                continue  # Skip duplicate
            try:
                resp = self._api_request("POST", "/api/memories", {
                    "content": orphan["content"],
                    "category": orphan["category"],
                    "tags": orphan["tags"],
                    "expanded_keywords": orphan["expanded_keywords"],
                    "importance": orphan["importance"],
                })
                server_id = resp.get("id")
                if server_id:
                    with self._lock:
                        self._conn.execute(
                            "UPDATE memories SET server_id=? WHERE id=?",
                            (server_id, orphan["id"]),
                        )
                        self._conn.commit()
            except Exception:
                pass  # Will be cleaned up by the full resync delete step

    def _api_request(self, method: str, path: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
        """Make an HTTP request to the memory API."""
        url = f"{self.api_base_url}{path}"
        data = json.dumps(body).encode() if body else None
        req = urllib.request.Request(
            url,
            data=data,
            method=method,
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                result: dict[str, Any] = json.loads(resp.read().decode())
                return result
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                self._auth_failed = True
                logger.warning(
                    "Auth failed (HTTP %d) — API key may have rotated. "
                    "Update MEMORY_API_KEY in ~/.claude.json", e.code
                )
            raise

    def _push_pending_ops(self) -> bool:
        """Push queued operations to the API server. Returns True on success."""
        with self._lock:
            cursor = self._conn.execute(
                "SELECT id, op_type, payload, retry_count FROM pending_ops ORDER BY id"
            )
            ops = cursor.fetchall()

        if not ops:
            return True

        all_ok = True
        for op in ops:
            op_id = op["id"]
            op_type = op["op_type"]
            payload = json.loads(op["payload"])
            retry_count = op["retry_count"] or 0

            # Skip ops that have exceeded retry limit
            if retry_count >= MAX_OP_RETRIES:
                logger.warning(
                    "Skipping op %d (%s) after %d retries — removing from queue",
                    op_id, op_type, retry_count,
                )
                with self._lock:
                    self._conn.execute("DELETE FROM pending_ops WHERE id = ?", (op_id,))
                    self._conn.commit()
                continue

            try:
                if op_type == "store":
                    result = self._api_request("POST", "/api/memories", payload)
                    server_id = result.get("id")
                    if server_id and payload.get("local_id"):
                        with self._lock:
                            self._conn.execute(
                                "UPDATE memories SET server_id = ? WHERE id = ?",
                                (server_id, payload["local_id"]),
                            )
                            self._conn.commit()
                elif op_type == "delete":
                    server_id = payload.get("server_id")
                    if server_id:
                        try:
                            self._api_request("DELETE", f"/api/memories/{server_id}")
                        except urllib.error.HTTPError as e:
                            if e.code == 404:
                                pass  # Already deleted on server
                            else:
                                raise

                # Remove from pending queue on success
                with self._lock:
                    self._conn.execute("DELETE FROM pending_ops WHERE id = ?", (op_id,))
                    self._conn.commit()

            except urllib.error.HTTPError as e:
                if e.code in (401, 403):
                    self._auth_failed = True
                    logger.warning("Auth failed (HTTP %d) — aborting push", e.code)
                    return False  # Abort entire push — no point retrying with bad key
                # Increment retry count for non-auth errors
                with self._lock:
                    self._conn.execute(
                        "UPDATE pending_ops SET retry_count = retry_count + 1 WHERE id = ?",
                        (op_id,),
                    )
                    self._conn.commit()
                logger.warning("Failed to push op %d (%s): HTTP %d", op_id, op_type, e.code)
                all_ok = False
            except Exception as e:
                with self._lock:
                    self._conn.execute(
                        "UPDATE pending_ops SET retry_count = retry_count + 1 WHERE id = ?",
                        (op_id,),
                    )
                    self._conn.commit()
                logger.warning("Failed to push op %d (%s): %s", op_id, op_type, e)
                all_ok = False

        return all_ok

    def _pull_changes(self) -> bool:
        """Pull changes from server since last sync. Returns True on success."""
        try:
            params = ""
            ts = self.last_sync_ts
            if ts:
                params = f"?since={urllib.parse.quote(ts, safe='')}"

            result = self._api_request("GET", f"/api/memories/sync{params}")
            memories = result.get("memories", [])
            server_time = result.get("server_time")

            with self._lock:
                for mem in memories:
                    server_id = mem["id"]
                    deleted_at = mem.get("deleted_at")

                    if deleted_at:
                        # Remove from local cache
                        self._conn.execute(
                            "DELETE FROM memories WHERE server_id = ?", (server_id,)
                        )
                    else:
                        # Upsert by server_id (server wins)
                        existing = self._conn.execute(
                            "SELECT id FROM memories WHERE server_id = ?", (server_id,)
                        ).fetchone()

                        if existing:
                            self._conn.execute(
                                """UPDATE memories SET content = ?, category = ?, tags = ?,
                                   expanded_keywords = ?, importance = ?, is_sensitive = ?,
                                   updated_at = ? WHERE server_id = ?""",
                                (
                                    mem["content"],
                                    mem["category"],
                                    mem.get("tags", ""),
                                    mem.get("expanded_keywords", ""),
                                    mem["importance"],
                                    1 if mem.get("is_sensitive") else 0,
                                    mem.get("updated_at", datetime.now(timezone.utc).isoformat()),
                                    server_id,
                                ),
                            )
                        else:
                            self._conn.execute(
                                """INSERT INTO memories
                                   (content, category, tags, expanded_keywords, importance,
                                    is_sensitive, created_at, updated_at, server_id)
                                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                                (
                                    mem["content"],
                                    mem["category"],
                                    mem.get("tags", ""),
                                    mem.get("expanded_keywords", ""),
                                    mem["importance"],
                                    1 if mem.get("is_sensitive") else 0,
                                    mem.get("created_at", datetime.now(timezone.utc).isoformat()),
                                    mem.get("updated_at", datetime.now(timezone.utc).isoformat()),
                                    server_id,
                                ),
                            )
                self._conn.commit()

            if server_time:
                self.last_sync_ts = server_time
            return True

        except Exception as e:
            logger.warning("Pull changes failed: %s", e)
            return False

    def enqueue_store(
        self,
        local_id: int,
        content: str,
        category: str,
        tags: str,
        expanded_keywords: str,
        importance: float,
        force_sensitive: bool = False,
    ) -> None:
        """Queue a store operation for later sync."""
        payload = {
            "local_id": local_id,
            "content": content,
            "category": category,
            "tags": tags,
            "expanded_keywords": expanded_keywords,
            "importance": importance,
            "force_sensitive": force_sensitive,
        }
        now = datetime.now(timezone.utc).isoformat()
        with self._lock:
            self._conn.execute(
                "INSERT INTO pending_ops (op_type, payload, created_at) VALUES (?, ?, ?)",
                ("store", json.dumps(payload), now),
            )
            self._conn.commit()

    def enqueue_delete(self, server_id: int) -> None:
        """Queue a delete operation for later sync."""
        payload = {"server_id": server_id}
        now = datetime.now(timezone.utc).isoformat()
        with self._lock:
            self._conn.execute(
                "INSERT INTO pending_ops (op_type, payload, created_at) VALUES (?, ?, ?)",
                ("delete", json.dumps(payload), now),
            )
            self._conn.commit()

    def try_sync_store(
        self,
        local_id: int,
        content: str,
        category: str,
        tags: str,
        expanded_keywords: str,
        importance: float,
        force_sensitive: bool = False,
    ) -> int | None:
        """Try to sync a store immediately. Returns server_id or None if failed."""
        if self._auth_failed:
            self.enqueue_store(
                local_id, content, category, tags, expanded_keywords, importance, force_sensitive
            )
            return None
        try:
            result = self._api_request("POST", "/api/memories", {
                "content": content,
                "category": category,
                "tags": tags,
                "expanded_keywords": expanded_keywords,
                "importance": importance,
                "force_sensitive": force_sensitive,
            })
            server_id = result.get("id")
            if server_id:
                with self._lock:
                    self._conn.execute(
                        "UPDATE memories SET server_id = ? WHERE id = ?",
                        (server_id, local_id),
                    )
                    self._conn.commit()
            return server_id
        except Exception:
            self.enqueue_store(
                local_id, content, category, tags, expanded_keywords, importance, force_sensitive
            )
            return None

    def try_sync_delete(self, server_id: int) -> bool:
        """Try to sync a delete immediately. Returns True if successful."""
        if self._auth_failed:
            self.enqueue_delete(server_id)
            return False
        try:
            self._api_request("DELETE", f"/api/memories/{server_id}")
            return True
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return True  # Already deleted on server — not an error
            self.enqueue_delete(server_id)
            return False
        except Exception:
            self.enqueue_delete(server_id)
            return False

    def get_counts(self) -> dict[str, Any]:
        """Get memory counts for diagnostics."""
        with self._lock:
            total = self._conn.execute("SELECT COUNT(*) as c FROM memories").fetchone()["c"]
            by_cat = self._conn.execute(
                "SELECT category, COUNT(*) as c FROM memories GROUP BY category ORDER BY c DESC"
            ).fetchall()
            orphans = self._conn.execute(
                "SELECT COUNT(*) as c FROM memories WHERE server_id IS NULL"
            ).fetchone()["c"]
            pending = self._conn.execute(
                "SELECT COUNT(*) as c FROM pending_ops"
            ).fetchone()["c"]

        return {
            "total": total,
            "by_category": {row["category"]: row["c"] for row in by_cat},
            "orphans_no_server_id": orphans,
            "pending_ops": pending,
            "last_sync_ts": self.last_sync_ts,
            "auth_failed": self._auth_failed,
            "last_sync_success": self._last_sync_success,
        }
