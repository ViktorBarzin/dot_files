---
name: remote
description: Execute commands on the remote dev VM (10.0.10.10)
---

# Remote Command Execution Skill

Execute commands on the remote host via the remote-exec daemon.

## Prerequisites

The daemon must be running in a terminal (outside sandbox):
```bash
~/.claude/remote-exec.sh daemon
```

## Instructions

When the user invokes `/remote <command>`:

1. Generate a unique filename: `cmd-$(date +%s%N).txt`
2. Write the command to `~/.claude/remote-commands/<filename>`
3. Wait for result in `~/.claude/remote-results/<filename>`
4. Display the result (ends with `---` and `EXIT_CODE: <n>`)

## Usage Examples

```bash
/remote pytest tests/ -v
/remote python main.py dump-listings
/remote "cd frontend && npm run build"
```

## Parallel Execution

For parallel commands, first line should be `--parallel`:
```
--parallel
pytest tests/unit/
pytest tests/integration/
```

## Configuration

Default host/workdir is built into the script. To change:
```bash
~/.claude/remote-exec.sh config <host> <workdir>
```

## Execution Steps

1. Write command to `~/.claude/remote-commands/cmd-<timestamp>.txt`
2. Poll `~/.claude/remote-results/` every 0.5s (timeout: 120s)
3. Once EXIT_CODE appears, display output
4. Report success/failure based on exit code
