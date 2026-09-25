#!/usr/bin/env python3
"""mail.py — multi-account IMAP/SMTP helper for Claude's `email` skill.

Accounts (read live from Vault, nothing stored at rest):
  me    me@viktorbarzin.me    (docker-mailserver)  mail.viktorbarzin.me
  spam  spam@viktorbarzin.me  (docker-mailserver)  mail.viktorbarzin.me
  gmail vbarzin@gmail.com     (Gmail, app password) imap.gmail.com / smtp.gmail.com

Credentials:
  me/spam : vault kv get <path> (find it with `homelab vault kv list secret`) -> mailserver_accounts[<addr>]
  gmail   : vault kv get <path> (find it with `homelab vault kv list secret`) -> gmail_imap_user / gmail_imap_pass

Sub-commands: accounts, folders, search, read, scan-pdfs, get-attachment, draft, send.
Reads are non-destructive (BODY.PEEK — never sets \\Seen unless --mark-seen).
Sending is the only outward-facing action; the skill requires confirming with the
user before `send` is ever invoked.
"""
import argparse
import datetime
import email
import json
import os
import re
import smtplib
import ssl
import subprocess
import sys
import time
from email.header import decode_header, make_header
from email.message import EmailMessage

import imaplib

imaplib._MAXLINE = 10_000_000  # large BODYSTRUCTURE batches


# ============================================================ credentials ===

def _vault(path):
    out = subprocess.check_output(
        ["vault", "kv", "get", "-format=json", path],
        text=True, stderr=subprocess.DEVNULL,
    )
    return json.loads(out)["data"]["data"]


def load_accounts():
    """Build the account registry from Vault. Cached per-process."""
    plat = _vault("secret/platform")
    acc = json.loads(plat["mailserver_accounts"])
    rr = _vault("secret/recruiter-responder")
    return {
        "me": dict(addr="me@viktorbarzin.me", imap_host="mail.viktorbarzin.me",
                   imap_port=993, smtp_host="mail.viktorbarzin.me", smtp_port=587,
                   user="me@viktorbarzin.me", password=acc["me@viktorbarzin.me"],
                   gmail=False),
        "spam": dict(addr="spam@viktorbarzin.me", imap_host="mail.viktorbarzin.me",
                     imap_port=993, smtp_host="mail.viktorbarzin.me", smtp_port=587,
                     user="spam@viktorbarzin.me", password=acc["spam@viktorbarzin.me"],
                     gmail=False),
        "gmail": dict(addr=rr["gmail_imap_user"], imap_host="imap.gmail.com",
                      imap_port=993, smtp_host="smtp.gmail.com", smtp_port=587,
                      user=rr["gmail_imap_user"],
                      password=rr["gmail_imap_pass"].replace(" ", ""), gmail=True),
    }


# ====================================================== pure parsing logic ===

def decode_mime_words(s):
    """Decode RFC2047 MIME-encoded words ('=?UTF-8?Q?..?=') to a plain str."""
    if not s:
        return ""
    try:
        return str(make_header(decode_header(s))).strip()
    except Exception:
        return str(s)


def _tokenize(s):
    """Tokenize an IMAP parenthesised structure into nested lists.

    Strings -> str, NIL -> None, integers -> int, atoms -> str.
    """
    if isinstance(s, str):
        s = s.encode()
    i, n = 0, len(s)

    def parse():
        nonlocal i
        items = []
        while i < n:
            c = s[i:i + 1]
            if c == b'(':
                i += 1
                items.append(parse())
            elif c == b')':
                i += 1
                return items
            elif c == b'"':
                i += 1
                buf = bytearray()
                while i < n:
                    ch = s[i:i + 1]
                    if ch == b'\\':
                        buf += s[i + 1:i + 2]
                        i += 2
                        continue
                    if ch == b'"':
                        i += 1
                        break
                    buf += ch
                    i += 1
                items.append(buf.decode("utf-8", "replace"))
            elif c == b'{':
                j = s.index(b'}', i)
                ln = int(s[i + 1:j])
                i = j + 1
                if s[i:i + 2] == b'\r\n':
                    i += 2
                items.append(s[i:i + ln].decode("utf-8", "replace"))
                i += ln
            elif c in (b' ', b'\r', b'\n'):
                i += 1
            else:
                buf = bytearray()
                while i < n and s[i:i + 1] not in (b' ', b'(', b')', b'"', b'\r', b'\n'):
                    buf += s[i:i + 1]
                    i += 1
                tok = buf.decode("ascii", "replace")
                if tok.upper() == "NIL":
                    items.append(None)
                elif tok.isdigit():
                    items.append(int(tok))
                else:
                    items.append(tok)
        return items

    return parse()


