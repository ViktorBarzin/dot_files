#!/usr/bin/env bash
#
# viz-publish — rasterize a visual to PNG, publish it to Nextcloud as an
# unguessable public link, and print a ready-to-paste inline markdown image.
#
# Why: chat clients that render markdown images (e.g. T3 Code's react-markdown)
# show `![](https://…)` inline, but NOT raw HTML/SVG, data: URIs, or LAN-only
# URLs. This packages the proven pipeline: rasterize → Nextcloud public share →
# image/png download URL.
#
# Usage:  viz-publish.sh <file.html|.svg|.png> [--title "Caption"] [--expire DAYS] [--keep N] [--max-aspect R]
#         viz-publish.sh --prune [KEEP]      # keep newest KEEP files in /_viz (default 1000)
#
# TTL: shares auto-expire after EXPIRE_DAYS (default 365, 0=never); each publish
# also keeps only the newest AUTO_PRUNE_KEEP files in /_viz (default 1000, 0=off).
#
# Tall visuals are auto-split into stacked tiles (each <= MAX_TILE_ASPECT of its
# width) so clients that crop tall inline images (T3 Code) render them in full.
#
# stdout: one `![title](url)` line per tile (a single line for normal-shaped images).
# Env overrides: VAULT_ADDR, NC_BASE, NC_FOLDER, VAULT_NC_PATH, CHROME_BIN,
#                EXPIRE_DAYS, AUTO_PRUNE_KEEP, MAX_TILE_ASPECT, PREVIEW_MAX, TRIM_MARGIN.
set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-https://vault.viktorbarzin.me}"; export VAULT_ADDR
NC_BASE="${NC_BASE:-https://nextcloud.viktorbarzin.me}"
NC_FOLDER="${NC_FOLDER:-_viz}"
VAULT_NC_PATH="${VAULT_NC_PATH:-secret/nextcloud/caldav}"
CHROME_BIN="${CHROME_BIN:-}"
EXPIRE_DAYS="${EXPIRE_DAYS:-365}"
AUTO_PRUNE_KEEP="${AUTO_PRUNE_KEEP:-1000}"
# Tall images get cropped by chat clients (T3 Code etc.) that cap inline-image
# height (max-height + object-fit:cover). Slice anything taller than W*MAX_TILE_ASPECT
# into stacked tiles so the whole thing renders. 0.5625 = 16:9, the one confirmed-safe
# shape; raise via --max-aspect for fewer/taller tiles if your client tolerates them.
MAX_TILE_ASPECT="${MAX_TILE_ASPECT:-0.5625}"
# Serve via Nextcloud's publicpreview endpoint, not /s/<tok>/download: since NC 32.x
# /download answers 303->public.php/dav with Content-Disposition: attachment, which chat
# clients (T3 Code) won't render inline. publicpreview is 200 image/png, inline, no redirect.
# It caps previews at PREVIEW_MAX px — fine because tiles are always well under it (full-res).
PREVIEW_MAX="${PREVIEW_MAX:-4096}"
# Margin (px) added back after trimming rasterized HTML/SVG, so content isn't flush/clipped
# against the top edge (the old aggressive trim shaved the first line).
TRIM_MARGIN="${TRIM_MARGIN:-40}"

err(){ echo "viz-publish: $*" >&2; }
die(){ err "$*"; exit 1; }

