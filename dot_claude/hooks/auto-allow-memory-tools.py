#!/usr/bin/env python3
"""
Auto-allow hook for claude-memory plugin tools.

This PermissionRequest hook automatically allows any tool whose name matches
the claude_memory MCP server pattern to proceed without user confirmation.

Environment variables:
  DEBUG_CLAUDE_MEMORY_HOOKS=1          Enable debug logging to stderr
  DISABLE_CLAUDE_MEMORY_AUTO_APPROVE=1 Disable auto-approve (for debugging)
"""

import json
import os
import re
import sys

DEBUG = os.environ.get("DEBUG_CLAUDE_MEMORY_HOOKS", "").lower() in ("1", "true", "yes")
DISABLED = os.environ.get("DISABLE_CLAUDE_MEMORY_AUTO_APPROVE", "").lower() in (
    "1",
    "true",
    "yes",
)

# Match any tool from this plugin's MCP server, resilient to slug variations
# e.g. mcp__plugin_claude-memory_claude_memory__memory_store
#      mcp__claude_memory__memory_recall
TOOL_PATTERN = re.compile(r"mcp__.*claude_memory__(?:memory_|secret_)")


def debug(msg: str) -> None:
    """Print debug message to stderr if DEBUG is enabled."""
    if DEBUG:
        print(f"[claude-memory] {msg}", file=sys.stderr)


def main() -> None:
    if DISABLED:
        debug("Auto-approve disabled via DISABLE_CLAUDE_MEMORY_AUTO_APPROVE")
        sys.exit(0)

    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(1)

    tool_name = input_data.get("tool_name", "")
    debug(f"Permission request for: {tool_name}")

    if TOOL_PATTERN.search(tool_name):
        debug(f"Auto-allowing: {tool_name}")
        output = {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {
                    "behavior": "allow",
                },
            }
        }
        json.dump(output, sys.stdout)
    else:
        debug(f"Not a claude-memory tool, passing through: {tool_name}")

    sys.exit(0)


if __name__ == "__main__":
    main()
