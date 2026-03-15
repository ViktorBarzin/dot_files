name: calendar
description: Query and manage Nextcloud calendar events via CalDAV. Use when the user
  asks about their calendar, schedule, events, availability, or wants to create events.
  Triggers on "check my calendar", "what's on my calendar", "any events", "create event",
  "schedule", "am I free", "calendar", "what do I have this week".
---

## Calendar Access

All commands use `bw-vault inject` to securely pass Nextcloud credentials. Passwords never appear in stdout.

### Base Command Pattern
```bash
bw-vault inject "76169a13-9830-48ee-b583-6cc9055ed03c" --as NEXTCLOUD_APP_PASSWORD -- env NEXTCLOUD_USER=admin ~/.venvs/claude/bin/python3 /Users/viktorbarzin/code/infra/.claude/calendar-query.py <command> [options]
```

### Available Commands

#### List all calendars
```bash
bw-vault inject "76169a13-9830-48ee-b583-6cc9055ed03c" --as NEXTCLOUD_APP_PASSWORD -- env NEXTCLOUD_USER=admin ~/.venvs/claude/bin/python3 /Users/viktorbarzin/code/infra/.claude/calendar-query.py list
```

#### Show events for a time period
```bash
# Today's events
bw-vault inject "76169a13-9830-48ee-b583-6cc9055ed03c" --as NEXTCLOUD_APP_PASSWORD -- env NEXTCLOUD_USER=admin ~/.venvs/claude/bin/python3 /Users/viktorbarzin/code/infra/.claude/calendar-query.py today

# Tomorrow
bw-vault inject "76169a13-9830-48ee-b583-6cc9055ed03c" --as NEXTCLOUD_APP_PASSWORD -- env NEXTCLOUD_USER=admin ~/.venvs/claude/bin/python3 /Users/viktorbarzin/code/infra/.claude/calendar-query.py tomorrow

# This week
bw-vault inject "76169a13-9830-48ee-b583-6cc9055ed03c" --as NEXTCLOUD_APP_PASSWORD -- env NEXTCLOUD_USER=admin ~/.venvs/claude/bin/python3 /Users/viktorbarzin/code/infra/.claude/calendar-query.py week

# Next week
bw-vault inject "76169a13-9830-48ee-b583-6cc9055ed03c" --as NEXTCLOUD_APP_PASSWORD -- env NEXTCLOUD_USER=admin ~/.venvs/claude/bin/python3 /Users/viktorbarzin/code/infra/.claude/calendar-query.py events --date "next week"

# This month
bw-vault inject "76169a13-9830-48ee-b583-6cc9055ed03c" --as NEXTCLOUD_APP_PASSWORD -- env NEXTCLOUD_USER=admin ~/.venvs/claude/bin/python3 /Users/viktorbarzin/code/infra/.claude/calendar-query.py month

# Next N days
bw-vault inject "76169a13-9830-48ee-b583-6cc9055ed03c" --as NEXTCLOUD_APP_PASSWORD -- env NEXTCLOUD_USER=admin ~/.venvs/claude/bin/python3 /Users/viktorbarzin/code/infra/.claude/calendar-query.py events --days N
```

#### Custom date range
```bash
# From a specific date
bw-vault inject "76169a13-9830-48ee-b583-6cc9055ed03c" --as NEXTCLOUD_APP_PASSWORD -- env NEXTCLOUD_USER=admin ~/.venvs/claude/bin/python3 /Users/viktorbarzin/code/infra/.claude/calendar-query.py events --date YYYY-MM-DD --days N

# Supported --date values: YYYY-MM-DD, today, tomorrow, week, "this week", "next week", month, "this month"
```

#### Filter by calendar
Add `--calendar "Calendar Name"` to any command. Omit to show all calendars.

#### JSON output
Add `--json` to any command for machine-readable output.

#### Create an event
```bash
bw-vault inject "76169a13-9830-48ee-b583-6cc9055ed03c" --as NEXTCLOUD_APP_PASSWORD -- env NEXTCLOUD_USER=admin ~/.venvs/claude/bin/python3 /Users/viktorbarzin/code/infra/.claude/calendar-query.py create \
  --title "Event Title" \
  --start "YYYY-MM-DD HH:MM" \
  --end "YYYY-MM-DD HH:MM" \
  --calendar "Personal" \
  --location "Location" \
  --description "Description"
```

Start time also accepts relative formats: `"today 14:00"`, `"tomorrow 10:00"`.
For all-day events add `--all-day`.

## Notes
- Credentials use the Nextcloud admin account via Vaultwarden item `76169a13-9830-48ee-b583-6cc9055ed03c`
- Some subscription calendars (Google Calendar imports) may show warnings — these are harmless
- The script is at `/Users/viktorbarzin/code/infra/.claude/calendar-query.py`
- Python deps (`caldav`, `icalendar`) are in `~/.venvs/claude/`
