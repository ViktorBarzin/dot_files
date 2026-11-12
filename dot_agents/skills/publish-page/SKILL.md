---
name: publish-page
description: Publish a finalized plan, spec or design doc as a page at pages.viktorbarzin.me, or re-publish one that changed. Use when a substantive design doc is final, a grilling session ends in one, or Viktor asks to publish a doc.
argument-hint: "<path/to/doc.md> [draft|approved|executing|done]"
---

# Publish a page

What to publish: finalized, substantive plans, specs and designs, from a
grilling session or written directly, and any doc Viktor asks for. Not research
output, brainstorming, progress snapshots or throwaway notes, and never a
sensitive personal or financial analysis (those stay in chat). Re-publish when
the doc materially changes: a revision, a status change, progress worth seeing.
Hand Viktor the URL; it is part of the deliverable. Publish here only, never to
claude.ai Artifacts or another vendor-hosted page: 3D viewers, decks, charts and
other interactive work belong here too (see "Visual and interactive work").

The markdown stays canonical wherever it lives (any repo — infra docs/plans, a
project repo). Publishing renders a snapshot into `~/code/pages`, a clone of the
private Forgejo repo `viktor/pages` (the pages/ subdir of the monorepo until
2026-11-03), and pushes; the site serves that repo at git HEAD, so **the push
is the publish**.

**Per-user layout (2026-07-26):** the site serves per-user private spaces.
Viktor's pages live in `~/code/pages/wizard/` (served at the
`pages.viktorbarzin.me` root for him); a `shared/` area is visible to everyone
with access. Other devvm users get their own `<user>/`. Assets are shared at
`assets/` (served via a `/assets/*` carve-out) — pages reference them as
absolute `/assets/...`.

1. **Diagram check, before rendering:** a doc with architecture, data flow,
   sequencing, or timeline content is EXPECTED to carry at least one
   ```` ```mermaid ```` fence (flowchart TD / sequence / gantt — they render
   client-side, dark-mode aware + palette-themed, and natively on GitHub). Viktor
   reviews on a PHONE: prefer portrait-friendly `flowchart TD` / sequence.
   Trivial docs stay text-only.

2. **Visual vocabulary** (the renderer supports these — lean on them):
   - **Callouts:** GitHub-native `> [!NOTE|TIP|IMPORTANT|WARNING|CAUTION]` →
     tinted boxes with an icon. Use for asides, risks, gotchas.
   - **Stat tiles:** a ```` ```stats ```` fence, one `value | label` per line →
     a row of number tiles. Use for key figures (costs, dates, counts).
   - **Diagram type by content:** flowchart TD (process/architecture, phone-
     friendly) · sequence (interactions over time) · gantt (timelines/phases) ·
     state (state machines) · ER (data models). Tables render inline to ~8
     columns; wider ones scroll.

3. **Render:**

   ```sh
   python3 ~/code/pages/tools/render.py <source.md> --pages-dir ~/code/pages/wizard --status <status>
   ```

   - `--pages-dir ~/code/pages/wizard` = Viktor's private space (default target).
     Use `~/code/pages/shared` for a team-visible page.
   - Writes `<date>-<slug>.html` (date from the source filename when it starts
     `YYYY-MM-DD-`, else today) + regenerates the target dir's `index.html`.
   - `--status`: `draft` | `approved` | `executing` | `done`. Pick what's true
     *now*.

4. **Look at it before you commit** (execution.md §4 — a rendered page is not
   verified by having been rendered). `pages.viktorbarzin.me` is owner-gated and
   403s every automated client, in-cluster included, so serve the tree locally:

   ```sh
   PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')
   cd ~/code/pages && python3 -m http.server "$PORT" --bind 127.0.0.1 &
   # from the pages ROOT, or /assets/* 404s and the page looks unstyled.
   # a free port, not a fixed 8099: the box is shared and someone else may hold it
   ```

   Then drive `http://127.0.0.1:$PORT/<user>/<date>-<slug>.html` and screenshot
   it. Pass a **plain relative filename**: the Playwright MCP refuses any path
   outside its allowed roots, which are the session's working directory, so an
   absolute path into `/tmp` comes back as "File access denied". Read back the
   path it reports. A browser call failing with `Target page, context or browser
   has been closed` means the server's browser wedged, not that the page is
   broken: `sudo systemctl restart playwright-mcp@wizard` and retry (2026-09-12).
   Check the things that
   silently break: mermaid fences actually rendering as diagrams, inline `<svg>`
   charts actually drawing rather than leaving a tall empty gap, tables not
   overflowing, stat tiles, and zero console errors. Kill the server after.

   A tall blank band where a picture belongs means the SVG element was cut in
   half. Grep the output for `<p>` or `</p>` between `<svg` and `</svg>` — none
   should be there.

5. **Commit + push the pages repo** (stage by name — never `add -A`):

   ```sh
   git -C ~/code/pages add wizard/<date>-<slug>.html wizard/index.html
   git -C ~/code/pages commit -m "pages: publish <title> (<status>)"   # body: why
   git -C ~/code/pages push origin master
   ```

   - Non-fast-forward → `git -C ~/code/pages pull --rebase origin master`, push again.
   - Docs-only single commit, allowed straight to master from a clean checkout.

