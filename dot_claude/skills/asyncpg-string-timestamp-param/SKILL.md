---
name: asyncpg-string-timestamp-param
description: |
  Fix for asyncpg.exceptions.DataError "invalid input for query argument: expected a
  datetime.date or datetime.datetime instance, got 'str'" when passing ISO timestamp
  strings to TIMESTAMPTZ query parameters. Use when: (1) asyncpg query fails with
  DataError on a timestamp parameter, (2) the same query works in psql or SQLAlchemy
  because PostgreSQL accepts string casts, (3) using FastAPI query params or any string
  source for timestamp values passed to asyncpg conn.fetch/fetchrow/execute. Root cause:
  asyncpg uses binary protocol with strict Python type binding, unlike text-based SQL
  clients. Also covers the URL-encoding gotcha where + in +00:00 becomes a space in
  query parameters.
author: Claude Code
version: 1.0.0
date: 2026-03-14
---

# asyncpg: String Timestamp Parameter Rejection

## Problem

asyncpg rejects ISO timestamp strings (e.g., `"2026-03-14T10:00:00+00:00"`) when
passed as query arguments for `TIMESTAMPTZ` columns, even though PostgreSQL itself
accepts them in raw SQL via implicit casting.

## Context / Trigger Conditions

- Error: `asyncpg.exceptions.DataError: invalid input for query argument $N: '<iso_string>' (expected a datetime.date or datetime.datetime instance, got 'str')`
- Using asyncpg directly (not through SQLAlchemy ORM which handles conversion)
- Passing timestamps from FastAPI query params, HTTP headers, or JSON request bodies
- The query works fine in psql, pgAdmin, or any text-protocol client
- Common with `WHERE updated_at > $1::timestamptz` or similar patterns
- Even `$1::timestamptz` cast in the SQL doesn't help — asyncpg validates the Python type before sending

## Solution

Parse the ISO string to a `datetime` object before passing to asyncpg:

```python
from datetime import datetime

# Before (fails):
await conn.fetch("SELECT * FROM t WHERE updated_at > $1", since_str)

# After (works):
since_dt = datetime.fromisoformat(since_str)
await conn.fetch("SELECT * FROM t WHERE updated_at > $1", since_dt)
```

Remove the `::timestamptz` cast from the SQL — it's unnecessary when passing a proper
`datetime` object, and misleading since it suggests the cast would handle string conversion.

### URL-Encoding Gotcha

When accepting timestamps via URL query parameters (e.g., `?since=2026-03-14T10:00:00+00:00`),
the `+` sign is URL-decoded to a space, producing `2026-03-14T10:00:00 00:00` which is
an invalid ISO format.

**Solutions (pick one):**
1. Use `Z` suffix instead of `+00:00` for UTC: `?since=2026-03-14T10:00:00Z`
2. URL-encode the `+` as `%2B`: `?since=2026-03-14T10:00:00%2B00:00`
3. Accept both formats in the API:
   ```python
   since_str = since_str.replace(" ", "+")  # Fix URL-decoded +
   since_dt = datetime.fromisoformat(since_str)
   ```

## Verification

```python
# Test that the parameter is accepted
from datetime import datetime, timezone
dt = datetime.fromisoformat("2026-03-14T10:00:00Z")
assert isinstance(dt, datetime)
# This should now work without DataError
rows = await conn.fetch("SELECT * FROM memories WHERE updated_at > $1", dt)
```

## Example

FastAPI endpoint accepting a timestamp query parameter:

```python
from datetime import datetime
from typing import Optional

@app.get("/api/items/sync")
async def sync_items(since: Optional[str] = None):
    pool = await get_pool()
    async with pool.acquire() as conn:
        if since:
            since_dt = datetime.fromisoformat(since)
            rows = await conn.fetch(
                "SELECT * FROM items WHERE updated_at > $1 ORDER BY updated_at",
                since_dt,
            )
        else:
            rows = await conn.fetch("SELECT * FROM items ORDER BY updated_at")
    return {"items": rows}
```

## Notes

- This only affects asyncpg's binary protocol. SQLAlchemy ORM, psycopg2, and psql all
  use text protocol where PostgreSQL handles string-to-timestamp conversion automatically.
- `datetime.fromisoformat()` was significantly improved in Python 3.11+ to handle more
  ISO 8601 formats, including `Z` suffix. On Python < 3.11, `Z` must be replaced with
  `+00:00` manually.
- asyncpg also rejects strings for `DATE`, `TIME`, `INTERVAL`, and other temporal types.
  Always pass proper Python objects (`datetime.date`, `datetime.time`, `datetime.timedelta`).

See also: `asyncpg-sqlalchemy-temp-table` (different asyncpg gotcha: temp tables in autocommit mode)