def _find_structure(top):
    """Locate the body-structure node (the element after a BODYSTRUCTURE token)."""
    stack = [top]
    while stack:
        node = stack.pop()
        if isinstance(node, list):
            for idx, el in enumerate(node):
                if isinstance(el, str) and el.upper() == "BODYSTRUCTURE" and idx + 1 < len(node):
                    return node[idx + 1]
            for el in node:
                if isinstance(el, list):
                    stack.append(el)
    # No keyword: assume the largest leading list is the structure itself.
    if isinstance(top, list):
        for el in top:
            if isinstance(el, list):
                return el
    return top


def _param(params, key):
    """Look up a parameter value (case-insensitive) from a flat [k,v,k,v] list.

    Handles RFC2231 split params (filename*0, filename*1, ...) best-effort.
    """
    if not isinstance(params, list):
        return None
    d = {}
    it = iter(params)
    for k in it:
        v = next(it, None)
        if isinstance(k, str):
            d[k.lower()] = v
    key = key.lower()
    if d.get(key):
        return d[key]
    parts, idx = [], 0
    while f"{key}*{idx}" in d or f"{key}*{idx}*" in d:
        parts.append(d.get(f"{key}*{idx}") or d.get(f"{key}*{idx}*") or "")
        idx += 1
    if parts:
        joined = "".join(parts)
        if "'" in joined and joined.split("'", 2)[0].lower() in ("utf-8", "iso-8859-1", "us-ascii"):
            import urllib.parse
            joined = urllib.parse.unquote(joined.split("'", 2)[-1])
        return joined
    return d.get(f"{key}*")


def _walk_parts(node, out):
    if not isinstance(node, list) or not node:
        return
    if isinstance(node[0], list):  # multipart: child parts then a subtype string
        for el in node:
            if isinstance(el, list):
                _walk_parts(el, out)
            else:
                break
        return
    if not (isinstance(node[0], str) and len(node) >= 2 and isinstance(node[1], str)):
        return
    mtype, subtype = node[0].lower(), (node[1] or "").lower()
    params = node[2] if len(node) > 2 else None
    size = node[6] if len(node) > 6 and isinstance(node[6], int) else None
    name = _param(params, "name")
    disp_name = None
    for el in node:
        if (isinstance(el, list) and el and isinstance(el[0], str)
                and el[0].lower() in ("attachment", "inline")):
            disp_name = _param(el[1] if len(el) > 1 else None, "filename")
    fname = decode_mime_words(disp_name or name) if (disp_name or name) else ""
    if (mtype == "application" and subtype == "pdf") or fname.lower().endswith(".pdf"):
        out.append({"name": fname, "size": size})
    # message/rfc822 embeds a nested structure; rare for our purposes — skip.


def extract_pdfs_from_bodystructure(bs):
    """Return [{'name', 'size'}] for every PDF part in an IMAP BODYSTRUCTURE blob."""
    out = []
    _walk_parts(_find_structure(_tokenize(bs)), out)
    return out


def pick_special_folder(list_lines, role):
    """Pick a folder by RFC6154 SPECIAL-USE flag, falling back to a name match."""
    special = {"drafts": "\\drafts", "sent": "\\sent", "all": "\\all",
               "junk": "\\junk", "trash": "\\trash", "archive": "\\archive"}
    fallback = {"drafts": ["drafts"], "sent": ["sent", "sent mail", "sent items"],
                "all": ["all mail", "all"], "junk": ["junk", "spam"],
                "trash": ["trash", "deleted"], "archive": ["archive"]}
    role = role.lower()
    parsed = []
    for line in list_lines:
        if isinstance(line, bytes):
            line = line.decode("utf-8", "replace")
        m = re.match(r'\((?P<flags>[^)]*)\)\s+(?:"[^"]*"|NIL|\S+)\s+'
                     r'(?P<name>"(?:[^"\\]|\\.)*"|\S+)', line)
        if not m:
            continue
        name = m.group("name")
        if name.startswith('"') and name.endswith('"'):
            name = name[1:-1]
        parsed.append((m.group("flags").lower(), name))
    flag = special.get(role)
    if flag:
        for flags, name in parsed:
            if flag in flags:
                return name
    wants = fallback.get(role, [role])
    for _flags, name in parsed:
        if name.lower() in wants or name.split("/")[-1].lower() in wants:
            return name
    return None


