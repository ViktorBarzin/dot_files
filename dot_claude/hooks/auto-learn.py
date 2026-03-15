#!/usr/bin/env python3
"""
Stop hook (async): automatic learning extraction via haiku-as-judge.

After each Claude response, reads the recent conversation window and uses
haiku to detect learnings worth persisting:
  - User corrections, preferences, decisions, facts (original scope)
  - Debugging insights: error → root cause → fix mappings
  - Architectural patterns and workarounds discovered during work
  - Service/tool-specific operational knowledge

Features:
  - Multi-turn context window (last 5 exchanges by default)
  - State tracking to avoid duplicate extraction
  - Writes to memory API/SQLite AND auto-memory markdown files
  - Throttled deep extraction: full window every ~5 turns, single-turn otherwise

Runs with async: true — does NOT block the user.
"""

import hashlib
import io
import json
import logging
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

logger = logging.getLogger(__name__)

API_BASE_URL = os.environ.get("MEMORY_API_URL") or os.environ.get("CLAUDE_MEMORY_API_URL", "")
API_KEY = os.environ.get("MEMORY_API_KEY") or os.environ.get("CLAUDE_MEMORY_API_KEY", "")

# How many turns between deep (multi-turn) extractions
DEEP_EXTRACTION_INTERVAL = 5
# Max exchanges to include in deep extraction
DEEP_WINDOW_SIZE = 5
# Max chars per message in the context window
MAX_MSG_CHARS = 3000
# State directory
STATE_DIR = Path.home() / ".claude" / "auto-learn-state"

SINGLE_TURN_PROMPT = """You are a memory extraction judge. Analyze this single exchange between a user and an AI assistant.

USER MESSAGE:
{user_message}

ASSISTANT RESPONSE:
{assistant_response}

Your job: determine if any of these learning events occurred:
1. USER CORRECTION — user corrected the assistant's mistake or misunderstanding
2. PREFERENCE — user stated a preference, habit, or "I like/prefer/want" statement
3. DECISION — a decision was reached about how to do something
4. FACT — user shared a durable fact about themselves, their team, tools, or environment

If ANY learning event occurred, return JSON:
{{"events": [{{"type": "correction|preference|decision|fact", "content": "concise fact to remember (one sentence)", "importance": 0.7, "tags": "comma,separated,tags", "expanded_keywords": "space-separated semantically related search terms for recall (minimum 5 words)", "supersedes": null}}]}}

If NO learning event occurred, return:
{{"events": []}}

Rules:
- Only extract DURABLE facts, not transient task details ("fix this file", "run tests")
- Corrections are highest value (0.8-0.9)
- Be conservative — false negatives are better than false positives
- "supersedes" should be a search query to find the old outdated memory, or null
- Return ONLY valid JSON, no other text"""

DEEP_EXTRACTION_PROMPT = """You are a knowledge extraction system. Analyze this multi-turn conversation between a user and an AI assistant working on software engineering tasks.

CONVERSATION (last {n_exchanges} exchanges):
{conversation}

Extract any DURABLE knowledge worth remembering across sessions. Look for:

1. **CORRECTIONS** — user corrected a mistake or misunderstanding (importance: 0.8-0.9)
2. **PREFERENCES** — user stated how they like things done (importance: 0.7-0.8)
3. **DECISIONS** — architectural or design decisions reached (importance: 0.7-0.8)
4. **FACTS** — durable facts about user, team, tools, environment (importance: 0.6-0.8)
5. **DEBUGGING INSIGHTS** — error → root cause → fix patterns that would help next time (importance: 0.7-0.9)
6. **WORKAROUNDS** — things that didn't work and what did instead (importance: 0.7-0.8)
7. **OPERATIONAL KNOWLEDGE** — service-specific learnings, config gotchas, resource requirements (importance: 0.7-0.8)

Return JSON:
{{"events": [{{"type": "correction|preference|decision|fact|debugging|workaround|operational", "content": "concise knowledge to remember (1-3 sentences max)", "importance": 0.7, "tags": "comma,separated,relevant,tags", "expanded_keywords": "space-separated semantically related search terms for recall (minimum 5 words)", "supersedes": null}}]}}

If NO durable knowledge was found, return:
{{"events": []}}

Rules:
- Only extract DURABLE knowledge, not transient task context ("reading file X", "running command Y")
- Don't extract things that are obvious from the codebase (file paths, function names)
- DO extract: "X doesn't work because Y — use Z instead", "service A needs B config", "always do X before Y"
- Merge related learnings into single events rather than splitting into tiny fragments
- If a debugging session revealed the root cause of an issue, capture the error→cause→fix chain
- "supersedes" should be a search query to find an old outdated memory this replaces, or null
- Maximum 5 events per extraction — prioritize by importance
- Return ONLY valid JSON, no other text"""


