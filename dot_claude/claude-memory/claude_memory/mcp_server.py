#!/usr/bin/env python3
"""
Claude Memory MCP Server — standalone memory server with multi-user support.

Supports three modes:
  1. SQLite-only: local file-based storage when no API key is configured
  2. Hybrid (default when API key set): local SQLite cache + background sync
  3. HTTP-only (legacy): direct HTTP to API, no local cache (MEMORY_SYNC_DISABLE=1)

Uses only stdlib (urllib) — no pip install required.
"""

import json
import logging
import os
import sqlite3
import sys
import urllib.error
import urllib.request
from typing import Any

logger = logging.getLogger(__name__)

PROTOCOL_VERSION = "2024-11-05"
SERVER_NAME = "claude-memory"
SERVER_VERSION = "2.0.0"

# API configuration — support both MEMORY_* (primary) and CLAUDE_MEMORY_* (fallback) env vars
API_BASE_URL = os.environ.get("MEMORY_API_URL") or os.environ.get("CLAUDE_MEMORY_API_URL", "http://localhost:8080")
API_KEY = os.environ.get("MEMORY_API_KEY") or os.environ.get("CLAUDE_MEMORY_API_KEY", "")

# Mode detection
SYNC_DISABLED = os.environ.get("MEMORY_SYNC_DISABLE", "") == "1"
HYBRID_MODE = bool(API_KEY) and not SYNC_DISABLED
HTTP_ONLY = bool(API_KEY) and SYNC_DISABLED
SQLITE_ONLY = not API_KEY


