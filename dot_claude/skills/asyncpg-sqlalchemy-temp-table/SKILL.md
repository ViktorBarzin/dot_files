---
name: asyncpg-sqlalchemy-temp-table
description: |
  Fix for "relation does not exist" errors when using PostgreSQL COPY with temp tables
  via raw asyncpg connections obtained from SQLAlchemy async sessions. Use when:
  (1) CREATE TEMP TABLE ... ON COMMIT DROP followed by COPY fails with "relation does not exist",
  (2) using session.connection().get_raw_connection() to access the asyncpg driver connection,
  (3) temp tables disappear between sequential statements on the same raw connection.
  Root cause: raw asyncpg connections obtained through SQLAlchemy operate in autocommit mode,
  so each statement is its own transaction and ON COMMIT DROP takes effect immediately.
author: Claude Code
version: 1.0.0
date: 2026-02-08
---

# asyncpg + SQLAlchemy: Temp Table Dropped Before COPY

## Problem
When using PostgreSQL's COPY protocol via raw asyncpg connections obtained from SQLAlchemy
async sessions, `CREATE TEMP TABLE ... ON COMMIT DROP` causes the temp table to be dropped
before subsequent statements (like `copy_records_to_table`) can use it.

## Context / Trigger Conditions
- Using SQLAlchemy's `AsyncSession` with `asyncpg` driver
- Accessing the raw asyncpg connection via:
  ```python
  conn = await session.connection()
  raw = await conn.get_raw_connection()
  asyncpg_conn = raw.dbapi_connection.driver_connection
  ```
- Creating a temp table with `ON COMMIT DROP` and then running COPY on it
- Error: `asyncpg.exceptions.UndefinedTableError: relation "_tmp_tablename" does not exist`

## Root Cause
When you extract the raw asyncpg connection from SQLAlchemy, the connection operates in
**autocommit mode** at the asyncpg level. Each `await asyncpg_conn.execute(...)` call is
its own implicit transaction. So:

1. `CREATE TEMP TABLE _tmp_foo (...) ON COMMIT DROP` — creates the table, transaction
   commits, table is dropped
2. `asyncpg_conn.copy_records_to_table("_tmp_foo", ...)` — table doesn't exist anymore

This happens even though SQLAlchemy's session thinks it has a transaction open — the raw
driver connection bypasses SQLAlchemy's transaction management.

## Solution
Replace `ON COMMIT DROP` with manual lifecycle management:

```python
async def _copy_upsert(session, table_name, columns, records, conflict_target=None):
    conn = await session.connection()
    raw = await conn.get_raw_connection()
    asyncpg_conn = raw.dbapi_connection.driver_connection

    tmp = f"_tmp_{table_name}"
    col_list = ", ".join(columns)

    # Drop any leftover temp table, then create without ON COMMIT DROP
    await asyncpg_conn.execute(f"DROP TABLE IF EXISTS {tmp}")
    await asyncpg_conn.execute(
        f"CREATE TEMP TABLE {tmp} (LIKE {table_name} INCLUDING DEFAULTS)"
    )

    # COPY rows into temp table
    await asyncpg_conn.copy_records_to_table(tmp, records=records, columns=columns)

    # Upsert from temp into real table
    conflict = f"ON CONFLICT {conflict_target} DO NOTHING" if conflict_target else "ON CONFLICT DO NOTHING"
    await asyncpg_conn.execute(
        f"INSERT INTO {table_name} ({col_list}) SELECT {col_list} FROM {tmp} {conflict}"
    )

    # Clean up
    await asyncpg_conn.execute(f"DROP TABLE IF EXISTS {tmp}")
```

**Alternative**: Wrap all raw statements in an explicit asyncpg transaction:
```python
async with asyncpg_conn.transaction():
    await asyncpg_conn.execute(f"CREATE TEMP TABLE {tmp} (...) ON COMMIT DROP")
    await asyncpg_conn.copy_records_to_table(tmp, ...)
    await asyncpg_conn.execute(f"INSERT INTO ... SELECT ... FROM {tmp} ...")
```
Note: This may conflict with SQLAlchemy's own transaction if one is already open
(asyncpg will use a savepoint in that case).

## Verification
Run the bulk insert and confirm no `UndefinedTableError`. Check that data appears
in the target table.

## Example
Before (broken):
```python
await asyncpg_conn.execute(
    f"CREATE TEMP TABLE {tmp} (LIKE {table} INCLUDING DEFAULTS) ON COMMIT DROP"
)
# This line fails: relation "_tmp_health_records" does not exist
await asyncpg_conn.copy_records_to_table(tmp, records=rows, columns=cols)
```

After (working):
```python
await asyncpg_conn.execute(f"DROP TABLE IF EXISTS {tmp}")
await asyncpg_conn.execute(f"CREATE TEMP TABLE {tmp} (LIKE {table} INCLUDING DEFAULTS)")
await asyncpg_conn.copy_records_to_table(tmp, records=rows, columns=cols)
await asyncpg_conn.execute(f"INSERT INTO {table} (...) SELECT ... FROM {tmp} ...")
await asyncpg_conn.execute(f"DROP TABLE IF EXISTS {tmp}")
```

## Notes
- This only affects raw asyncpg connections obtained through SQLAlchemy. If you use
  asyncpg directly (without SQLAlchemy), you control the transaction yourself.
- The `DROP TABLE IF EXISTS` before CREATE handles the case where a previous call
  crashed mid-way and left the temp table behind.
- Using `LIKE table INCLUDING DEFAULTS` copies the column types and defaults but not
  indexes or constraints, which is ideal for a staging table.
- Temp tables without `ON COMMIT DROP` persist for the duration of the session (connection),
  not just the transaction. This is fine since we explicitly drop them.
