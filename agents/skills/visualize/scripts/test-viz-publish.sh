#!/usr/bin/env bash
# Unit tests for viz-publish.sh pure functions + arg-validation.
# Network/Vault/Nextcloud paths are covered by a live smoke test, not here.
SCRIPT="$(cd "$(dirname "$0")" && pwd)/viz-publish.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT missing"; exit 1; }

# Source for pure functions (main is guarded by BASH_SOURCE check, won't run).
# shellcheck disable=SC1090
source "$SCRIPT"
set +euo pipefail   # the sourced script enables strict mode; relax it for the harness

pass=0; fail=0
ok(){ if eval "$2"; then echo "ok   - $1"; pass=$((pass+1)); else echo "FAIL - $1"; fail=$((fail+1)); fi; }

ok "detect html"          '[ "$(detect_type a.html)" = html ]'
ok "detect htm"           '[ "$(detect_type a.htm)" = html ]'
ok "detect svg uppercase" '[ "$(detect_type b.SVG)" = svg ]'
ok "detect png"           '[ "$(detect_type c.png)" = png ]'
ok "detect unsupported"   '[ "$(detect_type d.txt)" = unsupported ]'
ok "preview url"          '[ "$(nc_download_url TOK)" = "https://nextcloud.viktorbarzin.me/index.php/apps/files_sharing/publicpreview/TOK?x=4096&y=4096&a=true" ]'
ok "md image"             '[ "$(md_image Title http://x)" = "![Title](http://x)" ]'
ok "expire_date format"   '[[ "$(expire_date 30)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]'
ok "expire_date 0 = none" '[ -z "$(expire_date 0)" ]'
ok "find chrome present"  'find_chrome >/dev/null'

# tile_plan: split a tall image into contiguous, non-overlapping horizontal
# strips, each height <= floor(W*MAXASPECT); single "0 H" when no split needed.
ok "tile_plan short -> single"     '[ "$(tile_plan 1280 720 0.6)" = "0 720" ]'
ok "tile_plan at cap -> single"    '[ "$(tile_plan 1280 768 0.6)" = "0 768" ]'   # floor(1280*0.6)=768
ok "tile_plan tall -> 3 strips"    '[ "$(tile_plan 1280 1600 0.6 | wc -l)" -eq 3 ]'
ok "tile_plan first offset is 0"   '[ "$(tile_plan 1280 1600 0.6 | head -1 | cut -d" " -f1)" = 0 ]'
ok "tile_plan covers full height"  'l="$(tile_plan 1280 1600 0.6 | tail -1)"; set -- $l; [ $(( $1 + $2 )) -eq 1600 ]'
ok "tile_plan no strip over cap"   'm="$(tile_plan 1280 4740 0.5625 | cut -d" " -f2 | sort -n | tail -1)"; [ "$m" -le 720 ]'
ok "tile_plan strips contiguous"   'p=0; g=1; while read o h; do [ "$o" -eq "$p" ] || g=0; p=$((o+h)); done < <(tile_plan 1280 1600 0.6); [ "$g" -eq 1 ]'

# arg-validation via subprocess (does not touch the network)
ok "no args -> nonzero"      '! bash "$SCRIPT" >/dev/null 2>&1'
ok "missing file -> nonzero" '! bash "$SCRIPT" /no/such/file.html >/dev/null 2>&1'
ok "bad ext -> nonzero"      'printf x >/tmp/vp_t.$$ && ! bash "$SCRIPT" /tmp/vp_t.$$ >/dev/null 2>&1; r=$?; rm -f /tmp/vp_t.$$; [ $r -eq 0 ]'

echo "----"; echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