# ============================================================ IMAP / SMTP ===

def connect_imap(acc):
    M = imaplib.IMAP4_SSL(acc["imap_host"], acc["imap_port"])
    M.login(acc["user"], acc["password"])
    return M


def list_folders(M):
    typ, data = M.list()
    return [d for d in (data or []) if d]


def imap_date(s):
    return datetime.datetime.strptime(s, "%Y-%m-%d").strftime("%d-%b-%Y")


def default_scan_folders(M, acc):
    folders = list_folders(M)
    if acc["gmail"]:
        return [pick_special_folder(folders, "all") or "INBOX"]
    out = ["INBOX"]
    arch = pick_special_folder(folders, "archive")
    if arch and arch not in out:
        out.append(arch)
    return out


def _quote(name):
    return '"%s"' % name.replace('"', '\\"')


def search_pdf_uids(M, acc, since=None):
    if acc["gmail"]:
        raw = "has:attachment filename:pdf"
        if since:
            raw += " after:%s" % since.replace("-", "/")
        typ, data = M.uid("SEARCH", "X-GM-RAW", '"%s"' % raw)
    elif since:
        typ, data = M.uid("SEARCH", "SINCE", imap_date(since))
    else:
        typ, data = M.uid("SEARCH", "ALL")
    if typ != "OK" or not data or not data[0]:
        return []
    return data[0].split()


def iter_bodystructures(M, uids, chunk=200):
    for i in range(0, len(uids), chunk):
        batch = b",".join(uids[i:i + chunk])
        typ, data = M.uid("FETCH", batch, "(UID BODYSTRUCTURE)")
        if typ != "OK":
            continue
        for el in data:
            raw = el[0] if isinstance(el, tuple) else el
            if not raw:
                continue
            m = re.search(rb"UID (\d+)", raw)
            if not m:
                continue
            yield m.group(1), raw


def fetch_header_fields(M, uid):
    typ, data = M.uid("FETCH", uid, "(BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE TO)])")
    blob = b""
    for el in data or []:
        if isinstance(el, tuple) and len(el) > 1 and el[1]:
            blob += el[1]
    msg = email.message_from_bytes(blob)
    return {
        "from": decode_mime_words(msg.get("From", "")),
        "to": decode_mime_words(msg.get("To", "")),
        "subject": decode_mime_words(msg.get("Subject", "")),
        "date": (msg.get("Date", "") or "").strip(),
    }


def fetch_full(M, uid, mark_seen=False):
    item = "(RFC822)" if mark_seen else "(BODY.PEEK[])"
    typ, data = M.uid("FETCH", uid, item)
    for el in data or []:
        if isinstance(el, tuple) and len(el) > 1 and el[1]:
            return el[1]
    return b""


# ================================================================ commands ===

def cmd_accounts(args, accs):
    print(json.dumps([{"key": k, "address": v["addr"], "imap": v["imap_host"],
                       "smtp": v["smtp_host"]} for k, v in accs.items()], indent=2))


def cmd_folders(args, accs):
    M = connect_imap(accs[args.account])
    try:
        for d in list_folders(M):
            print(d.decode("utf-8", "replace") if isinstance(d, bytes) else d)
    finally:
        M.logout()


def cmd_search(args, accs):
    acc = accs[args.account]
    M = connect_imap(acc)
    try:
        M.select(_quote(args.folder), readonly=True)
        crit = []
        if args.unseen:
            crit.append("UNSEEN")
        if args.since:
            crit += ["SINCE", imap_date(args.since)]
        if args.from_:
            crit += ["FROM", '"%s"' % args.from_]
        if args.subject:
            crit += ["SUBJECT", '"%s"' % args.subject]
        if not crit:
            crit = ["ALL"]
        typ, data = M.uid("SEARCH", None, *crit)
        uids = data[0].split() if data and data[0] else []
        uids = uids[-args.limit:] if args.limit else uids
        out = []
        for uid in reversed(uids):
            out.append({"uid": uid.decode(), **fetch_header_fields(M, uid)})
        print(json.dumps(out, indent=2))
    finally:
        M.logout()