def _get_state_path(session_id: str) -> Path:
    """Get state file path for this session."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    return STATE_DIR / f"{session_id}.json"


def _load_state(session_id: str) -> dict:
    """Load extraction state for this session."""
    path = _get_state_path(session_id)
    if path.exists():
        try:
            return json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            pass
    return {"turn_count": 0, "extracted_hashes": [], "last_deep_turn": 0}


def _save_state(session_id: str, state: dict) -> None:
    """Save extraction state for this session."""
    path = _get_state_path(session_id)
    try:
        path.write_text(json.dumps(state))
    except OSError:
        pass


def _cleanup_old_state() -> None:
    """Remove state files older than 24 hours."""
    if not STATE_DIR.exists():
        return
    now = datetime.now().timestamp()
    try:
        for f in STATE_DIR.iterdir():
            if f.suffix == ".json" and (now - f.stat().st_mtime) > 86400:
                f.unlink(missing_ok=True)
    except OSError:
        pass


def _content_hash(content: str) -> str:
    """Hash content for deduplication."""
    return hashlib.sha256(content.encode()).hexdigest()[:16]


def _parse_transcript(transcript_path: str, max_exchanges: int = 1) -> list[dict]:
    """
    Parse the transcript and return the last N exchanges as
    [{"role": "user", "content": "..."}, {"role": "assistant", "content": "..."}, ...]
    """
    try:
        MAX_TAIL_BYTES = max_exchanges * 100_000  # ~100KB per exchange should be plenty
        with open(transcript_path, "rb") as f:
            f.seek(0, io.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - MAX_TAIL_BYTES))
            tail = f.read().decode("utf-8", errors="replace")
        lines = tail.split("\n")
    except Exception:
        return []

    entries = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        # Transcript format: role can be at top level or nested in message
        msg = entry.get("message", entry)
        role = msg.get("role", "") or entry.get("type", "")
        if role not in ("user", "assistant"):
            continue
        content = msg.get("content", "")
        if isinstance(content, list):
            content = " ".join(
                b.get("text", "") for b in content
                if isinstance(b, dict) and b.get("type") == "text"
            )
        content = str(content)[:MAX_MSG_CHARS]
        if content.strip():
            entries.append({"role": role, "content": content})

    # Extract the last N exchanges (user+assistant pairs)
    # Walk backwards to find pairs
    exchanges = []
    i = len(entries) - 1
    while i >= 0 and len(exchanges) < max_exchanges * 2:
        exchanges.insert(0, entries[i])
        i -= 1

    # Trim to last N complete exchanges
    result = []
    pair_count = 0
    for entry in reversed(exchanges):
        result.insert(0, entry)
        if entry["role"] == "user":
            pair_count += 1
        if pair_count >= max_exchanges:
            break

    return result


def _api_request(method: str, path: str, body: dict | None = None) -> dict:
    url = f"{API_BASE_URL}{path}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(
        url, data=data, method=method,
        headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode())


def _store_via_api(content, category, tags, importance, expanded_keywords):
    _api_request("POST", "/api/memories", {
        "content": content, "category": category, "tags": tags,
        "expanded_keywords": expanded_keywords, "importance": importance,
    })


def _store_via_sqlite(content, category, tags, importance, expanded_keywords):
    import sqlite3

    memory_home = os.environ.get("MEMORY_HOME", os.path.expanduser("~/.claude/claude-memory"))
    db_path = os.path.join(memory_home, "memory", "memory.db")

    if not os.path.exists(db_path):
        legacy_db = os.path.join(os.path.expanduser("~/.claude/metaclaw"), "memory", "memory.db")
        if os.path.exists(legacy_db):
            db_path = legacy_db

    conn = sqlite3.connect(db_path, timeout=10.0)
    conn.execute("PRAGMA journal_mode=WAL")
    now = datetime.now(timezone.utc).isoformat()
    conn.execute(
        "INSERT INTO memories (content, category, tags, importance, expanded_keywords, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        (content, category, tags, importance, expanded_keywords, now, now),
    )
    conn.commit()
    conn.close()


def _append_to_auto_memory(content: str, event_type: str) -> None:
    """Append a learning to the auto-memory markdown file for the current project."""
    # Find the project memory directory based on CWD
    cwd = os.getcwd()
    # Claude Code stores project memory at ~/.claude/projects/<escaped-path>/memory/
    escaped = cwd.replace("/", "-")
    if escaped.startswith("-"):
        escaped = escaped[1:]  # Remove leading dash
    memory_dir = Path.home() / ".claude" / "projects" / f"-{escaped}" / "memory"

    if not memory_dir.exists():
        # Try without the leading dash
        memory_dir = Path.home() / ".claude" / "projects" / escaped / "memory"

    if not memory_dir.exists():
        return

    auto_learn_file = memory_dir / "auto-learned.md"
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    header = "# Auto-Learned Knowledge\n\nAutomatically extracted by the auto-learn hook. Review periodically and promote valuable entries to MEMORY.md.\n\n"

    if not auto_learn_file.exists():
        auto_learn_file.write_text(header)

    # Append the new learning
    with open(auto_learn_file, "a") as f:
        f.write(f"- [{now}] **{event_type}**: {content}\n")


def _call_judge(prompt: str) -> list[dict]:
    """Call haiku as judge and return extracted events."""
    try:
        result = subprocess.run(
            ["claude", "-p", prompt, "--model", "haiku"],
            capture_output=True, text=True, timeout=45,
            env={**os.environ, "CLAUDECODE": ""},
        )
        if result.returncode != 0:
            return []
        response_text = result.stdout.strip()
        # Strip markdown code fences if present
        if response_text.startswith("```"):
            lines = response_text.split("\n")
            lines = [l for l in lines if not l.strip().startswith("```")]
            response_text = "\n".join(lines).strip()
        judge_result = json.loads(response_text)
        return judge_result.get("events", [])
    except (subprocess.TimeoutExpired, json.JSONDecodeError, OSError):
        return []


def _format_conversation(entries: list[dict]) -> str:
    """Format conversation entries for the judge prompt."""
    parts = []
    for entry in entries:
        role = "USER" if entry["role"] == "user" else "ASSISTANT"
        parts.append(f"[{role}]: {entry['content']}")
    return "\n\n".join(parts)


def _store_events(events: list[dict], extracted_hashes: list[str]) -> list[str]:
    """Store extracted events, return new hashes."""
    category_map = {
        "correction": "preferences",
        "preference": "preferences",
        "decision": "decisions",
        "fact": "facts",
        "debugging": "decisions",
        "workaround": "decisions",
        "operational": "facts",
    }

    new_hashes = []
    for event in events:
        content = event.get("content", "")
        if not content:
            continue

        # Deduplication: skip if we've already extracted this
        h = _content_hash(content)
        if h in extracted_hashes:
            continue

        event_type = event.get("type", "fact")
        importance = max(0.0, min(1.0, float(event.get("importance", 0.7))))
        category = category_map.get(event_type, "facts")
        tags = event.get("tags", f"auto-learned,{event_type}")
        if "auto-learned" not in tags:
            tags = f"auto-learned,{tags}"
        expanded_keywords = event.get("expanded_keywords", "")

        # Store to memory API or SQLite
        try:
            if API_KEY and API_BASE_URL:
                _store_via_api(content, category, tags, importance, expanded_keywords)
            else:
                _store_via_sqlite(content, category, tags, importance, expanded_keywords)
        except Exception:
            pass

        # Also append to auto-memory markdown
        try:
            _append_to_auto_memory(content, event_type)
        except Exception:
            pass

        new_hashes.append(h)

    return new_hashes


def main() -> None:
    if not shutil.which("claude"):
        return

    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        return

    if isinstance(hook_input, dict) and hook_input.get("stop_hook_active", False):
        return

    transcript_path = ""
    session_id = ""
    if isinstance(hook_input, dict):
        transcript_path = hook_input.get("transcript_path", "")
        session_id = hook_input.get("session_id", "")

    if not transcript_path or not os.path.exists(transcript_path):
        return

    # Derive session ID from transcript path if not provided
    if not session_id:
        session_id = hashlib.sha256(transcript_path.encode()).hexdigest()[:16]

    # Load state
    state = _load_state(session_id)
    state["turn_count"] = state.get("turn_count", 0) + 1
    turn_count = state["turn_count"]
    last_deep_turn = state.get("last_deep_turn", 0)
    extracted_hashes = state.get("extracted_hashes", [])

    # Decide: single-turn (cheap) or deep (multi-turn) extraction
    turns_since_deep = turn_count - last_deep_turn
    do_deep = turns_since_deep >= DEEP_EXTRACTION_INTERVAL

    if do_deep:
        # Deep extraction: read last N exchanges
        entries = _parse_transcript(transcript_path, max_exchanges=DEEP_WINDOW_SIZE)
        if len(entries) < 2:
            _save_state(session_id, state)
            return

        # Count actual exchanges
        n_exchanges = sum(1 for e in entries if e["role"] == "user")
        conversation = _format_conversation(entries)
        prompt = DEEP_EXTRACTION_PROMPT.format(
            n_exchanges=n_exchanges,
            conversation=conversation[:8000],  # Cap total context
        )
        events = _call_judge(prompt)
        state["last_deep_turn"] = turn_count
    else:
        # Single-turn extraction: just the last exchange
        entries = _parse_transcript(transcript_path, max_exchanges=1)
        if len(entries) < 2:
            _save_state(session_id, state)
            return

        user_msg = ""
        assistant_msg = ""
        for entry in entries:
            if entry["role"] == "user":
                user_msg = entry["content"]
            elif entry["role"] == "assistant":
                assistant_msg = entry["content"]

        if not user_msg or len(user_msg.strip()) < 10:
            _save_state(session_id, state)
            return

        prompt = SINGLE_TURN_PROMPT.format(
            user_message=user_msg,
            assistant_response=assistant_msg[:2000],
        )
        events = _call_judge(prompt)

    # Store events
    if events:
        new_hashes = _store_events(events, extracted_hashes)
        extracted_hashes.extend(new_hashes)
        # Keep hash list bounded
        if len(extracted_hashes) > 200:
            extracted_hashes = extracted_hashes[-200:]
        state["extracted_hashes"] = extracted_hashes

    _save_state(session_id, state)

    # Periodic cleanup of old state files
    if turn_count % 20 == 0:
        _cleanup_old_state()


if __name__ == "__main__":
    main()