def _api_request(method: str, path: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
    """Make an HTTP request to the memory API."""
    url = f"{API_BASE_URL}{path}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            result: dict[str, Any] = json.loads(resp.read().decode())
            return result
    except urllib.error.HTTPError as e:
        error_body = e.read().decode() if e.fp else str(e)
        raise RuntimeError(f"API error {e.code}: {error_body}") from e
    except urllib.error.URLError as e:
        raise RuntimeError(f"API connection error: {e.reason}") from e


# ─── SQLite initialization ────────────────────────────────────────────────────

def _get_db_path(db_path: str | None = None) -> str:
    """Resolve the SQLite database path."""
    if db_path is not None:
        return db_path

    memory_home = os.path.expandvars(
        os.path.expanduser(os.environ.get("MEMORY_HOME", "~/.claude/claude-memory"))
    )
    db_path = os.environ.get(
        "MEMORY_DB",
        os.path.join(memory_home, "memory", "memory.db"),
    )
    resolved = os.path.expandvars(os.path.expanduser(db_path))

    # Migration fallback: if the new path doesn't exist but legacy metaclaw path does, use that
    if not os.path.exists(resolved):
        legacy_home = os.path.expanduser("~/.claude/metaclaw")
        legacy_db = os.path.join(legacy_home, "memory", "memory.db")
        if os.path.exists(legacy_db):
            return legacy_db

    return resolved


SCHEMA_VERSION = 2


def _migrate_sqlite(conn: sqlite3.Connection) -> None:
    """Version-based SQLite schema migrations."""
    current = conn.execute("PRAGMA user_version").fetchone()[0]
    if current < 1:
        # Add server_id column for hybrid mode sync
        cursor = conn.execute("PRAGMA table_info(memories)")
        columns = {row["name"] for row in cursor.fetchall()}
        if "server_id" not in columns:
            conn.execute("ALTER TABLE memories ADD COLUMN server_id INTEGER")
            conn.execute(
                "CREATE UNIQUE INDEX IF NOT EXISTS idx_memories_server_id ON memories(server_id)"
            )
    if current < 2:
        # Ensure pending_ops has retry_count (sync.py also handles this, but belt-and-suspenders)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS pending_ops (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                op_type TEXT NOT NULL,
                payload TEXT NOT NULL,
                created_at TEXT NOT NULL,
                retry_count INTEGER DEFAULT 0
            )
        """)
        # Add retry_count if pending_ops already exists without it
        cursor = conn.execute("PRAGMA table_info(pending_ops)")
        po_columns = {row["name"] for row in cursor.fetchall()}
        if "retry_count" not in po_columns:
            conn.execute("ALTER TABLE pending_ops ADD COLUMN retry_count INTEGER DEFAULT 0")
    conn.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
    conn.commit()


def _init_sqlite(db_path: str | None = None) -> tuple[sqlite3.Connection, str]:
    """Initialize SQLite database."""
    from pathlib import Path

    db_path = _get_db_path(db_path)
    Path(os.path.dirname(db_path)).mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(db_path, timeout=30.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=30000")
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT NOT NULL,
            category TEXT DEFAULT 'facts',
            tags TEXT DEFAULT '',
            expanded_keywords TEXT DEFAULT '',
            importance REAL DEFAULT 0.5,
            is_sensitive INTEGER DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    """)
    # Version-based schema migrations
    _migrate_sqlite(conn)

    cursor.execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
            content, category, tags, expanded_keywords,
            content='memories', content_rowid='id'
        )
    """)
    cursor.execute("""
        CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
            INSERT INTO memories_fts(rowid, content, category, tags, expanded_keywords)
            VALUES (new.id, new.content, new.category, new.tags, new.expanded_keywords);
        END
    """)
    cursor.execute("""
        CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
            INSERT INTO memories_fts(memories_fts, rowid, content, category, tags, expanded_keywords)
            VALUES ('delete', old.id, old.content, old.category, old.tags, old.expanded_keywords);
        END
    """)
    cursor.execute("""
        CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
            INSERT INTO memories_fts(memories_fts, rowid, content, category, tags, expanded_keywords)
            VALUES ('delete', old.id, old.content, old.category, old.tags, old.expanded_keywords);
            INSERT INTO memories_fts(rowid, content, category, tags, expanded_keywords)
            VALUES (new.id, new.content, new.category, new.tags, new.expanded_keywords);
        END
    """)
    conn.commit()
    return conn, db_path


# ─── Tool definitions ────────────────────────────────────────────────────────

TOOLS = [
    {
        "name": "memory_store",
        "description": "Store a fact or memory in persistent storage. Use this to remember important information about the user, their preferences, projects, decisions, or people they mention.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "content": {"type": "string", "description": "The fact or memory to store"},
                "category": {
                    "type": "string",
                    "enum": ["facts", "preferences", "projects", "people", "decisions"],
                    "description": "Category for organizing the memory",
                    "default": "facts",
                },
                "tags": {"type": "string", "description": "Comma-separated tags", "default": ""},
                "importance": {
                    "type": "number",
                    "description": "Importance 0.0-1.0",
                    "default": 0.5,
                    "minimum": 0.0,
                    "maximum": 1.0,
                },
                "expanded_keywords": {
                    "type": "string",
                    "description": "REQUIRED. Space-separated semantically related search terms (MINIMUM 5 words). Generate keywords that someone might search for when this memory would be relevant. Include synonyms, related concepts, and adjacent topics.",
                },
                "force_sensitive": {
                    "type": "boolean",
                    "description": "If true, mark this memory as sensitive regardless of auto-detection. Sensitive memories have their content encrypted at rest.",
                    "default": False,
                },
            },
            "required": ["content", "expanded_keywords"],
        },
    },
    {
        "name": "memory_recall",
        "description": "Retrieve relevant memories based on context. Uses full-text search to find stored memories.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "context": {"type": "string", "description": "The context or topic to recall memories about"},
                "expanded_query": {
                    "type": "string",
                    "description": "REQUIRED. Space-separated semantically related search terms (MINIMUM 5 words).",
                },
                "category": {
                    "type": "string",
                    "enum": ["facts", "preferences", "projects", "people", "decisions"],
                    "description": "Optional: filter results to a specific category",
                },
                "sort_by": {
                    "type": "string",
                    "enum": ["importance", "relevance"],
                    "description": "Sort order",
                    "default": "importance",
                },
                "limit": {"type": "integer", "description": "Max results", "default": 10},
            },
            "required": ["context", "expanded_query"],
        },
    },
    {
        "name": "memory_list",
        "description": "List recent memories, optionally filtered by category.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "category": {
                    "type": "string",
                    "enum": ["facts", "preferences", "projects", "people", "decisions"],
                },
                "limit": {"type": "integer", "default": 20},
            },
        },
    },
    {
        "name": "memory_delete",
        "description": "Delete a memory by ID.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {"type": "integer", "description": "The ID of the memory to delete"},
            },
            "required": ["id"],
        },
    },
    {
        "name": "secret_get",
        "description": "Retrieve the decrypted content of a sensitive memory. Only works for memories marked as sensitive.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {"type": "integer", "description": "The ID of the sensitive memory to retrieve"},
            },
            "required": ["id"],
        },
    },
    {
        "name": "memory_count",
        "description": "Get memory counts by category from local cache and sync status. Useful for diagnostics.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
]


class MemoryServer:
    """MCP server for persistent memory management."""

    def __init__(self, sqlite_db_path: str | None = None) -> None:
        self.sqlite_conn: sqlite3.Connection | None = None
        self.sync_engine: Any = None

        if SQLITE_ONLY or HYBRID_MODE:
            self.sqlite_conn, resolved_path = _init_sqlite(sqlite_db_path)

            if HYBRID_MODE:
                from claude_memory.sync import SyncEngine
                sync_interval = int(os.environ.get("MEMORY_SYNC_INTERVAL", "60"))
                self.sync_engine = SyncEngine(
                    db_path=resolved_path,
                    api_base_url=API_BASE_URL,
                    api_key=API_KEY,
                    sync_interval=sync_interval,
                )
                self.sync_engine.start()

    def __del__(self) -> None:
        if self.sync_engine:
            self.sync_engine.stop()

    # ── Tool methods ────────────────────────────────────────────────

    def memory_store(self, args: dict[str, Any]) -> str:
        content = args.get("content")
        if not content:
            raise ValueError("content is required")
        category = args.get("category", "facts")
        tags = args.get("tags", "")
        importance = max(0.0, min(1.0, float(args.get("importance", 0.5))))
        expanded_keywords = args.get("expanded_keywords", "")
        force_sensitive = bool(args.get("force_sensitive", False))

        if HTTP_ONLY:
            result = _api_request("POST", "/api/memories", {
                "content": content,
                "category": category,
                "tags": tags,
                "expanded_keywords": expanded_keywords,
                "importance": importance,
                "force_sensitive": force_sensitive,
            })
            return f"Stored memory #{result['id']} in category '{result['category']}' with importance {result['importance']:.1f}"

        # SQLite-only or Hybrid: write to local SQLite first
        result_text = self._sqlite_store(content, category, tags, importance, expanded_keywords, force_sensitive)

        if HYBRID_MODE and self.sync_engine:
            # Extract local_id from result text
            local_id = int(result_text.split("#")[1].split(" ")[0])
            self.sync_engine.try_sync_store(
                local_id, content, category, tags, expanded_keywords, importance, force_sensitive
            )

        return result_text

    def memory_recall(self, args: dict[str, Any]) -> str:
        context = args.get("context")
        if not context:
            raise ValueError("context is required")
        expanded_query = args.get("expanded_query", "")
        category = args.get("category")
        sort_by = args.get("sort_by", "importance")
        limit = args.get("limit", 10)

        if HTTP_ONLY:
            result = _api_request("POST", "/api/memories/recall", {
                "context": context,
                "expanded_query": expanded_query,
                "category": category,
                "sort_by": sort_by,
                "limit": limit,
            })
            rows = result.get("memories", [])
            if not rows:
                filter_desc = f" in category '{category}'" if category else ""
                return f"No memories found matching: {context}{filter_desc}"

            sort_desc = "by relevance" if sort_by == "relevance" else "by importance"
            filter_desc = f" in '{category}'" if category else ""
            results = []
            for row in rows:
                results.append(
                    f"#{row['id']} [{row['category']}] (importance: {row['importance']:.1f}) {row['content']}"
                    f"\n  Tags: {row.get('tags') or 'none'} | Stored: {row['created_at']}"
                )
            return f"Found {len(rows)} memories{filter_desc} ({sort_desc}):\n\n" + "\n\n".join(results)

        # SQLite-only or Hybrid: always read from local cache
        return self._sqlite_recall(context, expanded_query, category, sort_by, limit)

    def memory_list(self, args: dict[str, Any]) -> str:
        category = args.get("category")
        limit = args.get("limit", 20)

        if HTTP_ONLY:
            params = f"?limit={limit}"
            if category:
                params += f"&category={category}"
            result = _api_request("GET", f"/api/memories{params}")
            rows = result.get("memories", [])
            if not rows:
                return f"No memories in category '{category}'" if category else "No memories stored yet"

            results = []
            for row in rows:
                results.append(
                    f"#{row['id']} [{row['category']}] {row['content']}"
                    f"\n  Importance: {row['importance']:.1f} | Tags: {row.get('tags') or 'none'} | Stored: {row['created_at']}"
                )
            header = "Recent memories"
            if category:
                header += f" in '{category}'"
            return header + f" ({len(rows)} shown):\n\n" + "\n\n".join(results)

        # SQLite-only or Hybrid: always read from local cache
        return self._sqlite_list(category, limit)

    def memory_delete(self, args: dict[str, Any]) -> str:
        memory_id = args.get("id")
        if memory_id is None:
            raise ValueError("id is required")

        if HTTP_ONLY:
            result = _api_request("DELETE", f"/api/memories/{memory_id}")
            return f"Deleted memory #{result['deleted']}: {result['preview']}..."

        # SQLite-only or Hybrid: delete from local SQLite
        # In hybrid mode, also try to sync delete to server
        server_id: int | None = None
        if HYBRID_MODE and self.sync_engine and self.sqlite_conn:
            cursor = self.sqlite_conn.cursor()
            cursor.execute("SELECT server_id FROM memories WHERE id = ?", (memory_id,))
            row = cursor.fetchone()
            server_id = row["server_id"] if row and row["server_id"] else None

        result_text = self._sqlite_delete(memory_id)

        if HYBRID_MODE and self.sync_engine and server_id:
            self.sync_engine.try_sync_delete(server_id)

        return result_text

    def secret_get(self, args: dict[str, Any]) -> str:
        memory_id = args.get("id")
        if memory_id is None:
            raise ValueError("id is required")

        if HTTP_ONLY or HYBRID_MODE:
            # Secrets should be fetched from API when available
            try:
                result = _api_request("POST", f"/api/memories/{memory_id}/secret")
                return f"#{result['id']} [{result['category']}] {result['content']}"
            except Exception:
                if HYBRID_MODE:
                    # Fall back to local SQLite
                    return self._sqlite_secret_get(memory_id)
                raise

        return self._sqlite_secret_get(memory_id)

    def memory_count(self, args: dict[str, Any]) -> str:
        if self.sync_engine:
            counts = self.sync_engine.get_counts()
            lines = [f"Local memories: {counts['total']}"]
            for cat, n in counts["by_category"].items():
                lines.append(f"  {cat}: {n}")
            lines.append(f"Orphans (no server_id): {counts['orphans_no_server_id']}")
            lines.append(f"Pending ops: {counts['pending_ops']}")
            lines.append(f"Last sync: {counts['last_sync_ts'] or 'never'}")
            lines.append(f"Auth failed: {counts['auth_failed']}")
            lines.append(f"Last sync success: {counts['last_sync_success']}")
            return "\n".join(lines)

        if self.sqlite_conn:
            cursor = self.sqlite_conn.cursor()
            cursor.execute("SELECT COUNT(*) as c FROM memories")
            total = cursor.fetchone()["c"]
            cursor.execute("SELECT category, COUNT(*) as c FROM memories GROUP BY category ORDER BY c DESC")
            by_cat = cursor.fetchall()
            lines = [f"Local memories (SQLite-only): {total}"]
            for row in by_cat:
                lines.append(f"  {row['category']}: {row['c']}")
            return "\n".join(lines)

        return "No storage available"

    # ── SQLite methods ──────────────────────────────────────────────

    def _sqlite_store(self, content: str, category: str, tags: str, importance: float, expanded_keywords: str, force_sensitive: bool = False) -> str:
        from datetime import datetime, timezone

        assert self.sqlite_conn is not None
        now = datetime.now(timezone.utc).isoformat()
        is_sensitive = 1 if force_sensitive else 0
        cursor = self.sqlite_conn.cursor()
        cursor.execute(
            "INSERT INTO memories (content, category, tags, expanded_keywords, importance, is_sensitive, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (content, category, tags, expanded_keywords, importance, is_sensitive, now, now),
        )
        self.sqlite_conn.commit()
        return f"Stored memory #{cursor.lastrowid} in category '{category}' with importance {importance:.1f}"

    def _sqlite_recall(self, context: str, expanded_query: str, category: str | None, sort_by: str, limit: int) -> str:
        assert self.sqlite_conn is not None
        all_terms = f"{context} {expanded_query}".strip()
        words = [w.replace(chr(34), "") for w in all_terms.split() if w]
        and_query = " AND ".join(f'"{w}"' for w in words)
        or_query = " OR ".join(f'"{w}"' for w in words)

        # Hybrid scoring: blend BM25 relevance with importance
        # bm25() returns negative values (lower = better match), so negate it
        order = (
            "(-bm25(memories_fts) * 0.7 + m.importance * 0.3) DESC"
            if sort_by == "relevance"
            else "(-bm25(memories_fts) * 0.4 + m.importance * 0.6) DESC"
        )

        base_select = (
            "SELECT m.id, m.content, m.category, m.tags, m.importance, m.created_at "
            "FROM memories m JOIN memories_fts fts ON m.id = fts.rowid "
        )
        cursor = self.sqlite_conn.cursor()
        rows: list[Any] = []
        try:
            # Try AND first for precise matches, fall back to OR for broader results
            cat_filter = "AND m.category = ?" if category else ""
            for fts_query in (and_query, or_query):
                params = [fts_query, category, limit] if category else [fts_query, limit]
                cursor.execute(
                    f"{base_select}WHERE memories_fts MATCH ? {cat_filter} ORDER BY {order} LIMIT ?",
                    tuple(p for p in params if p is not None),
                )
                rows = cursor.fetchall()
                if rows:
                    break
        except sqlite3.OperationalError:
            like = f"%{context}%"
            if category:
                cursor.execute(
                    "SELECT id, content, category, tags, importance, created_at FROM memories "
                    "WHERE (content LIKE ? OR tags LIKE ?) AND category = ? ORDER BY importance DESC LIMIT ?",
                    (like, like, category, limit),
                )
            else:
                cursor.execute(
                    "SELECT id, content, category, tags, importance, created_at FROM memories "
                    "WHERE content LIKE ? OR tags LIKE ? ORDER BY importance DESC LIMIT ?",
                    (like, like, limit),
                )
            rows = cursor.fetchall()

        if not rows:
            return f"No memories found matching: {context}"

        results = []
        for row in rows:
            results.append(
                f"#{row['id']} [{row['category']}] (importance: {row['importance']:.1f}) {row['content']}"
                f"\n  Tags: {row['tags'] or 'none'} | Stored: {row['created_at']}"
            )
        return (
            f"Found {len(rows)} memories (by {'relevance' if sort_by == 'relevance' else 'importance'}):\n\n"
            + "\n\n".join(results)
        )

    def _sqlite_list(self, category: str | None, limit: int) -> str:
        assert self.sqlite_conn is not None
        cursor = self.sqlite_conn.cursor()
        if category:
            cursor.execute(
                "SELECT id, content, category, tags, importance, created_at FROM memories "
                "WHERE category = ? ORDER BY created_at DESC LIMIT ?",
                (category, limit),
            )
        else:
            cursor.execute(
                "SELECT id, content, category, tags, importance, created_at FROM memories "
                "ORDER BY created_at DESC LIMIT ?",
                (limit,),
            )
        rows = cursor.fetchall()
        if not rows:
            return f"No memories in category '{category}'" if category else "No memories stored yet"

        results = []
        for row in rows:
            results.append(
                f"#{row['id']} [{row['category']}] {row['content']}"
                f"\n  Importance: {row['importance']:.1f} | Tags: {row['tags'] or 'none'} | Stored: {row['created_at']}"
            )
        header = "Recent memories" + (f" in '{category}'" if category else "")
        return header + f" ({len(rows)} shown):\n\n" + "\n\n".join(results)

    def _sqlite_delete(self, memory_id: int) -> str:
        assert self.sqlite_conn is not None
        cursor = self.sqlite_conn.cursor()
        cursor.execute("SELECT id, content FROM memories WHERE id = ?", (memory_id,))
        row = cursor.fetchone()
        if not row:
            return f"Memory #{memory_id} not found"
        preview = row["content"][:50]
        cursor.execute("DELETE FROM memories WHERE id = ?", (memory_id,))
        self.sqlite_conn.commit()
        return f"Deleted memory #{memory_id}: {preview}..."

    def _sqlite_secret_get(self, memory_id: int) -> str:
        assert self.sqlite_conn is not None
        cursor = self.sqlite_conn.cursor()
        cursor.execute(
            "SELECT id, content, category, is_sensitive FROM memories WHERE id = ?",
            (memory_id,),
        )
        row = cursor.fetchone()
        if not row:
            return f"Memory #{memory_id} not found"
        if not row["is_sensitive"]:
            return f"Memory #{memory_id} is not marked as sensitive"
        return f"#{row['id']} [{row['category']}] {row['content']}"

    # ── MCP protocol ─────────────────────────────────────────────────

    def handle_initialize(self, params: dict[str, Any]) -> dict[str, Any]:
        return {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {"tools": {}},
            "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
        }

    def handle_tools_list(self, params: dict[str, Any]) -> dict[str, Any]:
        return {"tools": TOOLS}

    def handle_tools_call(self, params: dict[str, Any]) -> dict[str, Any]:
        tool_name: str = params.get("name", "")
        arguments: dict[str, Any] = params.get("arguments", {})
        try:
            handler = {
                "memory_store": self.memory_store,
                "memory_recall": self.memory_recall,
                "memory_list": self.memory_list,
                "memory_delete": self.memory_delete,
                "secret_get": self.secret_get,
                "memory_count": self.memory_count,
            }.get(tool_name)
            if handler is None:
                return {"content": [{"type": "text", "text": f"Unknown tool: {tool_name}"}], "isError": True}
            result = handler(arguments)
            return {"content": [{"type": "text", "text": result}]}
        except Exception as e:
            return {"content": [{"type": "text", "text": f"Error: {e!s}"}], "isError": True}

    def process_message(self, message: dict[str, Any]) -> dict[str, Any] | None:
        method = message.get("method")
        params = message.get("params", {})
        msg_id = message.get("id")
        if msg_id is None:
            return None
        result = None
        error = None
        try:
            if method == "initialize":
                result = self.handle_initialize(params)
            elif method == "tools/list":
                result = self.handle_tools_list(params)
            elif method == "tools/call":
                result = self.handle_tools_call(params)
            else:
                error = {"code": -32601, "message": f"Method not found: {method}"}
        except Exception as e:
            error = {"code": -32603, "message": str(e)}
        response: dict[str, Any] = {"jsonrpc": "2.0", "id": msg_id}
        if error:
            response["error"] = error
        else:
            response["result"] = result
        return response

    def run(self) -> None:
        try:
            for line in sys.stdin:
                line = line.strip()
                if not line or line.startswith("Content-Length:"):
                    continue
                try:
                    message = json.loads(line)
                except json.JSONDecodeError:
                    continue
                response = self.process_message(message)
                if response is not None:
                    print(json.dumps(response), flush=True)
        finally:
            if self.sync_engine:
                self.sync_engine.stop()


def main() -> None:
    # Suppress all stderr output — MCP clients (e.g. Claude Code) may treat
    # any stderr as a fatal error and refuse to load the server.
    sys.stderr = open(os.devnull, "w")
    logging.disable(logging.CRITICAL)

    server = MemoryServer()
    server.run()


if __name__ == "__main__":
    main()