# ---- pure helpers (unit-tested) -------------------------------------------
detect_type(){ case "${1,,}" in *.html|*.htm) echo html;; *.svg) echo svg;; *.png) echo png;; *) echo unsupported;; esac; }
nc_download_url(){ echo "$NC_BASE/index.php/apps/files_sharing/publicpreview/$1?x=$PREVIEW_MAX&y=$PREVIEW_MAX&a=true"; }
md_image(){ echo "![${1}](${2})"; }
expire_date(){ if [ "${1:-0}" -gt 0 ] 2>/dev/null; then date -u -d "+${1} days" +%Y-%m-%d; fi; }  # empty when 0/unset
find_chrome(){
  [ -n "$CHROME_BIN" ] && { echo "$CHROME_BIN"; return 0; }
  local c; for c in google-chrome google-chrome-stable chromium chromium-browser; do
    command -v "$c" >/dev/null 2>&1 && { echo "$c"; return 0; }
  done
  return 1
}
# tile_plan W H MAXASPECT -> one "offset height" line per horizontal strip.
# Strips are contiguous, non-overlapping, cover [0,H], each height <= floor(W*MAXASPECT).
# Emits a single "0 H" when the image is already within the aspect cap (no split).
tile_plan(){
  local W="$1" H="$2" asp="$3" maxH n baseH i y th
  maxH="$(awk -v w="$W" -v a="$asp" 'BEGIN{m=int(w*a); print (m<1?1:m)}')"
  if [ "$H" -le "$maxH" ]; then echo "0 $H"; return 0; fi
  n="$(awk -v h="$H" -v m="$maxH" 'BEGIN{printf "%d", int((h+m-1)/m)}')"   # ceil(H/maxH)
  baseH="$(awk -v h="$H" -v n="$n" 'BEGIN{printf "%d", int((h+n-1)/n)}')"  # ceil(H/n) -> even strips
  for (( i=0; i<n; i++ )); do
    y=$(( i * baseH )); th="$baseH"
    [ $(( y + th )) -gt "$H" ] && th=$(( H - y ))
    [ "$th" -le 0 ] && break
    echo "$y $th"
  done
}

# ---- rasterize html/svg -> png --------------------------------------------
rasterize(){ # $1=infile $2=type $3=outpng
  local infile="$1" type="$2" out="$3" chrome profile
  chrome="$(find_chrome)" || die "no chrome/chromium found to rasterize $type — install one or pass a .png"
  command -v convert >/dev/null 2>&1 || die "ImageMagick 'convert' required for trimming"
  profile="$(mktemp -d)"  # isolated profile — avoids the singleton-lock clash when the user already has Chrome open
  local common=(--headless --no-sandbox --disable-gpu --disable-dev-shm-usage --hide-scrollbars --force-device-scale-factor=1.5 --user-data-dir="$profile")
  if [ "$type" = html ]; then
    local raster; raster="$(mktemp --suffix=.html)"
    python3 - "$infile" "$raster" <<'PY'
import sys
src=open(sys.argv[1]).read()
inj='<style>*{animation:none!important;transition:none!important}.reveal{opacity:1!important;transform:none!important}html,body{background:#0a0e14!important;background-image:none!important}</style>'
open(sys.argv[2],'w').write(src.replace('</head>',inj+'</head>',1) if '</head>' in src else inj+src)
PY
    "$chrome" "${common[@]}" --virtual-time-budget=4000 --window-size=1200,8000 --screenshot="$out.raw.png" "file://$raster" >/dev/null 2>&1 \
      || { rm -f "$raster"; die "headless render failed (html)"; }
    # gentle trim (3% shaved the anti-aliased top of the first line) + restore a margin so
    # content isn't flush/clipped against the edge; border color = the rendered background.
    local bg; bg="$(convert "$out.raw.png" -format '%[pixel:p{0,0}]' info: 2>/dev/null)"
    convert "$out.raw.png" -fuzz 1% -trim +repage -bordercolor "${bg:-#0a0e14}" -border "$TRIM_MARGIN" "$out"
    rm -f "$out.raw.png" "$raster"
  else # svg — size the window to the SVG's intrinsic dimensions (no margins, no trim needed)
    local dims w h
    dims="$(python3 - "$infile" <<'PY'
import re,sys
tag=(re.search(r'<svg[^>]*>', open(sys.argv[1]).read(), re.I) or [None])
tag=tag.group(0) if hasattr(tag,'group') else ''
def num(a):
    m=re.search(a+r'\s*=\s*"([0-9.]+)', tag); return float(m.group(1)) if m else 0
w=num('width'); h=num('height')
if not (w and h):
    vb=re.search(r'viewBox\s*=\s*"([\d.\s,]+)"', tag)
    if vb:
        p=re.split(r'[\s,]+', vb.group(1).strip())
        if len(p)==4: w=w or float(p[2]); h=h or float(p[3])
print(int(w), int(h))
PY
)"
    w="$(echo "$dims" | awk '{print $1}')"; h="$(echo "$dims" | awk '{print $2}')"
    if [ "${w:-0}" -gt 0 ] && [ "${h:-0}" -gt 0 ]; then
      "$chrome" "${common[@]}" --window-size="${w},${h}" --screenshot="$out" "file://$infile" >/dev/null 2>&1 \
        || die "headless render failed (svg)"
    else
      "$chrome" "${common[@]}" --window-size=1400,2000 --screenshot="$out.raw.png" "file://$infile" >/dev/null 2>&1 \
        || die "headless render failed (svg)"
      convert "$out.raw.png" -fuzz 2% -trim +repage "$out"; rm -f "$out.raw.png"
    fi
  fi
  rm -rf "$profile"
}

