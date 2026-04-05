# Claude Memory

## Instructions
- **Memory MCP is the ONLY memory system.** All memories (facts, preferences, decisions, project context) MUST be stored and recalled via the `memory_store` / `memory_recall` MCP tools. Do NOT use the file-based auto-memory system (`~/.claude/projects/*/memory/`).
- **"remember X"**: Store via `memory_store` MCP tool immediately. For project-specific static info (commands, architecture), also update the project's `.claude/CLAUDE.md`.
- **Recalling**: Always use `memory_recall` MCP tool to search for relevant context before responding to non-trivial requests.
- **Skills/agents**: Create in `~/.claude/skills/` or `~/.claude/agents/`, sync via chezmoi, commit to dotfiles repo.

## Preferences

### Chezmoi Sync
When making changes to dotfiles (including Claude files in `~/.claude/`), sync with chezmoi **only if it is installed** (`command -v chezmoi`):
1. Sync with chezmoi:
   - `chezmoi add <file>` for new files
   - `chezmoi re-add <file>` for updated files
2. Commit the changes in the chezmoi source directory:
   - `cd $(chezmoi source-path) && git add -A && git commit -m "<descriptive message>"`
If chezmoi is not installed, skip the sync steps and just make the changes directly.

### Claude Plugins
When installing new Claude plugins or marketplaces, update these files:
- `~/.local/bin/sync-dotfiles-remote.sh` - add new marketplace/plugin install commands
- `~/.local/share/chezmoi/run_once_after_install-claude-plugins.sh` - add to chezmoi run_once script
Then sync and commit both to chezmoi.

### Cluster Health Checks
- **Source of truth**: `infra/scripts/cluster_healthcheck.sh` — always run this script for cluster healthchecks
- The `cluster-triage` agent and `cluster-health` skill both use this script
- When checking cluster health, prefer spawning the `cluster-triage` agent (which runs the script and investigates FAIL/WARN results) over running the script directly
- Any new health checks must be added to the script, not done ad-hoc

### Skills/Agents Sync
All Claude Code skills, agents, and hooks live in the **dotfiles repo** (`~/.local/share/chezmoi/dot_claude/`), synced via chezmoi.
- **Add new skill/agent**: Create in `~/.claude/skills/` or `~/.claude/agents/`, then `chezmoi add ~/.claude/skills/<name>` and commit
- **OpenClaw**: Init container clones dotfiles repo and runs `executable_openclaw-install.sh` on pod start — no manual sync needed
- **After modifying skills/hooks**: `chezmoi re-add ~/.claude/skills && cd $(chezmoi source-path) && git add -A && git commit -m "update skills" && git push`

## Planning Mode Behavior

When in plan mode (system-reminder says "Plan mode is active"), follow this enhanced workflow:

### Interviewing Phase (BEFORE any research)
- **Challenge the goal itself.** Ask "Why?" at least once. Question whether the stated goal is the right goal.
- **Surface assumptions.** What is the user assuming about the problem, the solution, or the constraints?
- **Propose alternatives to the entire approach.** Before researching how to do X, ask whether X is even the right thing to do.
- **Ask about prior art.** Has this been attempted before? Are there existing solutions?
- **Use AskUserQuestion aggressively** — batch 2-4 targeted questions per round.
- **Do NOT proceed to research until the goal is crystal clear and challenged.**
- Minimum: 2 rounds of questions before any subagent research. Exception: truly trivial tasks (single-file edits, typo fixes).

### Research Phase (subagent-heavy)
- **Spawn subagents liberally** — no cap. Use judgment on quantity based on complexity.
- **Research ALL paths**, not just the obvious one. For each viable approach, spawn an agent to investigate.
- For each path, research: implementation complexity, tradeoffs, existing solutions, edge cases, maintenance burden.
- **Always research existing code** in the workspace that might already solve part of the problem.
- **Always research external solutions** (libraries, patterns, prior art) before proposing custom code.
- After research completes, present findings as a comparison table of approaches with clear tradeoffs.

### Gap Elimination Phase (BEFORE writing final plan)
- List every unknown, assumption, and risk explicitly.
- For each unknown: either resolve it via research or ask the user.
- **The plan is not ready until there are zero unresolved unknowns.**
- Ask: "What could go wrong?" and "What am I missing?" before finalizing.

### Complexity Detection (auto-trigger)
For non-trivial tasks (multi-file changes, new features, architectural decisions, anything involving more than ~20 lines of code), automatically engage the full planning workflow above. Skip only for:
- Typo fixes, single-line changes, renames
- Direct "just do it" / "skip planning" instructions from user
