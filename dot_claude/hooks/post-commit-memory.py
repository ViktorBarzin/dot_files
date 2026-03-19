#!/usr/bin/env python3
"""
PostToolUse hook: after a successful git commit, inject a prompt telling Claude
to review the recent conversation and store meaningful learnings as memories.

Triggers on Bash tool calls where the command contains 'git commit' and the
tool succeeded (exit code 0).
"""

import json
import sys


EXTRACT_INSTRUCTION = (
    "You just completed a git commit. Review the last few rounds of conversation "
    "and extract any meaningful, reusable knowledge that was discovered or confirmed "
    "during this work session. Look for:\n"
    "- Non-obvious debugging insights or root causes\n"
    "- Workarounds for tools/APIs that don't behave as documented\n"
    "- Architecture patterns or conventions confirmed by this work\n"
    "- Operational runbook-worthy procedures\n"
    "- Gotchas that could save time in future sessions\n\n"
    "For each piece of knowledge, call memory_store with appropriate category, "
    "tags, and importance (0.7-0.9). Skip anything already stored or too "
    "session-specific to be useful later. If nothing meaningful was learned "
    "beyond what's already in memory, skip silently.\n\n"
    "Do NOT mention this memory extraction to the user — it should be invisible."
)


def main() -> None:
    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        return

    if not isinstance(hook_input, dict):
        return

    # Check tool name
    tool_name = hook_input.get("tool_name", "")
    if tool_name != "Bash":
        return

    # Check the command contains 'git commit'
    tool_input = hook_input.get("tool_input", {})
    if isinstance(tool_input, dict):
        command = tool_input.get("command", "")
    else:
        return

    if "git commit" not in command:
        return

    # Check the tool succeeded
    tool_output = hook_input.get("tool_output", "")
    if isinstance(tool_output, dict):
        exit_code = tool_output.get("exit_code", -1)
        stdout = tool_output.get("stdout", "")
    elif isinstance(tool_output, str):
        # If output is a string, check for commit success indicators
        stdout = tool_output
        exit_code = 0 if ("master" in stdout or "main" in stdout) else -1
    else:
        return

    if exit_code != 0:
        return

    # Verify it actually committed (not a dry run or failed hook)
    if "nothing to commit" in stdout or "no changes added" in stdout:
        return

    output = json.dumps(
        {
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "additionalContext": EXTRACT_INSTRUCTION,
            }
        }
    )
    print(output)


if __name__ == "__main__":
    main()
