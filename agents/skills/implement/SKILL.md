---
name: implement
description: "Build a feature, fix a bug, or ship a spec or ticket. Worktree, a Workflow that reviews its own output until it is clean, and evidence a human can look at."
disable-model-invocation: true
---

# Implement

Build what the user described. Three things are not optional: the work happens
in a worktree, the build and review run as one Workflow, and you look at the
finished thing before you claim it works.

## 1. Worktree before the first edit

From inside the repo that owns the change:

```sh
homelab work start <topic>
```

It fetches, reads the real remote, creates `.worktrees/<topic>` on
`<os-user>/<topic>`, and carries the git-crypt filter flags. Enter it with
`EnterWorktree`. A shared checkout is never the workbench.

## 2. One Workflow does the build

Load the `workflow-authoring` skill before writing the script; it is the
authority on the API. Size every phase to the task and ignore the ambient
"under 15 agents" guideline. This skill is the instruction to spend what the
work needs.

| phase | agents | what they do |
|---|---|---|
| Research | 1 for an obvious one-file change, 3 or more across services | Read the callers, the blast radius, the existing patterns, the failure modes. Return the file partition for the next phase. |
| Implement | one per disjoint file set | Write the code. `/tdd` at agreed seams, red before green. |
| Review | exactly 3, in parallel | Code, interface, bugs. Section 3. |

Implementers share one worktree, so **their file sets must not overlap**. The
research phase returns the partition and the script asserts it is disjoint
before spawning. If the work cannot be partitioned cleanly, run the
implementers one at a time.

Sketch, not gospel:

```js
export const meta = {
  name: 'implement-<topic>',
  description: '<what this builds>',
  phases: [{ title: 'Research' }, { title: 'Implement' }, { title: 'Review' }],
}

const plan = await agent(RESEARCH_BRIEF, { phase: 'Research', schema: PLAN_SCHEMA })

let round = 0, findings = [], open = []
do {
  round++
  await parallel(plan.partition.map(p => () =>
    agent(implementBrief(p, open), { label: `impl:${p.owner}`, phase: 'Implement' })))

  if (round === 1 && plan.filesTouched === 1 && plan.linesChanged < 20) break  // §4

  findings = (await parallel([
    () => agent(CODE_REVIEW_BRIEF,      { label: 'review:code',      phase: 'Review', schema: FINDINGS }),
    () => agent(INTERFACE_REVIEW_BRIEF, { label: 'review:interface', phase: 'Review', schema: FINDINGS }),
    () => agent(BUG_REVIEW_BRIEF,       { label: 'review:bugs',      phase: 'Review', schema: FINDINGS }),
  ])).flatMap(r => r.findings)

  open = findings.filter(f => f.severity === 'CRITICAL' || f.severity === 'MAJOR')
} while (open.length && round < 5)

return { round, open, nits: findings.filter(f => f.severity === 'NIT') }
```

## 3. The review loop

Three reviewers run in parallel against the diff, every round:

1. **Code.** Run the bundled `/code-review` skill. Correctness, reuse, simplification, efficiency.
2. **Interface.** Whatever a human touches. A UI change: drive the real page and screenshot it. A CLI: the flags, help text, error messages, output shape. A library: the public API. Infra: what an operator sees when it breaks.
3. **Bugs and improvements.** Edge cases, failure modes, data assumptions, concurrency, anything the first two missed.

Every finding carries a severity of **CRITICAL**, **MAJOR** or **NIT**, plus a
file, a line, and a concrete failure scenario: inputs or state, then the wrong
output. A finding with no failure scenario is a NIT.

Feed the open findings back to the implementers and review again. Exit when a
round returns no CRITICAL and no MAJOR.

**Cap at 5 rounds.** Still open after round 5: stop, land nothing, and report
what survived plus what each round changed. A loop that has not converged in
five passes is disagreeing about intent, which is the user's call, not the
agents'.

On the final round the implementers fix the NITs that are a line or two. The
rest go in the summary as a plain list. Do not file them anywhere unless the
user asks.

## 4. The small-change exception

After the implement phase, sum what actually changed. **One file and fewer than
20 lines: skip the review loop** and go straight to verification. Measure the
real `git diff --stat`; never predict the size beforehand.

## 5. Evidence, before you say it works

The interface reviewer produces this every round, and you produce it once more
after the loop converges. A green test suite is not this.

| changed | evidence |
|---|---|
| a web UI or page | drive the real URL, screenshot to a path you own, and READ the screenshot back |
| Android, phone, tablet | the shared emulator (`presence claim service:android-emulator`, then `adb connect <address>` (find it with `homelab how "android emulator"`), or noVNC at android-emulator.viktorbarzin.me), never a desktop browser at phone width |
| iOS or Safari | `homelab ios shot out.png --url <url>`, then read the screenshot back |
| a CLI or a homelab verb | run the built binary against the live stack, paste what it printed |
| infra or Terraform | the live resource after rollout (`homelab k8s get`, `net check`), never plan output |
| a query, migration or data change | run it against the real data and show the rows |

Waiting is part of the check: `homelab deploy wait`, `homelab ci watch`,
`homelab k8s rollout-status`, or a `Monitor` until-loop. Never `sleep`.

No instrument exists for part of it? Say so in the same breath as the claim:
what you checked, what you did not, and what would settle it.

## 6. Land it

```sh
homelab work land --verify-cmd "<the repo's test command>"
homelab work clean <topic>
```

`land` merges master in, runs the verify command, pushes `HEAD:master` and
watches CI. Pass `--verify-cmd` unless the repo root has a `go.mod`. CI green
means a pipeline *containing* your commit went green, so check ancestry: a busy
repo cancels your pipeline when the next push lands.

Close with three lines: what changed, the evidence, the CI result.
