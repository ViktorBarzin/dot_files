---
name: publish-page
description: Publish a substantive design doc (plan/spec/design) as a styled HTML page at pages.viktorbarzin.me so Viktor can review it from a browser on the go. Use for FINALIZED SUBSTANTIVE design docs — whether from a grilling session (grilling / grill-with-docs / grill-me) or authored directly — and when Viktor explicitly asks to publish a specific doc. NOT for research outputs, raw brainstorming/writing-plans, execution/progress snapshots, or trivial throwaway notes (those stay canonical in their owning repo); the raw plan-mode approval text is not a deliverable, but a finalized substantive plan is; sensitive personal/financial analyses stay inline, never published. Once published, re-publish whenever it materially changes (revision, status change, execution progress worth seeing). grill-with-docs ends with this as its final deliverable step. (Broadened 2026-07-26 from grilling-only to substantive-design-docs for all users; renamed from publish-plan when the site became pages.viktorbarzin.me.)
argument-hint: "<path/to/doc.md> [draft|approved|executing|done]"
---

# Publish a page

The markdown stays canonical wherever it lives (any repo — monorepo docs, infra
docs/plans, a project repo). Publishing renders a snapshot into the monorepo's
`pages/` tree and pushes; the site serves the monorepo at git HEAD, so **the
push is the publish**.

**Per-user layout (2026-07-26):** the site serves per-user private spaces.
Viktor's pages live in `pages/wizard/` (served at the `pages.viktorbarzin.me`
root for him); a `pages/shared/` area is visible to everyone with access. Other
devvm users get their own `pages/<user>/`. Assets are shared at `pages/assets/`
(served via a `/assets/*` carve-out) — pages reference them as absolute
`/assets/...`.

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

3. **doc-tone (required):** run the `/doc-tone` skill on the canonical markdown
   before rendering — a tone pass that strips defensive/overconfident/adversarial
   phrasing while preserving every fact, number, decision, boundary, and ask.
   The changelog comes first (changed lines + the tone-tell each fixes), so the
   author can confirm nothing substantive moved. A doc already authored in the
   house style (global rules → "Writing style") usually needs few or no changes;
   run the pass anyway and report "no tone changes needed" when that's the
   result.

4. **Render:**

   ```sh
   python3 ~/code/pages/tools/render.py <source.md> --pages-dir ~/code/pages/wizard --status <status>
   ```

   - `--pages-dir ~/code/pages/wizard` = Viktor's private space (default target).
     Use `~/code/pages/shared` for a team-visible page.
   - Writes `<date>-<slug>.html` (date from the source filename when it starts
     `YYYY-MM-DD-`, else today) + regenerates the target dir's `index.html`.
   - `--status`: `draft` | `approved` | `executing` | `done`. Pick what's true
     *now*.

5. **Look at it before you commit** (execution.md §4 — a rendered page is not
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

6. **Commit + push the monorepo** (stage by name — never `add -A`):

   ```sh
   git -C ~/code add pages/wizard/<date>-<slug>.html pages/wizard/index.html
   git -C ~/code commit -m "pages: publish <title> (<status>)"   # body: why
   git -C ~/code push origin master
   ```

   - Non-fast-forward → `git -C ~/code pull --rebase origin master`, push again.
   - Docs-only single commit, allowed straight to master from a clean checkout.

7. **Hand over the URL** — part of the deliverable:
   `https://pages.viktorbarzin.me/<date>-<slug>.html` (index:
   `https://pages.viktorbarzin.me/`). ~60s to appear (git-sync serves on push).
   Owner-gated behind Authentik (per-user private). Old `plans.viktorbarzin.me/…`
   URLs 301-redirect here, so previously-shared links still resolve.

8. **Re-publish on material change:** same command + updated status; same source
   → same filename, so the page + index entry update in place.

The URL is the DELIVERABLE — never hand over a screenshot or a rasterised page
in its place. Looking at the page yourself is VERIFICATION, which is required
(execution.md §4) and is a different thing. Secrets never belong in pages.