# ---- split a tall png into stacked tiles -----------------------------------
tile_image(){ # $1=srcpng $2=outdir -> prints tile png paths (one per line, in order)
  local src="$1" outdir="$2" dims W H plan i=0 y th out
  dims="$(identify -format '%w %h' "$src" 2>/dev/null | head -1)" || dims=""
  W="${dims% *}"; H="${dims#* }"
  { [ "${W:-0}" -gt 0 ] && [ "${H:-0}" -gt 0 ]; } 2>/dev/null || { echo "$src"; return 0; }  # can't measure -> pass through
  plan="$(tile_plan "$W" "$H" "$MAX_TILE_ASPECT")"
  [ "$(printf '%s\n' "$plan" | wc -l)" -gt 1 ] || { echo "$src"; return 0; }                 # within cap -> single
  command -v convert >/dev/null 2>&1 || die "ImageMagick 'convert' required to split tall images (or raise --max-aspect)"
  while read -r y th; do
    i=$(( i + 1 )); out="$outdir/tile-$i.png"
    convert "$src" -crop "${W}x${th}+0+${y}" +repage "$out" || die "tile crop failed at +0+$y"
    echo "$out"
  done <<< "$plan"
}

# ---- nextcloud helpers -----------------------------------------------------
_nc_creds(){ # sets NCUSER, NCPASS
  command -v vault >/dev/null 2>&1 || die "vault CLI required"
  command -v jq >/dev/null 2>&1 || die "jq required"
  vault token lookup >/dev/null 2>&1 || die "Vault not authenticated (VAULT_ADDR=$VAULT_ADDR). Run: vault login -method=oidc"
  NCUSER="$(vault kv get -field=username "$VAULT_NC_PATH")" || die "cannot read $VAULT_NC_PATH (username)"
  NCPASS="$(vault kv get -field=app_password "$VAULT_NC_PATH")" || die "cannot read $VAULT_NC_PATH (app_password)"
}

publish(){ # $1=localpng $2=remote_basename $3=title  -> prints md image to stdout
  command -v curl >/dev/null 2>&1 || die "curl required"
  local NCUSER NCPASS; _nc_creds
  local davbase="$NC_BASE/remote.php/dav/files/$NCUSER"
  curl -fsS -u "$NCUSER:$NCPASS" -X MKCOL "$davbase/$NC_FOLDER" >/dev/null 2>&1 || true  # 405 if it already exists
  local remote="/$NC_FOLDER/$2" code
  code="$(curl -sS -o /dev/null -w '%{http_code}' -u "$NCUSER:$NCPASS" -T "$1" "$davbase$remote")"
  [[ "$code" =~ ^20 ]] || die "WebDAV PUT failed (HTTP $code) for $remote"

  local ocs="$NC_BASE/ocs/v2.php/apps/files_sharing/api/v1/shares" resp tok exp
  exp="$(expire_date "$EXPIRE_DAYS")"
  _create(){ # $1=expireDate(optional)
    local a=(-u "$NCUSER:$NCPASS" -H 'OCS-APIRequest: true' -H 'Accept: application/json' -d "path=$remote" -d 'shareType=3' -d 'permissions=1')
    [ -n "$1" ] && a+=(-d "expireDate=$1")
    curl -sS "${a[@]}" "$ocs"
  }
  resp="$(_create "$exp")"; tok="$(echo "$resp" | jq -r '.ocs.data.token // empty')"
  if [ -z "$tok" ] && [ -n "$exp" ]; then              # expiry maybe rejected (admin cap) -> retry without
    resp="$(_create "")"; tok="$(echo "$resp" | jq -r '.ocs.data.token // empty')"; exp=""
  fi
  if [ -z "$tok" ]; then                                 # already shared -> reuse existing public link
    tok="$(curl -sS -u "$NCUSER:$NCPASS" -H 'OCS-APIRequest: true' -H 'Accept: application/json' \
            "$ocs?path=$remote" | jq -r '.ocs.data[]?|select(.share_type==3)|.token' | head -1)"
  fi
  [ -n "$tok" ] || die "share creation failed: $(echo "$resp" | jq -rc '.ocs.meta // empty')"

  local url; url="$(nc_download_url "$tok")"
  curl -fsS -o /dev/null --max-time 30 "$url" >/dev/null 2>&1 || true  # warm the preview so the client's first load is instant
  err "published: $url${exp:+ (expires $exp)}"
  md_image "$3" "$url"

  [ "${AUTO_PRUNE_KEEP:-0}" -gt 0 ] 2>/dev/null && prune "$AUTO_PRUNE_KEEP" >/dev/null 2>&1 || true  # best-effort housekeeping
}

