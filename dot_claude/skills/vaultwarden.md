name: vaultwarden
description: Manage passwords in Vaultwarden. Use when needing credentials
  for services, databases, APIs, or when storing new secrets.
---

## CRITICAL: Credential Blindness
NEVER use commands that would print passwords to stdout.
Passwords must NEVER appear in tool output sent to Anthropic's API.

## Available commands (each triggers Touch ID)

### Search (safe — returns metadata only)
```bash
bw-vault search <query>
```
Returns: item name, username, URL, id — NO passwords

### Inject password into a command (safe — password never in output)
```bash
bw-vault inject <item-name-or-id> --as <ENV_VAR> -- <command...>
```
Example: `bw-vault inject "prod-db" --as PGPASSWORD -- psql -h db.local -U admin`

### Copy to clipboard (safe — only "Copied" message returned)
```bash
bw-vault copy <item-name-or-id> [field]
```
field defaults to "password", can be "username", "totp", "uri"

### Write to temp file (safe — only file path returned)
```bash
bw-vault file <item-name-or-id> /tmp/secret-XXXX
```

### Create new item (password auto-generated)
```bash
bw-vault create
```

### Edit existing item
```bash
bw-vault edit <item-name-or-id>
```

## NEVER DO
- `bw get password <id>` — would leak to API
- `cat /tmp/secret-XXXX` — would leak file contents to API
- `echo $PGPASSWORD` — would leak env var to API
- Any command that prints a secret value to stdout
