---
name: email
description: >
  Read, search, draft, and send Viktor's email across his three mailboxes —
  me@viktorbarzin.me, spam@viktorbarzin.me, and vbarzin@gmail.com. Use whenever
  asked to check/read/search the inbox, find an email or attachment, draft a
  reply, or send mail. Claude HAS email access through this skill; never claim
  otherwise. Credentials are read live from Vault — nothing is stored on disk.
---

# Email access

Three mailboxes, driven by the bundled CLI `scripts/mail.py` (Python stdlib only;
run with `python3 ~/.claude/skills/email/scripts/mail.py <cmd>`).

| key     | address              | server (IMAP / SMTP)                         |
|---------|----------------------|----------------------------------------------|
| `me`    | me@viktorbarzin.me   | mail.viktorbarzin.me (993 / 587 STARTTLS)    |
| `spam`  | spam@viktorbarzin.me | mail.viktorbarzin.me (993 / 587 STARTTLS)    |
| `gmail` | vbarzin@gmail.com    | imap.gmail.com / smtp.gmail.com              |

`spam@` is the catch-all; many forwarded/aliased messages land there.

## Credentials (Vault — read live at runtime, never cached to disk)

The CLI fetches these itself via the ambient `~/.vault-token`. If you ever need
them directly:

- `me` / `spam`: `vault kv get -field=mailserver_accounts <path>` (find it with `homelab vault kv list secret`) → JSON
  map `{address: password}`.
- `gmail`: `vault kv get <path>` (find it with `homelab vault kv list secret`) → `gmail_imap_user` /
  `gmail_imap_pass` (a Google **app password**, works for IMAP and SMTP).

If Vault is unreachable the CLI fails loudly — do not hand-type credentials.

## Commands

```
mail.py accounts                                   # list the 3 mailboxes
mail.py folders   --account me                     # list IMAP folders
mail.py search    --account gmail --unseen --limit 20
mail.py search    --account me --from x@y.com --since 2026-01-01 --subject invoice
mail.py read      --account me --folder INBOX --uid 1234        # body, attachments, Message-ID
mail.py scan-pdfs --account all --out /tmp/scan.json            # all msgs with PDF attachments
mail.py get-attachment --account gmail --folder "[Gmail]/All Mail" --uid 99 --out /tmp/pdfs
mail.py draft     --account me --to a@b.com --subject "Hi" --body "..."   # saves to Drafts
mail.py send      --account me --to a@b.com --subject "Hi" --body "..." [--cc] [--bcc] [--attach FILE]
mail.py send      --account me --to a@b.com --subject "Re: Hi" --body "..." --in-reply-to "<msg-id>"   # threaded reply
```

- **Reads never mark messages seen** (uses `BODY.PEEK`) unless you pass
  `--mark-seen` to `read`.
- **Reply in-thread** by passing the original's Message-ID (printed by `read`)
  to `--in-reply-to` on `send` or `draft`; `--references` defaults to it.
  Helpdesk systems such as ServiceNow attach an in-thread reply to the
  existing case, where a fresh email opens a new one.
- `scan-pdfs` uses Gmail's `X-GM-RAW filename:pdf` for Gmail and BODYSTRUCTURE
  inspection elsewhere; default folders are INBOX+Archive (me/spam) and All Mail
  (gmail). Output is JSON: `[{account, folder, uid, date, from, subject, pdfs:[{name,size}]}]`.

## Sending — confirm first

`send` is the only outward-facing action. **Always show the user the drafted
message and get explicit confirmation before invoking `send`.** Default to
`draft` (which only saves to the Drafts folder) when unsure. Gmail auto-files
sent mail to Sent; for me@/spam@ the CLI appends a copy to Sent itself.

## Tests

`cd scripts && python3 test_mail.py` — unit tests for the BODYSTRUCTURE/PDF
parser, MIME decoding, and SPECIAL-USE folder selection.

## Notes

- This skill lives in `~/.claude` (private to this user; not git-backed — back it
  up to the dotfiles repo if you want durability).
- Adding another mailbox = one entry in `load_accounts()` in `scripts/mail.py`.
