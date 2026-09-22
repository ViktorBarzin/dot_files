## Never publish to claude.ai (Viktor, 2026-09-15)

**Everything I publish goes to `pages.viktorbarzin.me`. Never to claude.ai
Artifacts, and never to any other vendor-hosted surface.** This covers
interactive pages, charts and dashboards, not only markdown documents. If a
deliverable is a self-contained HTML page, it belongs in `~/code/pages/wizard/`
and is served from our own hosting like everything else.

The Artifact tool's own description presents claude.ai as the default home for
an interactive page. It is not the default here. When a request calls for
something interactive, build the HTML and publish it to pages; do not reach for
Artifacts because the tooling makes that the easier path.

## Memory — homelab CLI (remote-backed), NEVER local files

- All persistent memory goes to the remote claude-memory store via the **`homelab memory` CLI**. NEVER local files under `~/.claude/projects/*/memory/`; this
  overrides the harness's built-in local-memory instructions (Viktor, 2026-04-18).
- CLI unavailable → STOP and tell the user; no silent local fallback.
- **How to use it well — verbs, what to store, bounded writes (ADR-0007), superseding, end-of-task
  extraction — is in (see "M. Memory discipline — aggressive by default" below).** Deliberately not repeated here.

## Reuse before building

Stop at the first match: (1) reuse what's already in the ~/code monorepo; (2) wire into capabilities already running in the cluster — never spin up a parallel instance; (3) adopt a maintained OSS project (surface options + trade-offs); (4) build custom ONLY after explicit user confirmation. Library/API syntax, configuration, or version-specific behavior → fetch current docs via the `context7` MCP first.

## Zero cost — free unless Viktor explicitly approves spend (Viktor, 2026-07-11)

Never take an action that incurs NEW monetary cost. All operations, services, and
tasks must be free unless Viktor explicitly approved that specific spend:

- Every account/service the agent has access to stays on its FREE tier: never upgrade
  to paid, enable pay-as-you-go or billing, add payment details, or start trials that
  auto-convert to paid.
