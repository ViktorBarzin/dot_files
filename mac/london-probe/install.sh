#!/bin/sh
# Install or update the London internet-drop probe as a launchd agent.
# Run on the Mac from this directory: ./install.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
dest="$HOME/.local/share/london-probe"
label=me.viktorbarzin.london-probe
plist="$HOME/Library/LaunchAgents/$label.plist"

(cd "$here" && /usr/bin/python3 -m unittest -q test_london_probe)

mkdir -p "$dest" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cp "$here/london_probe.py" "$dest/london_probe.py"
sed "s#__HOME__#$HOME#g" "$here/$label.plist" >"$plist"

launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
launchctl print "gui/$(id -u)/$label" | grep -E "state|pid" | head -3
