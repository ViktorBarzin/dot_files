---
name: parallel-worktree-builds
description: |
  Build large projects faster using parallel subagent worktrees in Claude Code.
  Use when: (1) implementing a multi-service or multi-component project,
  (2) multiple tasks can be worked on independently (non-overlapping files),
  (3) you want to parallelize code generation across isolated git worktrees.
  Covers: spawning parallel Task agents with worktree isolation, merging
  branches back to master, resolving conflicts when agents create overlapping
  files, and the tradeoff between TeamCreate agent teams vs direct Task subagents.
author: Claude Code
version: 1.0.0
date: 2026-02-22
---

# Parallel Worktree Builds

## Problem
Large projects with multiple independent components (microservices, shared libraries,
frontend + backend) take too long to build sequentially. Claude Code can parallelize
by spawning multiple subagents, but they need isolated workspaces to avoid conflicts.

## Context / Trigger Conditions
- Building a project with 3+ independent modules or services
- Implementation plan has tasks that don't depend on each other
- You want to maximize throughput by running agents in parallel
- Each agent needs to create files, run tests, and commit independently

## Solution

### Pattern: Parallel Task Agents with Worktree Isolation

**1. Identify parallelizable tasks.** Tasks are parallel-safe when they create/modify
non-overlapping files. Example: broker abstraction vs news fetcher vs sentiment analyzer.

**2. Spawn agents in parallel with `isolation: "worktree"`:**

```
// Send a SINGLE message with multiple Task tool calls
Task(
  description: "Build component A",
  isolation: "worktree",
  mode: "bypassPermissions",
  subagent_type: "general-purpose",
  prompt: "... detailed instructions ..."
)
Task(
  description: "Build component B",
  isolation: "worktree",
  mode: "bypassPermissions",
  subagent_type: "general-purpose",
  prompt: "... detailed instructions ..."
)
```

**3. Each agent returns:** agentId, worktreePath, worktreeBranch (e.g., `worktree-agent-af48b960`)

**4. Merge branches sequentially:**

```bash
git merge worktree-agent-XXXX --no-edit   # first branch (fast-forward)
git merge worktree-agent-YYYY --no-edit   # second branch (merge commit)
```

**5. Handle conflicts.** When two agents create the same files (e.g., both created
`shared/strategies/`), resolve with:

```bash
git checkout --ours shared/strategies/     # keep the dedicated agent's version
git add shared/strategies/
git commit --no-edit
```

**6. Clean up worktrees and branches:**

```bash
git worktree remove /path/to/worktree --force
git branch -d worktree-agent-XXXX
```

**7. Verify after merge:**

```bash
pip install -e ".[dev]"
python -m pytest tests/ -v
```

### Sprint Structure for Large Projects

Organize work into sprints with clear boundaries:

1. **Sprint = set of parallel tasks** with defined acceptance criteria
2. **Merge + verify** after each sprint before starting the next
3. **Dependency order**: foundation → services → API → frontend → integration
4. **Parallelism within sprints**: independent services build simultaneously

### Key Rules

- **Give agents FULL context** in the prompt. Include exact file paths, schemas to use,
  test expectations, and commit messages. Agents in worktrees can't see your conversation.
- **Include dependency code references** in prompts (e.g., "Read `shared/schemas/trading.py`
  for the TradeSignal schema to use").
- **One agent per non-overlapping file set.** If two agents might create the same file,
  assign it to only one agent or accept you'll resolve conflicts.
- **Always run full test suite after merge** to catch integration issues.
- **Install deps in the main repo** after merge if agents added new dependencies.

## Verification
- All worktree branches merge cleanly (or conflicts resolve easily)
- Full test suite passes after merge
- No duplicate or conflicting file contents

## Example

Sprint 2 of a trading bot — 3 independent services built in parallel:

| Agent | Task | Files | Tests |
|-------|------|-------|-------|
| broker-builder | Broker abstraction + Alpaca | shared/broker/* | 18 |
| news-builder | News fetcher (RSS + Reddit) | services/news_fetcher/* | 10 |
| sentiment-builder | Sentiment analyzer | services/sentiment_analyzer/* | 19 |

All 3 ran simultaneously in ~5 minutes. Merged sequentially. 122 total tests passed.

## Notes

### Agent Teams (TeamCreate) vs Direct Subagents (Task)

**Prefer direct Task subagents over TeamCreate for code generation:**

- TeamCreate agents require explicit message-based coordination and often go idle
  waiting for instructions, requiring multiple nudges
- Direct Task subagents with `isolation: "worktree"` run autonomously with the full
  prompt and return results directly
- Teams are better for long-running coordination tasks; subagents are better for
  well-defined build tasks

### Conflict Prevention

To minimize merge conflicts:
- Don't have two agents modify `pyproject.toml` — let one agent do it, or accept
  the auto-merge (usually works for different sections)
- Don't have two agents create the same package `__init__.py` files
- If an agent needs shared code that another agent is creating, include the code
  directly in the prompt rather than expecting them to read from each other

### pyproject.toml Conflicts

When multiple agents modify `pyproject.toml` (e.g., adding package discovery paths),
git's auto-merge usually handles it. If not, manually combine the changes.
