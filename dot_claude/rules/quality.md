# Quality (applies to ALL agents)

**If you are writing code, this applies to YOU. No exceptions.**

## 1. TDD cycle — test-first

1. **RED** — Write a failing test. Run it. Confirm it fails.
2. **GREEN** — Write minimal code to pass. Only enough to make the test green.
3. **REFACTOR** — Clean up. Tests stay green.
4. **VERIFY** — All must pass before committing:
   - Run tests: `pytest` (Python) / `npm test` (JS/TS)
   - Type check: `mypy .` (Python) / `tsc --noEmit` (TS)
   - Format: `yapf` (Python) / `prettier` (JS/TS)
   - Lint: `ruff check` (Python) / `eslint` (JS/TS) — **check the output**. Fix ALL errors before proceeding.
5. **COMMIT** — commit the verified change.
6. **REPEAT** — back to step 1.

## 2. Blockers — non-negotiable

- Writing implementation before a failing test exists = **BLOCKED**
- Skipping tests (with any excuse) = **BLOCKED**
- Writing tests after implementation = **BLOCKED**
- Lint errors (unused variables, missing imports) = **BLOCKED** — run linter and fix before proceeding.

## 3. Test quality rules

- Each test verifies ONE behavior
- Test behavior, not implementation (don't mock internals you own)
- Use data providers / parameterized tests for multi-scenario coverage
- Prefer property-based tests over example-based where the language supports it

## 4. Code quality checklist

Use this checklist for all code reviews and for your own output before committing. Evaluate each section and assign a verdict.

### AI slop detection

- [ ] No comments restating code (e.g., `// increment counter`, `// set the value`)
- [ ] No unnecessary docstrings (e.g., `/** Gets the value */` on a getter)
- [ ] No filler phrases (e.g., `This function is responsible for...`)
- [ ] No wrapper functions adding no value
- [ ] No commented-out code
- [ ] No redundant type annotations in comments
- [ ] No over-explained variable names — context comes from scope

### Engineering principles

- [ ] SRP: each function has a single responsibility (can describe without "and")
- [ ] DRY: existing utilities reused (searched before creating new)
- [ ] No premature abstractions or "just in case" parameters
- [ ] Functions ≤20 lines (excluding type signatures)
- [ ] Functions ≤3 parameters (more = use a struct/shape/object)
- [ ] Functions ≤1 nesting level (early return over nested if/else)
- [ ] No boolean parameters — named constants or enums instead
- [ ] No magic values — named constants used
- [ ] Error handling: fail fast, fail loud — no silent `catch {}`

### Idiomatic patterns

Write idiomatic code for each language. Common AI-generated anti-patterns:
- [ ] Sequential awaits on independent calls → use concurrent/parallel execution
- [ ] Loop + await → use async map/batch operations
- [ ] Loading all data into memory then filtering → use server-side/query-level filtering
- [ ] Acronyms in names (`ra`, `exp`) → use full names (`resource_account`, `experiment`)

### Verdicts

| Verdict | Criteria |
|---------|----------|
| **PASS** | All checks pass |
| **REVISE** | Non-critical issues (naming, minor DRY, style nits) |
| **BLOCK** | AI slop present, no tests for new behavior, or SOLID violation |