6. **Hand over the URL** — part of the deliverable:
   `https://pages.viktorbarzin.me/<date>-<slug>.html` (index:
   `https://pages.viktorbarzin.me/`). ~60s to appear (git-sync serves on push).
   Owner-gated behind Authentik (per-user private). Old `plans.viktorbarzin.me/…`
   URLs 301-redirect here, so previously-shared links still resolve.

7. **Re-publish on material change:** same command + updated status; same source
   → same filename, so the page + index entry update in place.

## Visual and interactive work (since 2026-11-12)

Everything an Artifact used to carry goes here instead, through
`homelab pages publish` (any user, own Space; `--shared` for the team):

| What | Publish | Notes |
|---|---|---|
| A doc | `homelab pages publish doc.md` | as above |
| A slide deck | `doc.md` with front matter `deck: true` | one slide per `---` line; reveal.js; "PDF" link prints it |
| A chart in a doc | a ```` ```chart ```` fence holding a Chart.js config (JSON with `type` and `data`) | a bad block fails the publish with a 400 |
| One HTML page (a 3D viewer, an HTML deck, a free-form chart) | `homelab pages publish page.html` | scripts and CDNs work; vendored libs at `/assets/` (below) |
| A page with its own images, models, data, clips | `homelab pages publish dir/` | a **Bundle**: `index.html` or `index.md` at the top, relative paths for the rest; 10 MiB per file, 25 MiB per publish |
| A link that opens without login | add `--public`, or `homelab pages share <page URL>` | prints `https://pages.viktorbarzin.me/p/<random>/`; `homelab pages unshare <page>` revokes it |

Pages run in a sandboxed frame (infra ADR-0042): page scripts get no cookies,
no `localStorage`/`sessionStorage`/`IndexedDB` and no service worker, and a
single page cannot load relative files (put them in a Bundle). Vendored copies,
listed in `~/code/pages/assets/VERSIONS.md`:

```html
<script type="importmap">{"imports":{"three":"/assets/three-0.187.0/three.module.js","three/addons/":"/assets/three-0.187.0/addons/"}}</script>
<script src="/assets/chart-4.6.1/chart.umd.min.js"></script>
<link rel="stylesheet" href="/assets/reveal-6.0.2/reveal.css"><script src="/assets/reveal-6.0.2/reveal.js"></script>
```

The same file or directory name updates the same page on any later day, and
keeps its public link. Check a Bundle or HTML page by opening the file locally
before publishing; `homelab pages preview` covers markdown only. `?raw` on a
page URL shows it outside the frame (for printing).

## Plans: blocks, not prose (since 2026-11-12)

A plan, spec or design starts from the plan template,
`curl -s https://pages.viktorbarzin.me/assets/plan-template.md` (also
`~/code/pages/assets/plan-template.md`). Each kind of change gets one fenced YAML block and one caption
line; the renderer draws it and refuses a block that does not validate, naming
it. A plan has no open questions: settle each one first, by investigation
for a fact or by the grilling skill for a decision, and record the answer in
a decision block; the renderer refuses a plan with an "Open questions"
section. Keep as text only: the two-sentence why, the one-line why
on each decision, and exact commands. Budget: about 600 words of prose outside
the blocks; above that the publish prints a warning (it still publishes).

| Block | For | Shape |
|---|---|---|
| ```` ```topology ```` | the system with the change on it | `nodes` (id, label, note, group, `state: new\|changed\|removed\|same`, `risk: high\|medium\|low`, `scope: out`), `edges` (from, to, label, state), `checks` (`node`, text, `status: passed\|failed\|open`), `left_out`; at most 12 nodes |
| ```` ```decision ```` | a choice | question, options (name, note, one `chosen: true`), why; a list for several |
| ```` ```config ```` | settings that change | rows of key, where, old, new |
| ```` ```numbers ```` | figures before and after | rows of label, before, after, `better: false` when it got worse |
| ```` ```timeline ```` | order of work | steps of when, what, `rollback`, and one `ponr: true` |

Write `node:` for a check, never `on:`: YAML reads a bare `on` as true.

Write the prose in ASD-STE100 Simplified Technical English (Issue 9, 2025),
the standard for aircraft maintenance manuals: one topic per paragraph, at
most 25 words in a description and 20 in an instruction, imperative
instructions, active voice, simple tenses, one word for one thing, lists
instead of long sentences. The template lists all the rules. The publish
warns on each sentence over 25 words; fix them before you hand over the URL.

In a topology, mark only real changes. The renderer draws unchanged parts
as a grey background and each change as a solid block, so a picture where
every part is "changed" says nothing.

## Lifetimes

Pages, Bundles and public links published or shared from 2026-11-12 on are
deleted 90 days after their last publish or share (git keeps a copy). Pass
`--expires never` for a page that must stay (a reference doc, a runbook-like
design), `--expires 30d` for something short-lived. `homelab pages unpublish
<page>` deletes one now.

The URL is the DELIVERABLE — never hand over a screenshot or a rasterised page
in its place. Looking at the page yourself is VERIFICATION, which is required
(execution.md §4) and is a different thing. Secrets never belong in pages.
