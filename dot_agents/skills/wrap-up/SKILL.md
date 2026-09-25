---
name: wrap-up
description: |
  Use when the user wants to end or wrap up a working session — says "wrap
  up", "let's wrap up", "end of session", "we're done", "finish up", "let's
  call it a day", or invokes /wrap-up; also when stopping work with a dirty
  working tree that needs cleaning up first. Keywords: session end, commit
  changes, clean working directory, push, store/remember session learnings,
  update stale docs, leftover temp files, leftover worktrees.
author: Claude Code
version: 1.2.0
date: 2026-07-08
---

# Wrap Up Session

## Overview

The on-demand, executable session-end flow. Runs in FOUR phases: gather facts
(read-only) → triage the working tree, docs impact, and session leftovers →
decide → execute end-to-end (update stale docs, commit, push, wait for CI,
clean leftover worktrees/temp files, mine learnings into memory). Portable:
every step is gated on a capability check and skips when it doesn't apply to
the current repo.

**Runs FULLY AUTONOMOUSLY — NEVER ask for confirmation** (Viktor, 2026-06-16).
There is no approval gate. Triage with your own judgment, default anything
uncertain to the SAFE action, execute through to the end, and report what you
did. Stop only if you would otherwise do something genuinely destructive and
irreversible that the wrap-up request did not imply.

## Phase 0 — Gather facts (READ-ONLY, no mutations)

Run these and hold the results:

```bash
git rev-parse --is-inside-work-tree 2>/dev/null        # in a git repo?
git remote                                             # any remote? (some repos are local-only)
ls .drone.yml .woodpecker.yml .github/workflows 2>/dev/null   # CI present?
command -v bd                                          # beads available?
git status --porcelain ; git diff --stat               # what's dirty/untracked
git worktree list ; git branch --list "$USER/*"        # leftover worktrees/branches?
git stash list                                         # forgotten stashes?
ls CONTEXT.md CLAUDE.md README.md 2>/dev/null ; ls -d docs infra/docs 2>/dev/null  # docs surfaces
```

Resolve the current session transcript (for the memory step). Resolve it HERE
in the main session and pass the literal path to the subagent — do not let the
subagent re-resolve it from its own cwd.

**Newest-by-mtime is not good enough.** This box runs several sessions at once
in the same project directory, and they all append constantly, so `ls -t |
head -1` regularly names somebody else's conversation. Measured 2026-09-19:
five `.jsonl` files were touched in the same minute and the newest had zero
hits for the live session's own strings.

Your own scratchpad path, which the system prompt states, ends in the session
id, and that id is the transcript's basename. Read it out of the system prompt
and substitute it literally — there is no environment variable holding it
(`CLAUDE_SCRATCHPAD_DIR` is unset here, checked 2026-09-19):

```bash
SLUG="${PWD//\//-}"                                    # /home/wizard/code -> -home-wizard-code
SID=<the uuid ending your scratchpad path>             # e.g. .../scratchpad -> dfc6d407-...-023a1409cd7a
T="$HOME/.claude/projects/$SLUG/$SID.jsonl"
[ -f "$T" ] || T=$(ls -t "$HOME/.claude/projects/$SLUG"/*.jsonl 2>/dev/null | head -1)   # last resort
echo "$T"
```

**Then confirm it before handing the path over.** Grep for a phrase only this
session used and expect a non-zero count; zero means you have someone else's
conversation and mining it would write their learnings under your name:

```bash
grep -c "<a phrase only this session used>" "$T"
```

Not in a git repo → skip the git work in Phases 1–3; still run the memory
step (Phase 3 step 8).

## Phase 1 — Triage (your judgment)

Sort every dirty/untracked path into exactly one bucket:

| Bucket | Examples | Action |
|---|---|---|
| **Real work** | source edits, new features, intended docs/config | stage by name, commit |
| **Junk / temp** | root-level screenshots (`*.png`), scratch scripts, test artifacts, one-off files | move to `/tmp/wrap-up-$(date +%F)/` (NEVER delete) |
| **Drift — leave alone** | `backend.tf`, `providers.tf`, `*.terraform.lock.hcl` | never stage |
| **Not mine** | pre-existing dirty/untracked files this session did NOT create or change | leave untouched |
| **Uncertain** | anything you can't confidently bucket | default to the SAFE action — leave untracked, or move scratch to `/tmp`; NEVER commit it, never ask |