prune(){ # keep newest $1 (default 1000) files in /_viz, delete the rest
  local keep="${1:-1000}" NCUSER NCPASS; _nc_creds
  local davbase="$NC_BASE/remote.php/dav/files/$NCUSER"
  local names; names="$(curl -sS -u "$NCUSER:$NCPASS" -X PROPFIND -H 'Depth: 1' "$davbase/$NC_FOLDER/" 2>/dev/null \
    | grep -oE "$NC_FOLDER/[^<]+\.png" | sed "s#^$NC_FOLDER/##" | sort -u)"
  [ -n "$names" ] || { err "prune: nothing in /$NC_FOLDER"; return 0; }
  local total; total="$(echo "$names" | wc -l)"
  [ "$total" -gt "$keep" ] || { err "prune: $total file(s) ≤ keep=$keep, nothing to do"; return 0; }
  err "prune: $total file(s) in /$NC_FOLDER, keeping newest $keep"
  # basenames embed YYYYMMDD-HHMMSS, so lexicographic sort == chronological; delete all but newest $keep
  echo "$names" | head -n "-${keep}" | while IFS= read -r n; do
    [ -n "$n" ] || continue
    curl -fsS -u "$NCUSER:$NCPASS" -X DELETE "$davbase/$NC_FOLDER/$n" >/dev/null 2>&1 && err "  deleted $n" || err "  (skip $n)"
  done
}

main(){
  [ $# -ge 1 ] || die "usage: viz-publish <file.html|.svg|.png> [--title T] [--expire DAYS] [--keep N] [--max-aspect R] | --prune [KEEP]"
  local file="" title=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --prune)  shift; prune "${1:-1000}"; exit 0;;
      --title)  title="${2:-}"; shift 2;;
      --expire) EXPIRE_DAYS="${2:-365}"; shift 2;;
      --keep)   AUTO_PRUNE_KEEP="${2:-1000}"; shift 2;;
      --max-aspect) MAX_TILE_ASPECT="${2:-0.5625}"; shift 2;;
      -*) die "unknown flag: $1";;
      *) file="$1"; shift;;
    esac
  done
  [ -n "$file" ] || die "no input file given"
  [ -f "$file" ] || die "file not found: $file"
  local type; type="$(detect_type "$file")"
  [ "$type" != unsupported ] || die "unsupported type: $file (want .html/.svg/.png)"
  [ -n "$title" ] || title="$(basename "${file%.*}")"
  local base ts remote_name srcpng cleanup=""
  base="$(basename "${file%.*}")"; ts="$(date +%Y%m%d-%H%M%S)"; remote_name="${base}-${ts}.png"
  if [ "$type" = png ]; then
    srcpng="$file"
  else
    srcpng="$(mktemp --suffix=.png)"; cleanup="$srcpng"
    rasterize "$file" "$type" "$srcpng"
  fi
  # split tall visuals into stacked tiles so cropping clients (T3 Code) show them in full
  local tiledir tiles_out tiles=() n i=0 t cap rn
  tiledir="$(mktemp -d)"
  tiles_out="$(tile_image "$srcpng" "$tiledir")"   # fail-fast: set -e aborts before publish if tiling errors
  while IFS= read -r t; do [ -n "$t" ] && tiles+=("$t"); done <<< "$tiles_out"
  n="${#tiles[@]}"
  [ "$n" -ge 1 ] || die "tiling produced no images"
  for t in "${tiles[@]}"; do
    i=$(( i + 1 ))
    if [ "$n" -gt 1 ]; then cap="$title ($i/$n)"; rn="${base}-${ts}-p${i}of${n}.png"
    else cap="$title"; rn="$remote_name"; fi
    publish "$t" "$rn" "$cap"
  done
  rm -rf "$tiledir"
  [ -n "$cleanup" ] && rm -f "$cleanup" || true
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then main "$@"; fi
