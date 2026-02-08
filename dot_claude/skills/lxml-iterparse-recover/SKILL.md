---
name: lxml-iterparse-recover
description: |
  Handle malformed XML in lxml iterparse with recover mode. Use when:
  (1) lxml.etree.XMLSyntaxError "AttValue: ' expected" or similar parse errors on
  large XML files like Apple Health exports, (2) need streaming XML parsing that
  tolerates broken attributes, (3) tried passing parser=XMLParser(recover=True)
  to iterparse and got "unexpected keyword argument 'parser'". The recover flag
  is a direct parameter of iterparse, not passed via a parser object.
author: Claude Code
version: 1.0.0
date: 2026-02-08
---

# lxml iterparse: Recovering from Malformed XML

## Problem
Large XML files (e.g., Apple Health exports) sometimes contain malformed attribute
values with unescaped characters. lxml's `iterparse` raises `XMLSyntaxError` and
aborts parsing, losing all data after the corrupt element.

## Context / Trigger Conditions
- Parsing large XML files with `lxml.etree.iterparse`
- Error: `lxml.etree.XMLSyntaxError: AttValue: ' expected, line NNNN, column NNN`
- The malformed XML is from an external source you can't control (Apple Health, etc.)
- You want to skip corrupt elements and continue parsing

## Solution
Pass `recover=True` directly to `iterparse` — it's a first-class parameter:

```python
from lxml import etree

context = etree.iterparse(
    file_path,
    events=("end",),
    tag=("Record", "Workout"),
    recover=True,  # Skip malformed elements instead of aborting
)
```

**Common mistake**: Trying to pass a parser object:
```python
# WRONG — iterparse does NOT accept a parser= keyword
parser = etree.XMLParser(recover=True)
context = etree.iterparse(file_path, parser=parser)
# TypeError: __init__() got an unexpected keyword argument 'parser'
```

## Verification
Parse the full file without `XMLSyntaxError`. Check `context.error_log` after
parsing to see which elements were skipped.

## Notes
- `recover=True` defaults to `True` for HTML mode, `False` for XML mode
- Recovered elements may have missing or truncated attributes — always validate
  parsed values before using them
- Other useful iterparse flags: `huge_tree=True` for very deep/large documents
- The full list of iterparse parameters can be viewed with `help(etree.iterparse)`
