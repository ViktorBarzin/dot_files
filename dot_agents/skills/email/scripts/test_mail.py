"""Unit tests for the pure parsing logic in mail.py.

These cover the bug-prone bits: IMAP BODYSTRUCTURE parsing for PDF detection,
MIME-word decoding, and SPECIAL-USE folder selection. IMAP/SMTP I/O is verified
by a live read-only smoke test, not here.

Run: python3 -m pytest test_mail.py -q   (or: python3 test_mail.py)
"""
import mail


# --- extract_pdfs_from_bodystructure -------------------------------------

SIMPLE = (
    b'1 (BODYSTRUCTURE (("text" "plain" ("charset" "utf-8") NIL NIL "7bit" 12 1 '
    b'NIL NIL NIL NIL)("application" "pdf" ("name" "Invoice-123.pdf") NIL NIL '
    b'"base64" 88516 NIL ("attachment" ("filename" "Invoice-123.pdf")) NIL NIL) '
    b'"mixed" ("boundary" "----abc") NIL NIL NIL))'
)

NO_PDF = (
    b'1 (BODYSTRUCTURE ("text" "html" ("charset" "utf-8") NIL NIL '
    b'"quoted-printable" 3450 50 NIL NIL NIL NIL))'
)

NESTED = (
    b'1 (BODYSTRUCTURE ((("text" "plain" ("charset" "utf-8") NIL NIL "7bit" 10 1 '
    b'NIL NIL NIL NIL)("text" "html" ("charset" "utf-8") NIL NIL "7bit" 20 1 NIL '
    b'NIL NIL NIL) "alternative" ("boundary" "x") NIL NIL NIL)("application" '
    b'"pdf" ("name" "ticket.pdf") NIL NIL "base64" 5000 NIL ("attachment" '
    b'("filename" "ticket.pdf")) NIL NIL) "mixed" ("boundary" "y") NIL NIL NIL))'
)

ENCODED = (
    b'1 (BODYSTRUCTURE (("text" "plain" ("charset" "utf-8") NIL NIL "7bit" 12 1 '
    b'NIL NIL NIL NIL)("application" "pdf" ("name" '
    b'"=?UTF-8?Q?Facture=5F2024=2Epdf?=") NIL NIL "base64" 4096 NIL '
    b'("attachment" ("filename" "=?UTF-8?Q?Facture=5F2024=2Epdf?=")) NIL NIL) '
    b'"mixed" ("boundary" "y") NIL NIL NIL))'
)

NONAME = (
    b'1 (BODYSTRUCTURE (("text" "plain" ("charset" "utf-8") NIL NIL "7bit" 12 1 '
    b'NIL NIL NIL NIL)("application" "pdf" NIL NIL NIL "base64" 999 NIL NIL NIL '
    b'NIL) "mixed" ("boundary" "y") NIL NIL NIL))'
)

# Some servers report the generic octet-stream type but a .pdf filename.
OCTET_PDF = (
    b'1 (BODYSTRUCTURE (("text" "plain" ("charset" "utf-8") NIL NIL "7bit" 12 1 '
    b'NIL NIL NIL NIL)("application" "octet-stream" ("name" "boarding-pass.pdf") '
    b'NIL NIL "base64" 7777 NIL ("attachment" ("filename" "boarding-pass.pdf")) '
    b'NIL NIL) "mixed" ("boundary" "y") NIL NIL NIL))'
)


def test_simple_pdf():
    r = mail.extract_pdfs_from_bodystructure(SIMPLE)
    assert len(r) == 1
    assert r[0]["name"] == "Invoice-123.pdf"
    assert r[0]["size"] == 88516


def test_no_pdf():
    assert mail.extract_pdfs_from_bodystructure(NO_PDF) == []


def test_nested_pdf():
    r = mail.extract_pdfs_from_bodystructure(NESTED)
    assert [p["name"] for p in r] == ["ticket.pdf"]
    assert r[0]["size"] == 5000


def test_encoded_filename():
    r = mail.extract_pdfs_from_bodystructure(ENCODED)
    assert len(r) == 1
    assert r[0]["name"] == "Facture_2024.pdf"


def test_pdf_without_name():
    r = mail.extract_pdfs_from_bodystructure(NONAME)
    assert len(r) == 1
    assert r[0]["size"] == 999
    assert (r[0]["name"] or "") == ""


def test_octet_stream_with_pdf_filename():
    r = mail.extract_pdfs_from_bodystructure(OCTET_PDF)
    assert len(r) == 1
    assert r[0]["name"] == "boarding-pass.pdf"


# --- decode_mime_words ----------------------------------------------------

def test_decode_plain():
    assert mail.decode_mime_words("Just a subject") == "Just a subject"


def test_decode_qencoded():
    assert mail.decode_mime_words("=?UTF-8?Q?Hello_World?=") == "Hello World"


def test_decode_none():
    assert mail.decode_mime_words(None) == ""


# --- pick_special_folder --------------------------------------------------

DOVECOT_LIST = [
    b'(\\HasNoChildren \\Drafts) "." "Drafts"',
    b'(\\HasNoChildren \\Sent) "." "Sent"',
    b'(\\HasNoChildren \\Junk) "." "Junk"',
    b'(\\HasNoChildren) "." "INBOX"',
    b'(\\HasNoChildren) "." "Archive"',
]

GMAIL_LIST = [
    b'(\\HasNoChildren) "/" "INBOX"',
    b'(\\HasChildren \\Noselect) "/" "[Gmail]"',
    b'(\\HasNoChildren \\All) "/" "[Gmail]/All Mail"',
    b'(\\HasNoChildren \\Drafts) "/" "[Gmail]/Drafts"',
    b'(\\HasNoChildren \\Sent) "/" "[Gmail]/Sent Mail"',
]


def test_pick_drafts_dovecot():
    assert mail.pick_special_folder(DOVECOT_LIST, "drafts") == "Drafts"


def test_pick_sent_gmail():
    assert mail.pick_special_folder(GMAIL_LIST, "sent") == "[Gmail]/Sent Mail"


def test_pick_all_gmail():
    assert mail.pick_special_folder(GMAIL_LIST, "all") == "[Gmail]/All Mail"


def test_pick_fallback_by_name():
    # No SPECIAL-USE flag present -> fall back to a name match.
    lines = [b'(\\HasNoChildren) "." "Drafts"', b'(\\HasNoChildren) "." "INBOX"']
    assert mail.pick_special_folder(lines, "drafts") == "Drafts"


def test_pick_missing_returns_none():
    lines = [b'(\\HasNoChildren) "." "INBOX"']
    assert mail.pick_special_folder(lines, "sent") is None


if __name__ == "__main__":
    import sys
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for fn in fns:
        try:
            fn()
            print(f"PASS {fn.__name__}")
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"FAIL {fn.__name__}: {type(e).__name__}: {e}")
    print(f"\n{len(fns)-failed}/{len(fns)} passed")
    sys.exit(1 if failed else 0)
