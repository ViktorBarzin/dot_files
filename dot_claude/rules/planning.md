# Planning (applies to ALL agents)

**No implementation without completed research.** This flow MUST run before implementation begins.

The approval gate at the end of planning is **ExitPlanMode** — there is no second user-gate step once the plan is accepted. See `execution.md` for what happens after approval.

## Phase 1: Interview the User

**Interview relentlessly. Make sure that all ambiguities are resolved before execution.**

Before dispatching any researcher, ask targeted questions:

- **What exactly should change?** — not "add feature X" but the specific behavior expected
- **What are the constraints?** — backward compatibility, performance requirements, scope limits
- **What should NOT change?** — explicit out-of-scope items
- **Who are the consumers?** — who calls this code, who depends on it, who will be affected
- **What edge cases worry you?** — empty input, timeouts, stale data, concurrent access

**Gates — do NOT proceed to Phase 2 until ALL of these are true:**
- [ ] Every question has been answered by the user (not assumed)
- [ ] If any answer raised new questions, those were asked and answered too
- [ ] Zero ambiguity remains — you can describe the exact change without "probably", "maybe", "might"
- [ ] The user has not said "I'm not sure" about any critical decision — if they did, resolve it

**Longer planning = fewer fixes later.**

## Phase 2: Code Exploration

Dispatch `researcher` subagents:

### Mandatory investigations

| Investigation | How | Blocker if skipped |
|---|---|---|
| **All callers + blast radius** | Claude Code `Grep` tool for references, IDE "find all references" | Cannot assess risk of change |
| **Existing patterns + reusable code** | Search for similar implementations before creating new | May duplicate existing utility |
| **Edge cases + failure modes** | Trace error handling paths, check null/empty/stale input | Bugs ship to production |
| **Current data state** | Query real data to understand current behavior with numbers | Assumptions may be wrong |

### For 2-3 parallel researchers

| Researcher | Focus |
|---|---|
| R1: Existing code + patterns | Trace the code path being modified. Find all callers. Identify existing abstractions to reuse. |
| R2: Blast radius + dependencies | Who depends on this? Cross-team callers? What breaks if we change the interface? |
| R3: Data + edge cases | Query real data to validate assumptions. Identify failure modes. |

### For infra changes

If the work touches state described in `infra/docs/architecture/` or
`infra/docs/runbooks/`, read the relevant files BEFORE dispatching
researchers. These docs are the authoritative starting point for
current infra state — what's deployed, how it's wired, which
conventions apply.

- `infra/docs/architecture/` — long-lived state (networking, storage,
  auth, databases, CI/CD, monitoring, backup-dr, etc.)
- `infra/docs/runbooks/` — operational procedures (restores, upgrades,
  recoveries)
- `infra/docs/plans/` — dated design/plan pairs for prior changes;
  grep here first when a similar change has been done before
- `infra/docs/post-mortems/` — incident analyses; relevant when work
  touches a past failure surface

If the docs contradict the live state, that mismatch is itself a
finding — surface it and resolve before proceeding.

## Phase 2b: Challenge, Verify, and Counter-Propose

**Always required.** After researchers report back, spawn **2 independent challenger subagents** in parallel. Each works INDEPENDENTLY — they do NOT see each other's output.

### Challenger mandate:

```
## Role: Independent Research Challenger

You are reviewing research findings. Your job has THREE parts:

### 1. Scrutinize
- Challenge the root cause analysis — what else could explain this?
- Question assumptions — what is assumed without evidence?
- Find missed edge cases — what happens with empty/null/stale/concurrent?
- Identify missing investigations — what callers/consumers were NOT checked?

### 2. Verify every reference
- For every FILE PATH cited: confirm it exists
- For every FUNCTION/CLASS cited: confirm it exists
- For every DATA CLAIM: confirm the data source exists and the query is valid
- Flag ANY reference that cannot be verified as UNVERIFIED

### 3. Counter-propose
- Propose at least ONE alternative approach to the problem
- Your alternative must ALSO be backed by verified code/data references
- Explain trade-offs: why your approach might be better or worse

Report:
- VERIFIED: claims you confirmed exist
- UNVERIFIED: claims you could not confirm
- ISSUES: genuine problems with the findings (not nitpicks)
- COUNTER-PROPOSAL: your alternative approach with references
- VERDICT: AGREE (approach is sound) or DISAGREE (significant issues remain)
```

### Convergence check

After challengers return, evaluate:

1. **Unverified claims** — if any reference was flagged UNVERIFIED, dispatch a researcher to verify or remove it
2. **Genuine issues** — if challengers found real problems, dispatch a new research round → back to Phase 2b
3. **Agreement** — if both challengers AGREE the approach is sound, proceed to Phase 3
4. **Counter-proposals** — if a counter-proposal is clearly better, adopt it and re-validate

**Never present unvetted findings to the user.** All claims must be verified.

## Phase 3: Resolve All Ambiguities

After researchers report back AND challengers have agreed on the approach:

1. **List every open question** — anything the researchers couldn't answer or disagreed on
2. **Ask the user** (via AskUserQuestion) to resolve each one — do NOT guess, do NOT assume
3. **Present the plan via ExitPlanMode** with:
   - **Goal**: what we're doing and why
   - **Research Decisions**: callers, blast radius, patterns to reuse, edge cases
   - **Plan**: ordered steps with checkboxes

ExitPlanMode is the approval gate. Once the user accepts, hand off to `execution.md` — no further "should I proceed?" check.

## Research completeness checklist

Research is NOT complete if any of these are true:
- [ ] Callers were not traced
- [ ] No search for existing patterns
- [ ] Edge cases not identified
- [ ] Assumptions not validated with data
- [ ] Open questions remain
- [ ] No blast radius assessment
- [ ] References not verified (file paths, functions cited without confirming they exist)
- [ ] No challenge round completed
- [ ] Challengers did not agree

If any box is checked, research is incomplete. Go back and fill the gaps before surfacing a plan.
