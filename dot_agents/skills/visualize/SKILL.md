---
name: visualize
description: Render a design doc, HTML page, SVG, or chart as an image shown INLINE in the chat. Rasterizes the visual to PNG and publishes it to Nextcloud as an unguessable public link, then emits a markdown image that clients like T3 Code render inline. Use when the user asks to "visualize", "diagram", "render", "show me", "draw", or "map out" something, or wants an HTML/SVG/design-doc shown inline rather than as raw code. Triggers on visualizing markdown/HTML design docs, architecture or flow diagrams, dashboards, or any .html/.svg/.png the user wants to view in-conversation.
---

# Visualize — inline images via Nextcloud

Markdown chat clients render `![](https://…)` **images** inline — but NOT raw HTML/SVG, `data:` URIs, or LAN-only URLs. This skill turns any HTML/SVG/PNG into an inline image by rasterizing it and publishing it as a Nextcloud public link.

## Quick start

```bash
~/.claude/skills/visualize/scripts/viz-publish.sh <file.html|.svg|.png> [--title "Caption"]
```

It prints **one markdown-image line per tile** — a single line for normal-shaped images, several for tall ones (auto-split, see Notes). **Post every line it prints, verbatim and in order**; image-rendering clients (e.g. T3 Code) show them inline. To visualize a markdown design doc, first render it to a self-contained `.html` (your own styling), then pass the `.html`.

## How it works
1. Rasterize HTML/SVG → PNG via headless Chrome (isolated `--user-data-dir`, so it works even when you already have Chrome open). Gentle `-fuzz 1% -trim` + a `TRIM_MARGIN` border so the first line isn't clipped/flush. PNGs pass through untouched.
2. Split tall PNGs into stacked tiles (each ≤ `MAX_TILE_ASPECT`×width); normal-shaped images stay one image.
3. Read Nextcloud creds from Vault `<path>` (find it with `homelab vault kv list secret`) (app-password).
4. WebDAV-upload each tile to `/_viz/` + create a public share (`shareType=3`), then warm its preview.
5. Emit one `![title (i/n)](…/index.php/apps/files_sharing/publicpreview/<token>?x=4096&y=4096&a=true)` per tile — served `image/png`, **inline, no redirect** (see Notes).

## Prerequisites (the script checks these and fails loudly)
- `VAULT_ADDR=https://vault.viktorbarzin.me` + an authenticated token (`vault login -method=oidc`). The token lives in `~/.vault-token` but the **addr is not set in non-interactive shells** — that's the usual "no Vault access" red herring; the script defaults it.
- `google-chrome`/`chromium` (HTML/SVG input only) + ImageMagick `convert`/`identify` (HTML/SVG trimming, and splitting tall images of any type).
- `curl`, `jq`, and network reachability to `nextcloud.viktorbarzin.me`.

## Notes
- **Surface**: renders inline only in clients that render markdown images (T3 Code, claude.ai). The plain Claude Code terminal/TUI shows it as a link — expected, not a bug.
- **Why PNG**: Nextcloud serves uploaded SVG as `text/plain` + `nosniff`, which `<img>` refuses; PNG comes back `image/png` and renders. Don't "optimize" by uploading SVG.
- **Why publicpreview, not `/download`**: since Nextcloud 32.x, `/s/<token>/download` answers **303 → `public.php/dav`** with `Content-Disposition: attachment`. Browsers render that fine in an `<img>`, but T3 Code's image fetch does **not** (it won't follow the redirect / refuses `attachment`) → blank. The `publicpreview` endpoint returns **200 `image/png`, `inline`, no redirect** — what renders. It caps at `PREVIEW_MAX` px, but that never bites because tiles are always smaller (so previews are full-res). This regressed silently on a Keel image bump — if images go blank again, re-check `/download`'s headers first.
- **Why the trim margin**: the old `-fuzz 3% -trim` shaved the anti-aliased top of the first line and left content flush against the edge (looked "cropped"). Now: `-fuzz 1%` + a `TRIM_MARGIN`-px border of the detected background.
- **Tall images → tiles**: T3 Code (and similar clients) cap inline-image height (`max-height` + `object-fit:cover`), so a tall image shows only its top slice. The skill serves the full image — the crop is purely client-side render. Fix: anything taller than `MAX_TILE_ASPECT`×width (default `0.5625` = 16:9, the confirmed-safe shape) is sliced into contiguous, non-overlapping stacked tiles, each published as its own inline image — so the whole thing renders, full-resolution, no content lost. Normal-shaped images are untouched (single image). Raise the cap for fewer/taller tiles if your client tolerates them: `--max-aspect 1.0` (or `MAX_TILE_ASPECT=1.0`).
- **Security**: links are unguessable but internet-reachable — keep content secret-free, or password-protect the share for sensitive diagrams. The TTL below bounds the exposure window.
- **TTL**: shares **auto-expire after 30 days** (`--expire DAYS`, `0`=never) — so inline images in *old* conversations stop rendering after that, by design (these are ephemeral). Each publish also keeps only the **newest 50** files in `/_viz` (`--keep N`, `0`=off). Manual sweep: `viz-publish.sh --prune [KEEP]`.
- **Other users / headless agents**: copy this skill into their `~/.claude/skills/`; their env needs chrome + Vault read on `<path>` (find it with `homelab vault kv list secret`) + NC reachability.
- **Tests**: `bash scripts/test-viz-publish.sh` (pure-function + arg-validation units).