def cmd_read(args, accs):
    acc = accs[args.account]
    M = connect_imap(acc)
    try:
        M.select(_quote(args.folder), readonly=not args.mark_seen)
        raw = fetch_full(M, args.uid.encode(), mark_seen=args.mark_seen)
        msg = email.message_from_bytes(raw)
        for h in ("From", "To", "Cc", "Subject", "Date",
                  "Message-ID", "In-Reply-To", "References"):
            if msg.get(h):
                print(f"{h}: {decode_mime_words(msg.get(h))}")
        atts = []
        body = ""
        for part in msg.walk():
            cd = (part.get("Content-Disposition") or "").lower()
            ctype = part.get_content_type()
            fn = decode_mime_words(part.get_filename()) if part.get_filename() else ""
            if fn or "attachment" in cd:
                atts.append(f"{fn or '(unnamed)'} [{ctype}]")
            elif ctype == "text/plain" and not body:
                try:
                    body = part.get_payload(decode=True).decode(
                        part.get_content_charset() or "utf-8", "replace")
                except Exception:
                    body = ""
        if atts:
            print("Attachments: " + "; ".join(atts))
        print("\n" + "-" * 60)
        print(body if args.full else body[:4000])
    finally:
        M.logout()


def cmd_scan_pdfs(args, accs):
    keys = [args.account] if args.account != "all" else list(accs.keys())
    results = []
    scanned = {}
    for key in keys:
        acc = accs[key]
        M = connect_imap(acc)
        try:
            folders = args.folders.split(",") if args.folders else default_scan_folders(M, acc)
            scanned[key] = folders
            for folder in folders:
                typ, _ = M.select(_quote(folder), readonly=True)
                if typ != "OK":
                    continue
                uids = search_pdf_uids(M, acc, since=args.since)
                pdf_uids = []
                cache = {}
                for uid, raw in iter_bodystructures(M, uids):
                    pdfs = extract_pdfs_from_bodystructure(raw)
                    if pdfs:
                        pdf_uids.append(uid)
                        cache[uid] = pdfs
                for uid in pdf_uids:
                    hdr = fetch_header_fields(M, uid)
                    results.append({
                        "account": key, "folder": folder, "uid": uid.decode(),
                        "date": hdr["date"], "from": hdr["from"],
                        "subject": hdr["subject"],
                        "pdfs": cache[uid],
                    })
        finally:
            M.logout()
        print(f"  scanned {key}: {scanned[key]} -> "
              f"{sum(1 for r in results if r['account'] == key)} msgs with PDFs",
              file=sys.stderr)
    out_path = args.out
    with open(out_path, "w") as f:
        json.dump(results, f, indent=2)
    print(f"{len(results)} messages with PDF attachments -> {out_path}", file=sys.stderr)
    print(out_path)


def cmd_get_attachment(args, accs):
    acc = accs[args.account]
    os.makedirs(args.out, exist_ok=True)
    M = connect_imap(acc)
    try:
        M.select(_quote(args.folder), readonly=True)
        raw = fetch_full(M, args.uid.encode(), mark_seen=False)
        msg = email.message_from_bytes(raw)
        written = []
        n = 0
        for part in msg.walk():
            ctype = part.get_content_type()
            fn = decode_mime_words(part.get_filename()) if part.get_filename() else ""
            if ctype == "application/pdf" or fn.lower().endswith(".pdf"):
                n += 1
                safe = re.sub(r"[^\w.\-]", "_", fn) or f"attachment_{n}.pdf"
                path = os.path.join(args.out, f"{args.account}_{args.uid}_{safe}")
                payload = part.get_payload(decode=True) or b""
                with open(path, "wb") as f:
                    f.write(payload)
                written.append({"path": path, "bytes": len(payload), "filename": fn})
        print(json.dumps(written, indent=2))
    finally:
        M.logout()


def _build_message(acc, args):
    msg = EmailMessage()
    msg["From"] = acc["addr"]
    msg["To"] = args.to
    if args.cc:
        msg["Cc"] = args.cc
    msg["Subject"] = args.subject
    irt = getattr(args, "in_reply_to", None)
    if irt:
        msg["In-Reply-To"] = irt
        refs = getattr(args, "references", None) or irt
        msg["References"] = refs
    msg.set_content(args.body)
    for path in (args.attach or []):
        with open(path, "rb") as f:
            data = f.read()
        msg.add_attachment(data, maintype="application", subtype="octet-stream",
                           filename=os.path.basename(path))
    return msg


