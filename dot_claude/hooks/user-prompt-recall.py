#!/usr/bin/env python3
"""
UserPromptSubmit hook: nudge Claude to check memories before responding.

Instead of searching SQLite directly (which can't generate expanded_query),
this hook injects a prompt instruction telling Claude to call memory_recall
with proper expanded_query. The model handles the semantic expansion.

Skips injection for short prompts, code blocks, and tool outputs.
"""

import json
import os
import sys


RECALL_INSTRUCTION = (
    "MANDATORY: Call memory_recall with context and expanded_query BEFORE responding "
    "to this message. This is a BLOCKING REQUIREMENT — do NOT answer, summarize, or "
    "take action until you have checked stored memories. The user's preferences, past "
    "corrections, and decisions are stored there and MUST inform your response.\n\n"
    "ONLY EXCEPTION: Skip memory_recall if the message is a direct technical command "
    "with zero personal context (e.g., 'fix this lint error', 'run tests', 'read file X'). "
    "Questions, discussions, opinions, design tasks, and anything involving preferences "
    "are NOT exceptions — check memory for those.\n\n"
    "NEVER mention the memory check to the user — not when you call it, not when you skip it, "
    "not when it returns nothing. It should be completely invisible. "
    "If it returns results, incorporate them naturally into your response."
)


def main() -> None:
    # Read hook input from stdin
    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        return

    # Extract user's prompt
    prompt = ""
    if isinstance(hook_input, dict):
        prompt = hook_input.get("prompt", "")
        if not prompt:
            prompt = hook_input.get("user_prompt", "")
            if not prompt:
                content = hook_input.get("content", "")
                if isinstance(content, str):
                    prompt = content

    if not prompt or len(prompt.strip()) < 10:
        return  # Too short to warrant memory check

    # Skip obviously irrelevant prompts
    stripped = prompt.strip()
    if (
        stripped.startswith("```")
        or stripped.startswith("{")
        or stripped.startswith("<")
    ):
        return

    # Skip if memory DB doesn't exist (no memories to recall)
    memory_home = os.environ.get(
        "MEMORY_HOME", os.path.expanduser("~/.claude/claude-memory")
    )
    db_path = os.path.join(memory_home, "memory", "memory.db")

    # Also check legacy path for migration
    legacy_home = os.path.expanduser("~/.claude/metaclaw")
    legacy_db = os.path.join(legacy_home, "memory", "memory.db")

    if not os.path.exists(db_path) and not os.path.exists(legacy_db):
        return

    # Inject the recall instruction
    output = json.dumps(
        {
            "hookSpecificOutput": {
                "hookEventName": "UserPromptSubmit",
                "additionalContext": RECALL_INSTRUCTION,
            }
        }
    )
    print(output)


if __name__ == "__main__":
    main()