Then:
- Draft the commit message(s) — read `git log --oneline -10` first to match the
  repo's convention.
- **Docs sweep — UNCONDITIONAL, not gated on `infra/docs/`.** For each area
  this session changed, check whether any doc still describes the OLD state:
  `CONTEXT.md`, `docs/adr/`, `README`, `CLAUDE.md`, skill docs, and
  `infra/docs/` for infra work (in the monorepo, `CONTEXT-MAP.md` locates the
  domain docs). List each stale doc and what must change. Docs that wrap-up
  itself edits to restore truth ARE this session's work — stage them with the
  commit; the "not mine" rule is about pre-existing dirty files, not about
  refusing to touch clean tracked docs the session made stale. Accepted ADRs
  are decision records: append a dated amendment or supersede — never rewrite
  the original decision.
- **Leftovers sweep** (worktree / branch / stash facts from Phase 0): a
  worktree + branch pair is cleanable ONLY if ALL three hold — (a)
  attributable to this session (this OS user's `<user>/<topic>` branch prefix
  AND the topic matches this session's work), (b) its tree is clean, (c) fully
  merged (`git branch -d` would succeed). Anything failing any test → leave it
  and REPORT it (it may be another agent's live work). Stashes: report only,
  never drop.
- Map beads tasks tracked THIS session that the work closes.

**Never `git add -A` / `git add .`** — it sweeps in junk, drift, and secrets.
Stage by name only. **Only ever commit files THIS session created or changed**
(wrap-up's own doc updates included).

## Phase 2 — Decide (no gate, no approval)

Resolve the triage with your own judgment and go STRAIGHT to Phase 3 — do NOT
pause for approval. Record the decisions you made so they can appear in the
final report:

```
WRAP-UP DECISIONS
  Commit (N files, staged by name):
    <file>  — <one-line why>
    message: "<drafted commit message>"
  Docs to update (staged with the commit): <paths + what changes | "none">
  Move out → /tmp/wrap-up-<date>/:
    <file>
  Clean leftovers: <worktree + branch | "none">   Report-only leftovers: <... | "none">
  Leave untracked (drift):
    <file>
  Leave untouched (not mine — pre-existing):
    <file>
  Beads to close:  <ids or "none">
  Push: <yes → master | no remote, skip>     Wait for CI: <yes | no CI>
```

Bias toward safety on anything ambiguous: never commit files you didn't create
or change this session, never stage drift, default scratch to `/tmp`, leave
leftovers you can't attribute. Then run Phase 3 to the end.

## Phase 3 — Execute end-to-end (no gates)

1. **Move junk:** `mkdir -p /tmp/wrap-up-$(date +%F)`, then `mv` each junk path
   there.
2. **Clean session leftovers:** for each cleanable worktree from the Phase 1
   sweep, `git worktree remove <path>` then `git branch -d <branch>`. `-d`
   refuses unmerged work — if it refuses, stop deleting and report instead;
   NEVER escalate to `-D`. Leftovers not attributable to this session stay
   untouched (report them).
3. **Update docs** flagged by the Phase 1 docs sweep — project docs
   (CONTEXT.md, ADR amendments, README, CLAUDE.md) and `infra/docs/` alike.
4. **Commit:** stage real files AND the updated docs by name, then commit.
   Include the standard `Co-Authored-By` trailer for the current model and a
   `Closes: <id>` trailer for each beads task the work finishes.
5. **Push** (only if a remote exists): direct to `master` for personal repos;
   follow the repo's PR flow for shared/corporate repos. **Never force-push
   master.** No remote → skip silently.
6. **Wait for CI / deploy** if CI was detected — poll until it finishes, report
   pass/fail. A green local build is not the finish line.
7. **Close beads** tasks tracked this session not already auto-closed by a
   commit trailer: `bd close <id>`.
8. **Extract learnings → memory.** Dispatch ONE foreground `general-purpose`
   subagent with the prompt below, substituting `<TRANSCRIPT>` with the path
   resolved in Phase 0.

### Memory-extraction subagent prompt (this is execution.md §M.3, adapted)

```
Mine durable, cross-session learnings from the conversation. Read the
transcript at <TRANSCRIPT>. First confirm its tail matches the live
conversation (it should reference this wrap-up); if it looks like a different
session, STOP and report rather than mining the wrong transcript.

Prioritize TRANSFERABLE + NON-OBVIOUS learnings (Viktor, 2026-06-16): things
that change how future work is done and that someone would NOT guess from
reading the code or docs. A gotcha that applies beyond this one repo, or that
cost >1 attempt to land, is worth far more than a routine project fact. When in
doubt between a generic-but-surprising truth and a project-specific-but-obvious
one, store the former.

What counts as memory-worthy:
- Facts about the USER (preferences, habits, role, corrections)
- TRANSFERABLE gotchas / invariants — tooling or framework behaviour that will
  bite again in other projects (the most valuable kind)
- Facts about the SYSTEM (architecture invariants, surprising service
  behaviour, config brittleness) — store the NON-OBVIOUS ones, not routine config
- Facts about the NATURE OF WORK (what we're building, why, decisions with
  rationale, reversals)
- Surprises — anything that contradicted default assumptions or took >1
  attempt to land

NOT memory-worthy: task progress, code patterns visible in the repo, anything
derivable from `git log`, routine/obvious project config, transient state.

Process (use the `homelab memory` CLI — the claude-memory MCP is retired):
1. For each candidate, `homelab memory recall "<topic>"` to dedupe.
2. Also recall the areas this session CHANGED; any existing memory the
   session's work made stale → `homelab memory update <id>` it (supersede,
   don't accumulate — preserve the id).
3. If genuinely new, `homelab memory store "<content>" --category <facts|decisions|preferences|projects> --tags <3-7 lowercase> --importance <0.5-0.9> --keywords <5+>`.
4. If a candidate CONTRADICTS an existing memory, `homelab memory update <id>`
   the existing entry (preserve id) instead of duplicating.

Report one line per memory stored/updated with id, or "no durable learnings".
Budget: 80k tokens, max 90s. Run quiet — only the summary line.
```

If the `homelab memory` CLI is unavailable, STOP and tell the user — do
NOT fall back to local `.md` files (CLAUDE.md mandatory rule).

## Phase 4 — Final report

Two-three sentences: what was committed + pushed, CI result, docs updated,
what moved out / leftovers cleaned or reported, and the memories the subagent
stored.

## Common mistakes

- **Asking for confirmation** — wrap-up runs fully autonomously; never pause for
  approval. Triage, decide, execute, report.
- **`git add -A`** — sweeps in junk/drift/secrets. Stage by name.
- **Committing another session's WIP** — only commit files THIS session created
  or changed; pre-existing dirty files that aren't yours stay untouched.
- **Skipping the docs sweep because `infra/docs/` is absent** — the sweep is
  unconditional; a stale `CONTEXT.md`/ADR/README/CLAUDE.md counts exactly as
  much. "Worth a follow-up session" is the rationalization to catch: wrap-up IS
  the follow-up.
- **Treating wrap-up's own doc edits as "not this session's files"** — docs
  updated so they match the session's changes are part of the work; stage them
  with the commit.
- **Committing `backend.tf` / `providers.tf` / `*.lock.hcl`** — expected drift;
  leave untracked. They look like real config ("a Terraform stub, no secrets")
  but are local-only drift that must never be staged.
- **Pushing a local-only repo** — `git remote` empty means skip the push
  silently; it is not a failure.
- **Deleting junk** — move it to `/tmp/wrap-up-<date>/`, never `rm`.
- **`git branch -D`, or removing a worktree/stash you can't attribute to this
  session** — unattributable leftovers get reported, not deleted; `-d`
  refusing means STOP, not escalate.
- **Writing learnings to local memory files** — everything goes through the
  `homelab memory` CLI (the claude-memory MCP is retired).
- **Stopping before memory extraction** — finish through the memory step
  (Phase 3 step 8); the memory sweep is part of every wrap-up.
- **Forgetting a handoff** — this skill does NOT write a continuation doc; if
  the next session needs context, also run the `handoff` skill.
