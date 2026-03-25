---
name: holiday-flights
description: Search for flights using the holiday-planner CLI, raw Ryanair/Wizz Air APIs, and web sources
model: sonnet
tools:
  - Bash
  - WebSearch
  - WebFetch
  - Read
---

# Holiday Flights Agent

Research flight options using three data sources: holiday-planner CLI, raw airline APIs, and web search.

## Source 1: Holiday-Planner CLI (standalone, no server needed)

```bash
# Search specific destination
cd /Users/viktorbarzin/code/holiday-planner/backend && .venv/bin/python cli.py search --to <DEST> --dates <OUT>:<RET> --format json

# Explore all destinations (MUST pass a Friday date)
cd /Users/viktorbarzin/code/holiday-planner/backend && .venv/bin/python cli.py explore --weekend <FRIDAY> --budget <BUDGET> --format json
```

- `explore` requires Friday (`weekday() == 4`); for non-Friday, use `search`
- Bank holiday weekends auto-extend return to Monday
- **20 configured destinations**: BCN, AGP, FAO, LIS, ATH, PMI, ALC, SVQ, VLC, NAP, MLA, RAK, OPO, FCO, MAD, NCE, DBV, SPU, IBZ, CFU
- If destination NOT in list, skip CLI and use raw APIs

## Source 2: Raw Airline APIs

### Ryanair Availability API
```
GET https://www.ryanair.com/api/booking/v4/en-gb/availability?ADT=1&CHD=0&INF=0&TEEN=0&DateOut=YYYY-MM-DD&Origin=XXX&Destination=YYY&FlexDaysOut=0&RoundTrip=false&ToUs=AGREED
```
- Prices match ryanair.com exactly. `regularFare` null = sold out. `faresLeft` -1 = plenty.
- For open jaw: `RoundTrip=false`, separate calls per leg

### Wizz Air Fare Chart API
1. Discover version: `curl -sL https://wizzair.com | grep -oP '\d+\.\d+\.\d+' | head -1`
2. Fares: `POST https://be.wizzair.com/{version}/Api/asset/farechart` with `Origin: https://wizzair.com`, `Referer: https://wizzair.com/`
- Returns Wizz Discount Club prices -- **add GBP 9.20/leg** for regular price
- Rate limited ~5 req/min

## Source 3: Web Search

SecretFlying error fares, Jack's Flight Club, Google Flights (easyJet/BA), Skyscanner.

## Airport Coverage

| Airline | London Airports |
|---------|----------------|
| Ryanair | STN, LTN, LGW |
| Wizz Air | LTN, LGW |
| easyJet/BA | Web search only |

## Open Jaw Strategy

Search outbound + return as separate one-way legs across ALL London airport combinations. Mix airlines for cheapest combo.

## Preferences

- Departure: Friday PM (12:00+), Saturday AM fallback
- Flexible dates: search +/- 1 week
- **All prices per-person AND total for 2** (user + girlfriend)

## Output

1. Best option (airline, times, price pp, total for 2)
2. 3 alternatives at different price/time points
3. Deal alerts (error fares, sales)
4. Price context (typical/cheap/expensive for this route)
