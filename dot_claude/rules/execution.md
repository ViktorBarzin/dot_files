# Execution (applies to ALL agents)

Once a plan is approved (via ExitPlanMode or explicit user go-ahead), execute end-to-end. This file governs what happens AFTER planning — see `planning.md` for the interview/research/challenger flow that precedes it.

## 1. Default posture — run through, no mid-task gates

**Keep working until the user's request is satisfied.**

- Don't stop after research, after a single commit, after each "phase" or "batch" — keep going.
- No "Should I proceed with X?" / "Want me to continue?" prompts between steps of an approved plan.
- No mid-task checkpoints or batch approvals. The user interrupts if something drifts.
- Course-correct on user interruption, not by polling.

Stopping is the exception that needs a reason. The ONLY reasons to stop mid-execution are listed in §2.

## 2. When to stop and ask (the ONLY ASK FIRST list)

Pause and surface to the user (or, if you're a subagent, to the session that spawned you) for:

- **Destructive ops** — force-push, `git reset --hard`, `rm -rf`, dropping DB tables, killing processes the user didn't start
- **Schema / public API changes** — REST, GraphQL, gRPC, DB schema
- **Deleting tested code** — anything that has tests covering it
- **Interface / contract changes** that affect other teams
- **Live network devices** — routers, switches, firewalls (confirmed preference)
- **Scope changes** — work beyond the approved plan
- **New genuine ambiguity** discovered mid-execution that the research didn't resolve
- **Configuration changes with external impact** — credentials, DNS, firewall rules, production configs

Anything NOT on this list → just do it. Don't invent new reasons to pause.

## 3. Push / merge behaviour

On personal repositories (this monorepo and similar):

- **Push after every commit** — don't batch, don't wait for approval
- **Direct to master** — no feature branches, no PRs unless the user explicitly asks
- **Wait for CI / deployment** to complete before marking the task done — a green local build isn't the finish line if CI still runs
- **`git add` specific files by name** — never `git add -A` or `git add .`, which can sweep in secrets, worktree cruft, or untracked experiments
- **Never skip hooks** (`--no-verify`, `--no-gpg-sign`) unless the user explicitly requests it
- **Never force-push to master** — warn the user if they request it

Shared / corporate repos follow whatever PR flow the project uses; when in doubt, ask.

## 4. When to dispatch subagents

**Default: do the work inline.** The main session reads files, writes code, runs tests, commits. Every handoff costs clarity and context.

Spawn a subagent only when one of these is true:

- **Parallel independent work** — two or more genuinely independent investigations can run at the same time
- **Context protection** — raw output would be huge (wide codebase sweeps, long log dumps, 50+ files) and would pollute the main context; let a subagent digest and summarise
- **User asked** — the user explicitly requested an agent
- **Long-running stand-alone task** — something that runs for a while and doesn't need your attention (use `run_in_background: true`)

### Dispatch table

| Task pattern | Agent type | Background? |
|---|---|---|
| Write code / fix code / refactor | `coder` | foreground |
| Debug error / test failure | `debugger` | foreground |
| Review code / plan scrutiny | `reviewer` | background |
| Explore codebase / research | `researcher` | foreground |
| System design / architecture | `architect` | foreground |
| Run verification commands | `verifier` | foreground |

### Rules when you DO dispatch

1. **Parallel when independent** — 2+ independent subtasks = spawn agents in parallel in one message
2. **Background for long-running** — agents marked "background" in the table use `run_in_background: true`
3. **Context protection** — keep raw output inside the subagent; ask for a concise summary
4. **Prompt quality** — every agent prompt MUST:
    - Be 50+ words
    - Start with a clear task description (action verbs: implement, fix, add, refactor)
    - Include acceptance criteria (checkboxes or "Done when" conditions)
    - Include specific file/path references
5. **Failed agent recovery** — one retry with a refined prompt; second failure → escalate to the user with a summary

## 5. NEVER do these — no exceptions

- Create files without asking
- Use `any` / untyped types when a specific type exists
- Refactor adjacent code (only touch what's requested)
- Add lint-ignore or type-error suppression comments
- Edit generated / auto-generated files
- Write implementation before tests (see `quality.md`)
- Commit temp / one-off / test scripts to the repo — store them outside the repo instead

## 6. Before touching any directory

Check if it (or any parent up to repo root) contains project-specific rules (e.g., `.claude/CLAUDE.md`, `.cursor/rules`). If found, read those files first — they may override anything in this file.

## 7. Docs — keep `infra/docs/` current

For any infra change that alters state described in
`infra/docs/architecture/` or `infra/docs/runbooks/`:

- **Update affected docs in the same commit.** Never land infra
  changes that leave docs stale.
- **New architecture-visible component** (new service, storage class,
  module, integration) → add or extend the relevant
  `architecture/*.md` doc.
- **New operational procedure** (restore flow, upgrade path, recovery
  step) → add a `runbooks/*.md` entry.
- **Medium/large designed changes** — write a
  `plans/YYYY-MM-DD-<topic>-{design,plan}.md` pair while designing,
  not after.
- **Incidents** → post-mortem in
  `post-mortems/YYYY-MM-DD-<topic>.md`.

If you can't tell which docs are affected, grep for the service or
resource name across `infra/docs/` — treat every match as a candidate
for update. This rule is `infra/`-scoped; other repos may or may not
have `docs/` directories.

See also: `infra/.claude/CLAUDE.md` "Update docs with every change"
for the full list of doc surfaces (includes `.claude/CLAUDE.md`,
`AGENTS.md`, `.claude/reference/service-catalog.md`).