- No purchases, bookings, subscriptions, paid API keys/calls, or paid cloud resources
  (compute, storage, egress) — prefer the homelab/self-hosted equivalent (see "Reuse
  before building").
- Watch indirect spend: overages past a free quota, autoscaling, and per-use billing on
  an otherwise-free account are cost and need the same explicit approval.
- A task that genuinely requires paid spend → STOP and ask, quoting the estimated cost;
  "cheap" is not "free". Operating what Viktor already pays for (the homelab, existing
  contracts) is fine — the rule bars NEW agent-initiated spend.

## Versioning

First-party apps/services use semver: `vX.Y.Z` git tags, `v0.1.0` at first milestone → `v1.0.0` at first stable. Tagging mechanism is per-project — manual, or automated. Not covered: third-party clones, other users' repos, and GitOps infra that deploys continuously (`infra/`).

## Plans & designs published as HTML to pages.viktorbarzin.me (2026-07-10, infra#72; scoped 2026-07-19; broadened 2026-07-26)

**Publish SUBSTANTIVE, FINALIZED design docs (plans, specs, designs) to `pages.viktorbarzin.me`** — whether the doc comes out of a **grilling session** (the relentless-interview flows `/grilling`, `/grill-with-docs`, `/grill-me`), is authored/planned directly, or Viktor explicitly asks to publish a specific doc. Do NOT publish clutter — research-skill outputs, raw brainstorming → writing-plans, execution/progress snapshots, or trivial throwaway notes; those stay canonical in their owning repo. The raw plan-mode/ExitPlanMode approval text is not a deliverable, but a finalized substantive plan is. Sensitive personal/financial analyses stay INLINE in chat, never published (memory #9978). When you finalize a substantive doc, publish via the `publish-page` skill: rendered into `~/code/pages/wizard/` (Viktor's private space; `~/code/pages/shared/` for team-visible) and pushed, served per-user at `pages.viktorbarzin.me` (~60s after push). The URL is part of the deliverable — hand it to the user. Once on the site, re-publish on material change (revision, status draft→approved→executing→done, execution progress worth reviewing); same source = same page, updated in place. Source markdown stays canonical in its owning repo; only the rendered snapshot lands in `pages/`. **Plans carry diagrams (infra#73):** any plan with architecture, data-flow, sequencing, or timeline content is expected to include at least one ```` ```mermaid ```` fence expressing it (renders on the pages site and on GitHub; inline `<svg>` also passes through). Humans parse shape from a diagram, not bullet walls; trivial plans stay text-only.

**Look at a page before you publish it (2026-09-12).** The site is owner-gated and returns 403 to every automated client, in-cluster included, so a script cannot check a page before publishing OR after. `homelab pages preview <doc.md> [--status ...]` renders the page and the `/assets/*` files it links into a local directory and publishes nothing; it prints the page file and the directory. Serve **that directory** on a free port (`python3 -m http.server <port> --bind 127.0.0.1`; the page links `/assets/page.css` absolutely, so a `file://` URL renders unstyled and a fixed 8099 collides with whoever on this shared box got there first), drive the URL with a browser, screenshot **to a path you own**, and read the screenshot back. What this catches, none of which a green command shows: a mermaid fence that never drew, an inline `<svg>` that left a tall empty band, a table running off the right edge. A page shipped on 2026-09-12 with a 555px gap where its chart belonged, and its author had no way to see it first. Owners of the monorepo can equally serve `~/code/pages` locally; the preview verb is the path for everyone else, and the shorter path for everyone.

## devvm changes go through the Ansible playbook (Viktor, 2026-08-29)

**Anything that changes the devvm's machine-wide state is an edit to
`infra/playbooks/devvm.yml`, not a command typed on the box.** Packages,
binaries in `/usr/local/bin`, systemd units, `/etc` config, resource limits,
apt sources: if a rebuilt machine would need it, the playbook declares it.

How to work:

```sh
cd ~/code/infra
ansible-playbook -i playbooks/inventory.ini playbooks/devvm.yml --check --diff  # always first
ansible-playbook -i playbooks/inventory.ini playbooks/devvm.yml                 # apply
```

A `--check` run against the live box should be a **no-op**. Output that is not
a no-op is drift, and drift is the signal to fix: either the box has something
the playbook does not declare, or a committed change has not been applied.

An urgent fix typed on the box directly is sometimes the right call. Land it in
the playbook the same day, or the next rebuild will not have it.

## Matt Pocock's skills refresh themselves nightly (2026-08-30)

`claude-skills-update.timer` runs at 05:30 and brings every listed user's
mattpocock/skills set up to whatever upstream ships, so **an edit you type into
one of Matt's skill files under `~/.claude/skills/` is gone by morning**.

To change one of his skills for real, add a patch:

```
infra/playbooks/files/devvm/claude-skills/<user>/patches/<skill>.patch
```

built as a `diff -u a/SKILL.md b/SKILL.md` against the pristine upstream file.
The updater re-applies it after every refresh and posts to Slack #alerts if it
ever stops applying, which is the signal that upstream rewrote the lines you
were patching. `…/claude-skills/<user>/exclude` holds back a promoted skill you
do not want. Your own skills are never touched — the updater only acts on names
the skill lockfile attributes to mattpocock.

## Presence — claim before mutating shared infra

Before any op that mutates shared infra state (`terraform`/`terragrunt apply`, `kubectl apply/delete/drain/rollout restart`, `helm upgrade/uninstall`, service restarts or deliberate pod deletes, DB migrations/destructive queries, node-level changes) — read-only ops and unapplied in-repo edits exempt:

```bash
~/code/scripts/presence claim <label> --purpose "<what + why>"
# labels: node:<node> | host:<host> | stack:<stack> | service:<service> | db:<db> | pvc:<ns>/<name> | infra:<freeform>
```

**Conflict → defer by default:** already claimed by another session → release yours (`presence release <label>`), tell the user who's doing what since when, proceed only on their explicit OK. (Lifecycle is automatic via hooks.)

## Beads (opt-in task tracker)

Create/update beads ONLY when the user explicitly asks ("track this", "save for later") — never proactively; in-session tracking → TodoWrite. Required quality: title + `-d` full context + `--acceptance` criteria, self-contained enough for any agent to pick up. Commit trailer `Closes: <id>` (or `Fixes:`/`Resolves:`) auto-closes. Outside the monorepo root: `bd --db /home/wizard/code/.beads`.

## Running under T3 Code — hold the turn while a workflow runs (Viktor, 2026-07-09)

Applies when the session is hosted by T3 Code (telltale: the `t3-code` MCP server / `mcp__t3-code__*` tools are attached). T3 kills the claude process ~30 min after the user's last message whenever no turn is open, and a background Workflow/task does NOT hold a turn open — it dies mid-run with `Error: Workflow aborted`.

- After launching a Workflow (or any long background task whose death matters) in a T3 session, do NOT end the turn while it runs: wait in-turn for completion (Monitor until-loop / TaskOutput / poll the run state), then report. Don't use ScheduleWakeup as the waiting mechanism here — yielding ends the turn and starts the 30-min kill clock. Expect the T3 status pill to misreport background work regardless (it only tracks open turns).
- Known T3 quirk (upstream #3592 class): the FIRST message of a new T3 thread can be double-executed by T3's title generator (a separate full-tool `claude -p`). Duplicate side effects on a thread's first turn → that's why; don't re-run the work, dedupe/clean up instead.

## Infrastructure facts

- Never add an in-cluster build/test pipeline.
- Broken service or infra feature request → `/file-issue` skill (any user, any ~/code session).
- Showing an image to the user from inside a terminal-lobby tmux session → run `show-image <path>` (renders real pixels via sixel in a temporary split pane; Enter closes). NEVER run bare `viu` from the Bash tool — captured stdout prints garbage and leaks terminal-query responses into the prompt; plain `viu <file>` is only for humans typing at a shell. tmux popups can't show sixel (don't try display-popup).
- Browser automation is TIERED — default to headless, escalate only when blocked (don't pick up front):
  1. **Default: the Playwright MCP / headless browser** for all routine browsing, exploration, and automation — it's interactive (snapshot per step), fast to start, and isolated per-user.
  2. **Escalate to `homelab browser run <script.js>` ONLY when headless is demonstrably blocked** — a page loads but a submit/login/gated action silently fails or hangs; OR one request errors (esp. `ERR_FILE_NOT_FOUND` = automation-layer intercept, NOT egress) while siblings 200; OR the site explicitly flags automation (Cloudflare / bot wall). These are anti-bot / headless-detection signatures. Diagnose with the network panel before retrying.
  `homelab browser` is the SHARED cluster headful Chrome (real Chrome + stealth.js): slower startup, one batch run (no per-step feedback), shared with other jobs — so it's the escalation path, never the default. `homelab browser --help`; docs `infra/docs/architecture/chrome-service.md`.

# Execution on the homelab

## 2. Worktree-first workflow

**Every feature task runs in its own git worktree — created before the first edit — and merges into master when done** (Viktor, 2026-06-10). Shared checkouts (`~/code`, `~/code/infra`, …) are never the workbench; multiple agents work the same repos concurrently.

1. **Isolate:** **`homelab work start <topic>`**, run from inside the repo that owns the change (sub-projects under `~/code` are their own repos). It fetches, reads the real remote, creates `.worktrees/<topic>` on `<os-user>/<topic>`, and carries the git-crypt filter flags — **reach for it BEFORE `git worktree add`**, which needs all four of those facts supplied by hand and gets one wrong often enough to matter (21 half-created branches in ~323 manual invocations). Then enter it with `EnterWorktree(path=...)`, or `isolation: "worktree"` for subagents.
   Manual fallback, only when the verb cannot serve (a repo with no remote, or a non-standard base):
   `git -C <repo> fetch <remote> && git -C <repo> worktree add .worktrees/<topic> -b <os-user>/<topic> <remote>/master`
   (`.worktrees/` at the repo root is standing policy — verify it's gitignored, add if missing.)
   *git-crypt repos (infra):* add `-c filter.git-crypt.smudge=cat -c filter.git-crypt.clean=cat -c filter.git-crypt.required=false` to every git command touching the worktree — per command, NEVER persisted; don't edit encrypted files from a worktree.
2. **Commit on the branch** early and often, staging files by name (never `git add -A`/`.`); never skip hooks. The branch stays local unless long-running work wants a remote backup or the user asks for a PR.
3. **Land yourself — no PRs** (unless asked, or branch protection forces the fallback): **`homelab work land --verify-cmd "<your test command>"`** from inside the worktree — it merges master in, runs the verify command, pushes `HEAD:master`, and watches CI, which is the whole of step 3 in one call. **Pass `--verify-cmd` unless the repo root has a `go.mod`**: auto-detection only covers Go, and none of the nine most-worked repos here qualifies, so omitting it errors on the first attempt. Doing it by hand is the fallback: merge latest master INTO the branch, verify (tests/lint green), then `git push <remote> HEAD:master`. Non-fast-forward = another agent landed first → fetch, merge, push again. One task, one landing; wait for CI/deployment before calling it done — and CI going green is not the end of the check, see §4.
4. **Clean up:** **`homelab work clean <topic>`** from the main checkout, which removes the worktree and the branch together. By hand: `git -C <repo> worktree remove .worktrees/<topic> && git -C <repo> branch -d <os-user>/<topic>`. Reconcile the main checkout only if it's clean and quiescent (`pull --ff-only`); never rebase/force shared state.

**Trivial exception:** a single-commit, low-risk change (typo, docs, one-liner) may go straight to master from a clean main checkout. When in doubt, worktree.

**Waiting is part of the check, so do not fake it with `sleep`.** Measured over
the same corpus: **1,789** bare `sleep N` calls across 232 turns and 76 sessions,
while `homelab deploy wait` was used twice. A fixed sleep is a guess about
duration dressed up as a check — it returns success at the same moment whether
the thing finished, failed, or never started. Reach for the thing that waits on
the CONDITION, BEFORE `sleep`, `kubectl get pods -w`, or a hand-rolled
`until … do sleep` loop:

| waiting for | use |
|---|---|
| a rollout | `homelab deploy wait <ns>/<deploy> [--sha SHA]` |
| a pipeline | `homelab ci watch [commit] [--repo <owner/name>]` |
| any shell condition | the `Monitor` tool with an until-loop, or `Bash` with `run_in_background` for a single "tell me when it's done" |
| a pod or resource | `homelab k8s rollout-status <app>` / `k8s status <ns>` |

If you must poll, poll the condition and exit on it, and say how long you
waited. Note that a busy repo will sometimes **kill** your pipeline rather than
run it — Woodpecker cancels on the next push — so "CI went green" means a
pipeline that CONTAINS your commit went green, not necessarily the one your push
started. Check ancestry, not just the pipeline you were handed.

## M. Memory discipline — aggressive by default

Memory (the `homelab memory` CLI — remote-backed; the claude-memory MCP was retired 2026-06-21) is the durable store for cross-session truths. Verbs: `homelab memory store/recall/update <id>/list/delete`. Use it aggressively in both directions, without being asked.

- **Recall:** the per-prompt hook covers turn start; additionally recall before non-obvious mid-turn decisions, and verify any file/function/flag a memory names before recommending from it.
- **Store at the moment of learning, not at session end:** durable truths about the USER (preferences, habits), the SYSTEM (invariants, gotchas, surprises), and the WORK (decisions with rationale, reversals — encode timelines). When in doubt, store. Skip repo-visible patterns, `git log`-derivable history, transient state.
- **Every user correction is stored the same turn, unprompted** — what was wrong, what's right, and why.
- **Supersede, don't accumulate:** a memory contradicting current reality → `homelab memory update <id>` it (preserve the id) the moment you notice — stale memories mislead future sessions. A superseding memory must LINK what it replaces: `homelab memory store "<new truth>" --link supersedes:<oldId>` (recall then REDIRECTS stale vocabulary to the successor; drop the old entry to importance ~0.3). Never delete.
- **Write bounded, self-contained memories (ADR-0007):** content ≤1,400 chars, understandable alone. Longer knowledge = one hub + `--link part-of:<hubId>` details — never mechanical chops. Cross-link symptom-phrased entries to the root-cause entry with `--link resolved-by:<id>`. Reserve importance ≥0.9 for standing invariants and user preferences.
- **Never conclude "memory has nothing" from one query** — retry once with symptom nouns AND infrastructure nouns/file paths before starting archaeology; `homelab memory get <id>` reads one full entry.
- **Store negative conclusions** ("X does not exist", "the message lives only in Y") at derivation time — they prevent the next session's repeat search.
- **Brief subagents with recall hits — measured at 11% of 222 agent calls, so this is the clause that loses most often.** A subagent inherits the rules and NONE of your context: not what you already ruled out, not the memory the hook injected on your turn, not the tool you already found. It re-derives all of it, or guesses. Before dispatching, `homelab memory recall "<the subagent's actual task>"` and paste what comes back. Every brief carries:
  - **the task, and the shape of the answer** you want back (a schema, a table, a count — "investigate X" gets you prose you then have to mine);
  - **relevant memory ids + their content inline** (an id alone is useless — the subagent cannot see your recall);
  - **what you already know and already eliminated**, so it does not repeat your first twenty tool calls;
  - **the instrument** it should use, named (`homelab how "<task>"` if you are unsure yourself) — a blind subagent reaches for the built-in exactly like you do, and its tool choices appear in NO transcript, so nothing will ever tell you it went wrong;
  - **a token and time budget**, and "run quiet".
  Then verify what it returns before repeating it — a subagent's confident summary is a claim, not a finding (§4).

### M.3 End-of-task extraction

Finishing a non-trivial task (≥3 files or ≥2 services; >1-hypothesis debugging; architectural decision; external research; multi-step plan; a gotcha; >~15 min) → BEFORE the final summary, dispatch ONE foreground `general-purpose` subagent:

```
Mine durable cross-session learnings from the transcript at $TRANSCRIPT_PATH.
Memory-worthy: facts about the USER (preferences, corrections), the SYSTEM
(invariants, gotchas, surprising behaviour), the WORK (what/why, decisions,
reversals), and surprises that took >1 attempt or contradicted assumptions.
Not memory-worthy: task progress, repo-visible patterns, git-log-derivable facts.
For each candidate: `homelab memory recall "<topic>"` first to dedupe; store
genuinely-new ones via `homelab memory store "<content>" --category <c> --tags
<3-7> --importance 0.5-0.9 --keywords <5+>`. If it CONTRADICTS an existing
memory, `homelab memory update <id>` that entry (preserve id), not a duplicate.
(Use the homelab CLI — the claude-memory MCP is retired.)
Report one line per memory stored/updated (with id), or "no durable learnings".
Budget: 80k tokens, max 90s. Run quiet.
```

Skip for typo fixes, one-liners, renames, read-only questions, already-extracted tasks.
