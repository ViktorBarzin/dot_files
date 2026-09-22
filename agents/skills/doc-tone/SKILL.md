---
name: doc-tone
description: >-
  Tone-only revision pass for a document — removes defensive, adversarial, or
  overconfident phrasing while keeping every fact, decision, boundary, number,
  and ask exactly as-is. Use when: doing a tone pass before publishing a plan
  or design; a draft reads as territorial, blaming, dismissive, or over-claims
  its evidence; you want to calibrate confidence to the evidence; or you want a
  blameless, collaborative rewrite. The 7 principles are the default house style
  for every markdown authored; the revision pass is required before publishing
  (publish-page step 3) and invocable on demand as /doc-tone. Keywords:
  tone pass, defensive, adversarial, overconfident, revision, blameless,
  calibrate confidence, loaded language, editorializing.
---

# doc-tone — a tone-only revision pass

Do a tone-only revision of the target document to remove defensive, adversarial,
or overconfident phrasing — while keeping every fact, decision, boundary,
number, and ask exactly as-is.

**This is a tone pass, not a content edit:** don't drop claims, soften
decisions, or blur ownership boundaries. Firm boundaries should still land
firmly — just clear and collaborative rather than territorial. Preserve exact
numbers, their units, and their hedges.

Assume the readers include the people who built the systems being discussed and
the teams being asked to take on work. Write so a reader acting in good faith
wouldn't feel blamed, dismissed, or cornered.

## The 7 principles

1. **Calibrate confidence to the evidence.** State facts as facts and hypotheses
   as hypotheses; where something is unknown, say so plainly (add a short "open
   questions / what we don't know yet" note if the doc asserts more than it can
   prove). Don't present proposed or assumed values as settled.
2. **Cut dismissive or loaded language and insistence phrases** — e.g. "hacky,"
   "firehose," "catch-all," "silently absorbed," "the honest bottleneck," "the
   uncomfortable part," "it writes itself," "routinely misread" (swap in
   whatever your own draft over-reaches with). Replace with neutral, specific
   descriptions of the actual situation.
3. **Reframe boundaries collaboratively.** Where the doc says what we do NOT own
   or won't take on, keep the boundary but state it as scope + how we
   route/partner, not a list of refusals. Avoid framing that implies other teams
   failed ("falls between teams," "no single team owns it") — describe the gap
   neutrally.
4. **Credit existing work.** When noting a limitation of an existing system,
   name the specific gap (what it doesn't do yet) rather than judging the system
   or its authors; acknowledge what it does well where natural.
5. **Drop rhetorical editorializing.** Prefer plain, measured statements over
   persuasive flourishes, rhetorical asides, or "the result is what you'd
   expect."
6. **Use bold sparingly** — only for genuine key terms, not to insist.
7. **Frame the whole thing as a shared problem to solve with the reader**, not a
   case being prosecuted.

## Two modes

**Authoring (the default, every `.md`).** The 7 principles are the house style
for every markdown file written — design docs, plans, specs, ADRs, post-mortems,
RFCs, READMEs, runbooks, skill files, repo docs, issue bodies (global rules →
"Writing style — every markdown I author"). Apply them while drafting rather
than writing a defensive draft and cleaning it up afterwards. No changelog:
there's no prior version to diff against.

**Revising (this skill invoked on an existing doc).** Changelog first, then the
rewrite — see below. This is what `/doc-tone` runs, and what `publish-page`
step 3 requires before rendering.

## Workflow — changelog first, then rewrite

Before rewriting, **list the specific lines you're changing and the tone-tell
each one fixes, so the author can confirm meaning is preserved. Then produce the
revised version.**

This order is deliberate: the changelog is the sign-off surface. It proves the
pass changed tone, not substance — the author can scan it and catch any place a
fact, number, decision, or boundary shifted before the rewrite is accepted.

When a doc was already authored in the house style, the changelog is often short
or empty. Say "no tone changes needed" plainly — an empty changelog is a valid
result, not a reason to invent edits.

## Tone-tell reference

The left column is the loaded phrasing to watch for (the author's own list of
over-reaches). The right column is *suggested* neutral directions, not fixed
substitutions — replace with a specific, accurate description of the actual
situation in context.

| Tone-tell (loaded) | Neutral direction (suggested) |
|---|---|
| "hacky" | name the specific limitation ("relies on X, which breaks if Y") |
| "firehose" | quantify the volume ("~N events/min") |
| "catch-all" | state what it actually covers ("handles cases A, B, C") |
| "silently absorbed" | describe the behavior ("dropped without a log line") |
| "the honest bottleneck" / "the uncomfortable part" | just state the constraint plainly |
| "it writes itself" | describe what's automated and what isn't |
| "routinely misread" | "easy to misread as X; it actually means Y" |
| "falls between teams" / "no single team owns it" | describe the gap neutrally + how it's routed/owned going forward |
| "the result is what you'd expect" | state the actual result |
| bold used to insist | remove the bold; keep it only for genuine key terms |

## Scope

Preserve every fact, number, decision, and boundary — this pass only changes how
things are said. If a change would alter meaning, stop and flag it in the
changelog instead of making it.

Reach (Viktor, 2026-08-08): the principles are the default style for **every
markdown authored**, and the revision pass is required before publishing to
pages. Chat replies and commit messages are out of scope — commit bodies follow
the audit-trail rules instead.
