#!/bin/sh
# Wire the unslop style check into ~/.claude/settings.json Stop hooks.
#
# The hook script itself arrives as a plain dotfile, but the wiring lives in
# settings.json, which some machines keep outside chezmoi (the devvm holds an
# API key there at mode 0600 and is listed in .chezmoiignore). Without this the
# script would land and never run, which fails quietly.
#
# Idempotent and additive: it appends nothing when the entry is already there,
# and leaves every other key untouched.
set -eu

SETTINGS="$HOME/.claude/settings.json"
[ -f "$SETTINGS" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

python3 - "$SETTINGS" "$HOME/.claude/hooks/unslop-check.py" <<'PY'
import collections, json, os, sys

settings, hook = sys.argv[1], sys.argv[2]
if not os.path.exists(hook):
    sys.exit(0)

try:
    with open(settings) as fh:
        data = json.load(fh, object_pairs_hook=collections.OrderedDict)
except (OSError, ValueError):
    sys.exit(0)

command = f"python3 {hook}"
stop = data.setdefault("hooks", {}).setdefault("Stop", [])
if any(command in h.get("command", "") for m in stop for h in m.get("hooks", [])):
    sys.exit(0)

stop.insert(0, {"hooks": [{"type": "command", "command": command, "timeout": 10}]})
mode = os.stat(settings).st_mode & 0o777
tmp = settings + ".unslop-tmp"
with open(tmp, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
os.chmod(tmp, mode)
os.replace(tmp, settings)
print("wired unslop-check.py into the Stop hooks")
PY
