---
name: plan-holiday
description: |
  Plan holidays and search flights using Ryanair/Wizz Air direct APIs.
  Use when: (1) user asks to plan a trip/holiday, (2) user asks to find or compare
  flights, (3) "where should I go" / "weekend getaway", (4) need real-time flight
  prices from London to European destinations. Covers full trip planning (flights,
  itinerary, visa, deals) and standalone flight search.
  No paid API keys or browser automation needed.
author: Claude Code
version: 3.0.0
date: 2026-03-15
---

# Holiday Planner

This skill has two modes. All domain knowledge lives in the agents — this file is purely orchestration.

## Mode Detection

- **Full trip plan**: "plan a trip", "plan a holiday", "where should I go", "weekend getaway", "plan my trip"
- **Flight search only**: "find flights", "search flights", "how much to fly to X", "flights from X to Y", "compare prices"

---

## FLIGHT SEARCH ONLY MODE

Spawn a single **holiday-flights** agent (model: sonnet) with the user's query. The agent has all Ryanair/Wizz Air API docs, CLI commands, open jaw strategy, and seat tips. No further orchestration needed — just relay its output.

---

## FULL TRIP PLANNING MODE

### Step 0 — Discovery (Brainstorming)

Before doing any research, understand what the user actually wants. Ask questions **one at a time**, preferring multiple choice when possible. Stop asking once you have enough to proceed — don't over-question.

**Extract these (skip any the user already provided):**

1. **Destination**: Where? Or "anywhere warm / anywhere cheap / surprise me"?
2. **Dates**: When? Specific dates, or flexible? If flexible:
   - (a) Specific weekend (e.g., "May bank holiday")
   - (b) Flexible within a month (e.g., "sometime in May")
   - (c) Totally open — find the cheapest weekend
3. **Duration**: Weekend (Fri-Sun), long weekend (Fri-Mon), or longer?
4. **Budget**: What's the target? Per person or total?
   - (a) Budget (under £200 total)
   - (b) Mid-range (£200-500 total)
   - (c) No real limit, just find the best value
5. **Trip type**:
   - (a) Fly in and out of the same city
   - (b) Open jaw — fly into one city, out of another
   - (c) Not sure yet
6. **Vibe** — what kind of trip?
   - (a) Culture & history (museums, architecture, walking tours)
   - (b) Beach & relax
   - (c) Food & nightlife
   - (d) Adventure & outdoors (hiking, nature)
   - (e) Mix of everything
7. **Accommodation preference**:
   - (a) Hostel / budget
   - (b) Hotel / mid-range
   - (c) Airbnb / apartment
   - (d) Whatever's cheapest
8. **Any must-dos or deal-breakers?** (e.g., "must see the Alhambra", "no hostels", "need beach access")

**Rules:**
- If the user's initial message already covers most of these, don't re-ask — just confirm your understanding and ask about the 1-2 gaps.
- Maximum 3 rounds of questions. If you still have gaps after 3, use sensible defaults.
- Present a brief summary of what you understood before moving to Step 1.

### Step 1 — Parse & Calendar Check

With discovery complete, resolve the concrete parameters:

#### Date Normalization
Always resolve departure to a **Friday** when using `explore`. If user gives non-Friday dates, use `search` instead. The `explore` CLI command requires a Friday date.

#### Bank Holiday Check
```bash
cd /Users/viktorbarzin/code/holiday-planner/backend && .venv/bin/python -c "
from app.bank_holidays import is_long_weekend
from datetime import date
print(is_long_weekend(date(YYYY, M, D)))
"
```
If True, the return date will be Monday instead of Sunday.

#### Calendar Conflict Check (best-effort)
```bash
bw-vault inject "76169a13-9830-48ee-b583-6cc9055ed03c" --as NEXTCLOUD_APP_PASSWORD -- env NEXTCLOUD_USER=admin ~/.venvs/claude/bin/python3 /Users/viktorbarzin/code/infra/.claude/calendar-query.py events --date <start> --days <length> --json
```
Uses `bw-vault inject` for secure credential injection. If the script fails, note "calendar check skipped" and proceed. If conflicts found, report them and ask user to confirm or shift dates.

### Step 2 — Phase 1: Parallel Research (3 agents)

Spawn ALL THREE agents in a **single tool call block** (parallel):

1. **holiday-flights** (model: sonnet) — flights via CLI + raw APIs + web deals
2. **holiday-timing-safety** (model: sonnet) — weather, FCDO advisory, visa for BG/UK + RO nationals
3. **holiday-deals** (model: sonnet) — accommodation, discount codes, cashback, free activities

Each agent prompt MUST include: destination, exact dates, budget, preferences, accommodation preference, vibe, and for open jaw trips the inbound/outbound airports.

### Step 2.5 — Phase 1 Output Validation

- If **flights returned NO results**: inform user and ask whether to proceed with web-search-only or abort. Do NOT spawn itinerary agent without flight times.
- If **timing-safety failed**: proceed but note "safety/visa data unavailable — verify independently."
- If **deals failed**: proceed without deals section.

### Step 3 — Phase 2: Sequential Planning (1 agent)

Spawn **holiday-itinerary** (model: opus) with ALL Phase 1 outputs combined plus the user's vibe/preferences from discovery. It synthesizes a day-by-day plan factoring in flight times, hotel location, weather, and safety.

### Step 4 — Present Final Plan

```markdown
# Trip Plan: [Destination], [Country]
**Dates**: Fri DD Mon - Sun/Mon DD Mon (N nights)
**Budget**: ~GBPX total

## Visa Requirements
| Who | Visa? | Details |
|-----|-------|---------|
| You (BG/UK) | ... | ... |
| Girlfriend (RO) | ... | ... |

## Flights
[Best option + booking link]

## Accommodation
[Top pick + discount codes]

## Day-by-Day Itinerary
[Full plan from itinerary agent]

## Budget Breakdown
[Itemized: flights, accommodation, food, activities, transport]

## Money-Saving Tips
[Cashback, codes, free activities]

## Safety Notes
[FCDO advisory, key warnings]
```
