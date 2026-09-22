---
name: job-hunter
description: |
  Query and refresh the passive job-market scraper. Use when:
  (1) User asks about salary data, job-market bands, or comp percentiles
      ("what are London staff SWE salaries", "bands for SRE roles at
      Anthropic", "how much does Monzo pay for backend engineers"),
  (2) User asks what jobs are available in London (or any named market)
      with filters by title / company / salary / source,
  (3) User asks for a digest of recent job postings ("top 10 London
      roles this week", "what did I miss"),
  (4) User asks to rescrape / refresh the job-hunter DB before querying
      ("pull fresh data first", "refresh then show me top roles"),
  (5) Any question about the job-hunter service, database, or scraper
      behaviour.
  All queries default to primary_location=london; pass 'any' to disable.
  Uses CNPG Postgres via kubectl exec into the job-hunter pod — no local
  DB needed.
author: Claude Code
version: 1.1.0
date: 2026-07-19
---

# job-hunter — query salaries + jobs + refresh

The `job-hunter` service in the `job-hunter` K8s namespace stores scraped
job postings from Greenhouse / Lever / Ashby (ATS), HN Who-is-hiring,
LinkedIn guest, and changedetection.io, plus per-level **compensation**
datapoints from levels.fyi + UK salary surveys. Prefer these CLIs over
direct Postgres queries — they enforce filters, normalise salary to GBP,
and return agent-friendly JSON.

**Salary/comp questions → the `comp*` commands (§6–8), not `bands`.** `bands`
percentiles come from disclosed *job-posting* salary; the levels.fyi per-level
medians (`comp`, `comp-band`, `comp-table`, `comp-lookup`, `analyze`) are the
richer cross-company compensation source, and `comp-lookup` reaches **any**
company live — not just the seeded set.

## Invocation pattern

Always invoke via `kubectl exec` into the running pod:

```bash
kubectl -n job-hunter exec deploy/job-hunter -- python -m job_hunter <subcommand> [flags]
```

All subcommands default to JSON output; parse with `jq` or directly.

## Subcommands

### 1. `report` — one-shot summary (start here)

```bash
kubectl -n job-hunter exec deploy/job-hunter -- python -m job_hunter report --days 7 --top-n 10
```

Returns: `{filter, totals, salary_band_gbp:{n,min,max,avg,p25,p50,p75,p90},
top_roles:[…], top_companies:[…], by_source:{…}}` for a single filter window.
**Use this whenever the user asks "what's happening"** — it's the highest-leverage
single call.

Options:
- `--location london` (default; `any` to disable)
- `--days 7` (window for "recent")
- `--top-n 10` (top roles included)

### 2. `query` — list individual roles

```bash
kubectl -n job-hunter exec deploy/job-hunter -- python -m job_hunter query \
  --title staff --min-gbp 180000 --limit 20
```

Returns a JSON array of role dicts ordered by (salary_confidence DESC,
parsed_base_gbp DESC, posted_at DESC).

Options:
- `--location london` / `--location any` / `--location remote_uk`
- `--min-gbp N` / `--max-gbp N` (GBP-normalised base comp)
- `--title STR` / `--company STR` (ILIKE fuzzy match)
- `--source greenhouse|lever|ashby|hn|cdio|linkedin_guest`
- `--remote-only` (remote_policy='remote')
- `--days N` (posted within last N days)
- `--with-salary` (only rows with explicit comp)
- `--limit N --offset N`
- `--format json|table`

### 3. `bands` — salary percentiles

```bash
kubectl -n job-hunter exec deploy/job-hunter -- python -m job_hunter bands \
  --title 'staff engineer' --location london
```

Returns `{n, min, max, avg, p25, p50, p75, p90}` in GBP for all roles
matching the filter that have explicit salary disclosure. **Requires
>= 1 row with salary** — will return nulls if filter is too narrow.

### 4. `refresh` — trigger a scrape

```bash
kubectl -n job-hunter exec deploy/job-hunter -- python -m job_hunter refresh \
  --source ats --source hn
```

Runs the chosen sources synchronously. Takes ~60-180 seconds for ATS +
HN. Primes FX rates first so non-GBP roles convert correctly. Returns
`{"status":"ok","counts":{"ats":N,"hn":N}}`.

Sources: `ats` (all Greenhouse+Lever+Ashby companies in config),
`hn` (current month's Who-is-hiring thread), `linkedin`
(LinkedIn guest via JobSpy, 200/day cap), `levels_fyi` (per-level comp via
the official `.md` endpoint, ~6 eng families × seeded companies, ~7 min),
`uk_surveys` (Robert Walters / Hays annual bands).

### 5. `backfill-locations` / `backfill-fx` — housekeeping

- `backfill-locations` — rewrites `primary_location` for rows with NULL
  after a migration. Rarely needed.
- `backfill-fx --days 30` — populates `fx_rates` from ECB for the last
  N days.

### 6. `comp` / `comp-band` / `comp-table` — company × level compensation

Cross-company per-level compensation from levels.fyi (median total comp) +
UK surveys — **the right tools for "what does X pay at level Y"**, all
GBP-normalised. Default `--location any` (browse the whole market); narrow
with `--location london` (UK-HQ names) / `us` (US big-tech) / etc.

```bash
# concrete datapoints for a (company, level)
kubectl -n job-hunter exec deploy/job-hunter -- python -m job_hunter comp \
  --company stripe --level senior
# percentile summary (p25/p50/p75/p90 total comp)
kubectl -n job-hunter exec deploy/job-hunter -- python -m job_hunter comp-band \
  --company anthropic --location us
# per-(company, level) table for a location
kubectl -n job-hunter exec deploy/job-hunter -- python -m job_hunter comp-table \
  --location london --limit 30
```

`--source levels_fyi | robert_walters_2026 | hays_2026` filters the origin.

### 7. `comp-lookup` — live levels.fyi for ANY company

Fetches levels.fyi's official role `.md` **live** for any company/role —
including ones NOT in the seeded set — parses the per-level table, returns
native + GBP with attribution. **Use this for arbitrary "what does <company>
pay" questions.** Read-only; `--save` persists into comp_points.

```bash
kubectl -n job-hunter exec deploy/job-hunter -- python -m job_hunter comp-lookup \
  --company jane-street --role software-engineer
kubectl -n job-hunter exec deploy/job-hunter -- python -m job_hunter comp-lookup \
  --company databricks --role machine-learning-engineer --save
```

`--company` is the levels.fyi slug (lowercase-hyphenated; a name is slugified).
`--role` defaults to `software-engineer`. `--location <slug>` is optional and
usually unnecessary — levels.fyi frequently echoes national numbers for
locations without their own data.

### 8. `analyze` — comp market leaders + dated trends

```bash
kubectl -n job-hunter exec deploy/job-hunter -- python -m job_hunter analyze \
  --level senior --location us --top-n 10
```

Markdown (default) or `--format json`. Current comp leaders by p50 total comp,
snapshot-driven movers, new entrants. `--location` defaults to `london`.

## Typical agent flows

**"Show me top London staff engineer roles."**

```bash
kubectl -n job-hunter exec deploy/job-hunter -- python -m job_hunter query \
  --title 'staff' --with-salary --limit 10
```

**"What's the London staff salary band right now?"**

```bash
kubectl -n job-hunter exec deploy/job-hunter -- python -m job_hunter bands \
  --title 'staff'
```

**"Refresh first, then give me a summary of this week's roles."**

```bash
kubectl -n job-hunter exec deploy/job-hunter -- python -m job_hunter refresh --source ats --source hn
kubectl -n job-hunter exec deploy/job-hunter -- python -m job_hunter report --days 7
```

**"Compare Monzo vs Anthropic comp."** (levels.fyi per-level medians)

```bash
kubectl -n job-hunter exec deploy/job-hunter -- python -m job_hunter comp-band --company monzo --location london
kubectl -n job-hunter exec deploy/job-hunter -- python -m job_hunter comp-band --company anthropic --location us
```

**"What does <any company> pay for SWEs?"** (live, reaches beyond the seeded set)

```bash
kubectl -n job-hunter exec deploy/job-hunter -- python -m job_hunter comp-lookup --company stripe
```

## Output conventions

All JSON output is UTF-8, pretty-printed, `default=str` for decimals/dates.

Role record shape:
```json
{
  "id": 4857,
  "source": "ashby",
  "title": "Software Engineer, Integrity Foundations - London",
  "company": "OpenAI",
  "company_slug": "openai",
  "location": "London, UK",
  "primary_location": "london",
  "remote_policy": null,
  "base_gbp": 295500.0,
  "currency": "USD",
  "salary_confidence": 1.0,
  "apply_url": "https://jobs.ashbyhq.com/openai/…",
  "posted_at": "2026-01-26T19:01:32+00:00",
  "fetched_at": "2026-04-19T17:56:41+00:00"
}
```

## Data sources (as of 2026-04-19)

- **ATS** (Greenhouse / Lever / Ashby): 23 verified companies. Public
  JSON APIs, no auth. See `/app/config/companies.yaml` in the pod.
- **HN Who-is-hiring**: current month's thread via Algolia.
- **LinkedIn guest**: capped at 200/day, 1 req/5s. Opt-in with `--source linkedin`.
- **CDIO**: custom careers pages via changedetection.io (Two Sigma, Jane
  Street, Citadel, Bloomberg, Wise, Revolut). Fires via webhook, not
  pulled by `refresh`.
- **levels.fyi** (`source=levels_fyi`, comp_points): per-level median total
  comp via the official, no-auth `.md` LLM endpoint
  (`/companies/{slug}/salaries/{family}.md`; see levels.fyi/llms.txt).
  Refresh pulls ~6 engineering families per seeded company. **Attribution
  required** — cite "Data source: Levels.fyi (https://www.levels.fyi)" in any
  derived / shared output.
- **UK surveys** (`source=robert_walters_2026 | hays_2026`, comp_points):
  annual UK salary-guide bands (base comp).

**Compensation location model (since 2026-07-19):** levels.fyi rows are tagged
with the page's *declared* location — UK/London → `london`, US → `us`, else a
country slug — instead of the old force-tag-everything-`london`. So the `london`
comp bucket holds UK-HQ names (Monzo etc.); US big-tech (Google/Meta/Stripe)
lives under `us`. levels.fyi's free `.md` is **country-granular** — true
London-only numbers for US companies aren't available (a `/locations/london…`
page just echoes the national figures), so the `comp*` commands default to
`--location any`.

**Comp caveats:** levels.fyi exposes only median TOTAL comp per level (no
base/bonus/RSU split; no per-level sample count via `.md`). Canonical level
buckets are coarse — `infer_level` collapses e.g. Monzo L1–L3 → `entry`,
L4–L5 → `senior`; the raw level label (E5, L4, …) is preserved in
`raw_payload` and in `comp-lookup` output.

Currency normalisation: ECB rates backfilled on every refresh, looked up
by `posted_at` date (falls back up to 7 days). `parsed_base_gbp` is the
GBP-normalised midpoint of `salary_min` and `salary_max`.

Dedup: `dedup_key = sha256(company_slug, normalised_title, normalised_location)`.
Same role from LinkedIn + company Greenhouse collapses.

## Do NOT

- Don't query Postgres directly (`psql`, raw SQL) unless the CLI can't
  express the query — the CLI enforces invariants (FK join, location
  normalisation, safe LIMIT). Escalate to SQL only for aggregates the
  CLI doesn't support.
- Don't run `refresh` in tight loops. Once per hour is plenty; once per
  day is the normal cadence.
- Don't pass raw user input into `--company` / `--title` flags without
  sanitising — they go into `ILIKE '%...%'` which treats `%` / `_` as
  wildcards.

## Related

- Service: `<service URL>` (find it with `homelab k8s get job-hunter svc`)
  (`/healthz`, `/refresh`, `/webhook/cdio`, `/digest/generate`)
- DB: `<host>:<port>/job_hunter` (find it with `homelab k8s get dbaas svc`)
  (role `job_hunter`, password rotated 168h via Vault)
- Grafana: `https://grafana.viktorbarzin.me` → Finance → Job Hunter
- Forgejo repo: `https://forgejo.viktorbarzin.me/viktor/job-hunter`
- Terraform stack: `infra/stacks/job-hunter/`
- Beads epic: `code-snp`
