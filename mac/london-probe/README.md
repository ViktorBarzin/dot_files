# London probe

Detects internet drops seen from this Mac while it is on the London Flint's
networks and reports each one to Loki (`{job="london-drops", source="mac"}`).
Drops of the Mac's own Wi-Fi or DNS post one Slack message each; upstream drops
are reported by the Flint's own probe. Design and settings live in the infra
repo: `docs/plans/2026-09-27-london-flint-main-router.md` and
`docs/architecture/london-site.md`.

```sh
./install.sh                      # runs the tests, installs the launchd agent
tail -f ~/Library/Logs/london-probe.log
```

Uninstall: `launchctl bootout gui/$(id -u)/me.viktorbarzin.london-probe` and
delete `~/Library/LaunchAgents/me.viktorbarzin.london-probe.plist`.