def cmd_draft(args, accs):
    acc = accs[args.account]
    msg = _build_message(acc, args)
    M = connect_imap(acc)
    try:
        drafts = pick_special_folder(list_folders(M), "drafts") or "Drafts"
        M.append(_quote(drafts), "\\Draft",
                 imaplib.Time2Internaldate(time.time()), msg.as_bytes())
        print(f"Draft saved to {drafts} ({acc['addr']})")
    finally:
        M.logout()


def cmd_send(args, accs):
    acc = accs[args.account]
    msg = _build_message(acc, args)
    recipients = [r.strip() for r in (args.to.split(",") + (args.cc.split(",") if args.cc else [])
                                      + (args.bcc.split(",") if args.bcc else [])) if r.strip()]
    s = smtplib.SMTP(acc["smtp_host"], acc["smtp_port"], timeout=30)
    try:
        s.ehlo()
        s.starttls(context=ssl.create_default_context())
        s.ehlo()
        s.login(acc["user"], acc["password"])
        s.send_message(msg, from_addr=acc["addr"], to_addrs=recipients)
    finally:
        s.quit()
    saved = ""
    if not acc["gmail"]:  # Gmail auto-files to Sent; docker-mailserver does not
        M = connect_imap(acc)
        try:
            sent = pick_special_folder(list_folders(M), "sent") or "Sent"
            M.append(_quote(sent), "\\Seen",
                     imaplib.Time2Internaldate(time.time()), msg.as_bytes())
            saved = f"; copy filed to {sent}"
        finally:
            M.logout()
    print(f"Sent from {acc['addr']} to {recipients}{saved}")


def main():
    p = argparse.ArgumentParser(description="Multi-account IMAP/SMTP helper")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("accounts")

    sp = sub.add_parser("folders")
    sp.add_argument("--account", required=True)

    sp = sub.add_parser("search")
    sp.add_argument("--account", required=True)
    sp.add_argument("--folder", default="INBOX")
    sp.add_argument("--unseen", action="store_true")
    sp.add_argument("--since")
    sp.add_argument("--from", dest="from_")
    sp.add_argument("--subject")
    sp.add_argument("--limit", type=int, default=50)

    sp = sub.add_parser("read")
    sp.add_argument("--account", required=True)
    sp.add_argument("--folder", default="INBOX")
    sp.add_argument("--uid", required=True)
    sp.add_argument("--mark-seen", action="store_true")
    sp.add_argument("--full", action="store_true")

    sp = sub.add_parser("scan-pdfs")
    sp.add_argument("--account", default="all", help="me|spam|gmail|all")
    sp.add_argument("--folders", help="comma-separated; default per-account")
    sp.add_argument("--since", help="YYYY-MM-DD")
    sp.add_argument("--out", default="/tmp/pdf_scan.json")

    sp = sub.add_parser("get-attachment")
    sp.add_argument("--account", required=True)
    sp.add_argument("--folder", default="INBOX")
    sp.add_argument("--uid", required=True)
    sp.add_argument("--out", default="/tmp/mail_pdfs")

    for name in ("draft", "send"):
        sp = sub.add_parser(name)
        sp.add_argument("--account", required=True)
        sp.add_argument("--to", required=True)
        sp.add_argument("--cc", default="")
        sp.add_argument("--bcc", default="")
        sp.add_argument("--subject", required=True)
        sp.add_argument("--body", required=True)
        sp.add_argument("--attach", action="append")
        sp.add_argument("--in-reply-to", dest="in_reply_to",
                        help="Message-ID being replied to (threads the reply)")
        sp.add_argument("--references", help="References header; defaults to --in-reply-to")

    args = p.parse_args()
    if args.cmd == "accounts":
        return cmd_accounts(args, load_accounts())
    accs = load_accounts()
    {"folders": cmd_folders, "search": cmd_search, "read": cmd_read,
     "scan-pdfs": cmd_scan_pdfs, "get-attachment": cmd_get_attachment,
     "draft": cmd_draft, "send": cmd_send}[args.cmd](args, accs)


if __name__ == "__main__":
    main()
