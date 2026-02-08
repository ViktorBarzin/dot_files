---
name: clean-code-craftsman
description: |
  Enforces high-quality software engineering practices when writing code, based on
  principles from Robert C. Martin (Clean Code, Clean Architecture), John Ousterhout
  (A Philosophy of Software Design), Kent Beck (Simple Design, TDD), Martin Fowler
  (Refactoring), and The Pragmatic Programmer. Triggers: (1) Before writing any
  non-trivial code, (2) during code reviews, (3) when refactoring, (4) when the user
  asks for "clean" or "production-quality" code. Covers naming, function design, SOLID,
  deep modules, error handling, testing, and code structure. Primary languages: Python
  and TypeScript.
author: Claude Code
version: 1.1.0
date: 2026-02-07
---

# Clean Code Craftsman

You write code as a craftsman. Every function, every name, every abstraction is a
deliberate act of communication to the next developer who reads it — including
future-you. Quality is not a phase; it is woven into every keystroke.

## When This Skill Activates

Apply these principles **every time you write or modify code**. This is not a checklist
you run at the end — it is how you think while coding.

---

## 1. Naming Is Design

> "You should name a variable using the same care with which you name a first-born child."
> — Robert C. Martin

Names are the primary vehicle of intent in code. A good name eliminates the need for
a comment. A bad name is a tiny lie that compounds into confusion.

### Rules

- **Reveal intent**: The name should answer why it exists, what it does, and how it is
  used. If a name requires a comment, the name is wrong.
- **Make meaningful distinctions**: `accountList` vs `accounts` vs `accountGroup` — each
  must mean something different, or collapse them into one.
- **Use domain vocabulary**: Name things using the language of the problem domain
  (Ubiquitous Language). If the business calls it a "claim", don't call it a "request".
- **Verb phrases for functions**: `fetch_listings`, `calculate_route`, `validateAddress`.
  Functions do things; their names should say what.
- **Noun phrases for classes and variables**: `ListingRepository`, `transit_route`,
  `priceRange`.
- **Avoid encodings**: No Hungarian notation, no type prefixes (`strName`, `iCount`),
  no member prefixes (`m_`). Modern editors and type systems make these redundant.
- **Length proportional to scope**: Loop counters can be `i`. Module-level constants
  should be `MAX_RETRY_ATTEMPTS`. The wider the scope, the more descriptive the name.
- **Searchable names**: Avoid single-letter names and magic numbers outside the
  tightest scopes. `RESULTS_PER_PAGE = 25` beats a bare `25`.
- **Don't be cute**: `whack()` instead of `kill()`? No. Clarity over cleverness.
- **One word per concept**: Pick `fetch`, `retrieve`, or `get` and stick with it
  throughout the codebase. Don't use all three to mean the same thing.

### Python

```python
# BAD: What does this do? What's d? What's 7?
def calc(d: list[dict]) -> list[dict]:
    return [x for x in d if x["s"] >= 7]

# GOOD: Every name tells you exactly what's happening
MIN_LISTING_SCORE = 7

def filter_high_scoring_listings(listings: list[Listing]) -> list[Listing]:
    return [listing for listing in listings if listing.score >= MIN_LISTING_SCORE]
```

### TypeScript

```typescript
// BAD: Cryptic, forces reader into the implementation
const proc = (d: any[], f: boolean) => d.filter(x => f ? x.a : x.b);

// GOOD: Self-documenting
function filterListingsByAvailability(
  listings: Listing[],
  status: AvailabilityStatus,
): Listing[] {
  return listings.filter((listing) => listing.availability === status);
}
```

### Smell Test

If you read a name and need to look at the implementation to understand what it does,
rename it.

---

## 2. Functions

> "The first rule of functions is that they should be small. The second rule is that
> they should be smaller than that." — Robert C. Martin

> "Functions should do one thing. They should do it well. They should do it only."
> — Robert C. Martin

### Rules

- **Small**: A function should fit on a screen. If you're scrolling, it's too long.
  Aim for 5-20 lines. This is not a hard rule — some algorithms are inherently longer —
  but it is the default.
- **One level of abstraction**: A function should not mix high-level orchestration
  with low-level details. Extract the low-level work into well-named helper functions.
- **Single Responsibility**: A function does one thing. If you describe what a function
  does and use the word "and", it does two things. Split it.
- **Few arguments**: Zero is ideal. One is good. Two is acceptable. Three requires
  justification. More than three — introduce a parameter object or rethink the design.
- **No side effects**: A function named `check_password` should not also initialize
  a session. If it must do both, name it `check_password_and_init_session` — then realize
  that name is a smell and refactor.
- **Command-Query Separation**: Functions should either do something (command) or
  answer something (query), not both.
- **Guard clauses for preconditions**: Handle edge cases at the top and return early.
  This keeps the main logic at the lowest indentation level.
- **Don't Repeat Yourself (DRY)**: If you see the same 3+ lines in two places,
  extract a function. But don't create premature abstractions for coincidental
  similarity — wait until you see the pattern three times (Rule of Three).
- **No flag arguments**: A boolean parameter means the function does two things.
  Write two functions instead.

### Python

```python
# BAD: Too long, mixed abstraction levels, flag argument, multiple responsibilities
def process_listing(listing: dict, send_email: bool = False) -> None:
    if listing.get("price") and listing.get("address"):
        conn = sqlite3.connect("data/wrongmove.db")
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO listings (price, address, sqm) VALUES (?, ?, ?)",
            (listing["price"], listing["address"], listing.get("sqm", 0)),
        )
        conn.commit()
        conn.close()
        if send_email:
            import smtplib
            server = smtplib.SMTP("smtp.gmail.com", 587)
            server.starttls()
            # ... 20 more lines of email sending
            server.quit()

# GOOD: Each function does one thing, clear names, no flags
def save_listing(listing: Listing, repository: ListingRepository) -> None:
    repository.insert(listing)

def notify_new_listing(listing: Listing, notifier: EmailNotifier) -> None:
    notifier.send_new_listing_alert(listing)

def process_new_listing(
    listing: Listing,
    repository: ListingRepository,
    notifier: EmailNotifier,
) -> None:
    save_listing(listing, repository)
    notify_new_listing(listing, notifier)
```

```python
# BAD: Deeply nested, no guard clauses
def calculate_price_per_sqm(listing: Listing) -> float | None:
    if listing is not None:
        if listing.price is not None:
            if listing.square_meters is not None:
                if listing.square_meters > 0:
                    return listing.price / listing.square_meters
                else:
                    return None
            else:
                return None
        else:
            return None
    else:
        return None

# GOOD: Guard clauses, flat structure, happy path at lowest indentation
def calculate_price_per_sqm(listing: Listing) -> float | None:
    if listing.price is None or listing.square_meters is None:
        return None
    if listing.square_meters <= 0:
        return None
    return listing.price / listing.square_meters
```

### TypeScript

```typescript
// BAD: Flag argument, mixed concerns
async function getListings(includeArchived: boolean): Promise<Listing[]> {
  // ...
}

// GOOD: Two functions, each does one thing
async function getActiveListings(): Promise<Listing[]> {
  return listingRepository.findByStatus("active");
}

async function getArchivedListings(): Promise<Listing[]> {
  return listingRepository.findByStatus("archived");
}
```

```typescript
// BAD: Too many parameters
function createListing(
  price: number,
  address: string,
  bedrooms: number,
  bathrooms: number,
  sqm: number,
  type: string,
  district: string,
): Listing { /* ... */ }

// GOOD: Parameter object
interface CreateListingParams {
  price: number;
  address: string;
  bedrooms: number;
  bathrooms: number;
  squareMeters: number;
  propertyType: PropertyType;
  district: District;
}

function createListing(params: CreateListingParams): Listing { /* ... */ }
```

### The Stepdown Rule

Code should read like a top-down narrative. Each function should be followed by the
functions it calls, at the next level of abstraction. A reader should be able to read
the code from top to bottom, understanding each level before diving deeper.

---

## 3. Deep Modules, Not Shallow Ones

> "The best modules are those whose interfaces are much simpler than their
> implementations." — John Ousterhout

### The Depth Principle

A module's value is the functionality it provides minus the complexity of its interface.

- **Deep module**: Simple interface, rich functionality. The Unix file I/O API
  (`open`, `read`, `write`, `close`) hides enormous complexity behind five calls.
- **Shallow module**: Complex interface relative to what it does. A class with 15
  methods that each delegate to one other call adds complexity without hiding any.

### Rules

- **Pull complexity downward**: When choosing where to put complexity, push it into the
  implementation, not into the interface. Make the caller's life simple.
- **Information hiding**: Each module should encapsulate design decisions that are likely
  to change. The interface exposes *what*, never *how*.
- **Avoid pass-through methods**: A method that does nothing but forward to another
  method is a sign of a shallow decomposition. Collapse the layers.
- **Avoid pass-through variables**: Threading a variable through multiple layers just to
  reach the one place that needs it is a design smell. Consider dependency injection or
  context objects.
- **General-purpose interfaces**: A somewhat general interface is often simpler and
  deeper than a special-purpose one. Design for the common case, not every possible use.
- **Define errors out of existence**: Instead of throwing an error for "file not found
  on delete," just make delete idempotent. Fewer error paths = less complexity.

### Python

```python
# BAD: Shallow — every method is a trivial pass-through, caller must orchestrate
class ListingExporter:
    def open_file(self, path: str) -> IO: ...
    def write_header(self, file: IO, columns: list[str]) -> None: ...
    def write_row(self, file: IO, listing: Listing) -> None: ...
    def close_file(self, file: IO) -> None: ...

# Caller has to know the entire protocol:
exporter = ListingExporter()
f = exporter.open_file("out.csv")
exporter.write_header(f, ["price", "sqm"])
for listing in listings:
    exporter.write_row(f, listing)
exporter.close_file(f)

# GOOD: Deep — simple interface hides all the complexity
class ListingExporter:
    def export_to_csv(self, listings: list[Listing], path: Path) -> None:
        """Export listings to CSV. Handles file lifecycle, headers, encoding."""
        ...

# Caller just says what they want:
exporter.export_to_csv(listings, Path("out.csv"))
```

### TypeScript

```typescript
// BAD: Shallow wrapper that adds nothing — just pass-through
class ApiClient {
  private axios: AxiosInstance;

  get(url: string): Promise<AxiosResponse> {
    return this.axios.get(url);
  }
  post(url: string, data: unknown): Promise<AxiosResponse> {
    return this.axios.post(url, data);
  }
  // ... every axios method duplicated
}

// GOOD: Deep module — simple interface hiding retry, auth, error mapping
class ListingApiClient {
  async fetchListings(query: ListingQuery): Promise<Listing[]> {
    // Internally handles: auth headers, pagination, retry with backoff,
    // rate limiting, response parsing, error mapping to domain errors
  }

  async fetchListingDetails(id: string): Promise<ListingDetails> {
    // Same concerns handled internally, caller doesn't know or care
  }
}
```

---

## 4. SOLID Principles

### Single Responsibility Principle (SRP)

"A module should be responsible to one, and only one, actor."

Not "do one thing" (that's for functions) — a *class* should have one reason to change,
meaning one stakeholder whose requirements could cause it to be modified.

**Smell**: When you change a class for reason A and it breaks something related to
reason B, SRP is violated.

#### Python

```python
# BAD: This class changes for three different reasons
class Listing:
    def calculate_price_per_sqm(self) -> float: ...     # business logic
    def to_json(self) -> str: ...                        # serialization
    def save_to_database(self, db: Session) -> None: ... # persistence

# GOOD: Each class has one reason to change
class Listing:
    def calculate_price_per_sqm(self) -> float: ...

class ListingSerializer:
    def to_json(self, listing: Listing) -> str: ...

class ListingRepository:
    def save(self, listing: Listing) -> None: ...
```

### Open/Closed Principle (OCP)

"Open for extension, closed for modification."

You should be able to add new behavior without changing existing code. Use polymorphism,
strategy patterns, and plugin architectures. But don't over-engineer for hypothetical
extensions — apply when you see a concrete pattern of change.

#### TypeScript

```typescript
// BAD: Adding a new export format requires modifying this function
function exportListings(listings: Listing[], format: string): string {
  if (format === "csv") { /* ... */ }
  else if (format === "json") { /* ... */ }
  else if (format === "geojson") { /* ... */ }
  // Every new format = another branch here
}

// GOOD: New formats are added by implementing an interface, not editing code
interface ListingExporter {
  export(listings: Listing[]): string;
}

class CsvExporter implements ListingExporter {
  export(listings: Listing[]): string { /* ... */ }
}

class GeoJsonExporter implements ListingExporter {
  export(listings: Listing[]): string { /* ... */ }
}

function exportListings(listings: Listing[], exporter: ListingExporter): string {
  return exporter.export(listings);
}
```

### Liskov Substitution Principle (LSP)

Subtypes must be substitutable for their base types without altering correctness.

#### Python

```python
# BAD: Violates LSP — Square changes the contract of Rectangle
class Rectangle:
    def __init__(self, width: float, height: float) -> None:
        self.width = width
        self.height = height

    def area(self) -> float:
        return self.width * self.height

class Square(Rectangle):
    def __init__(self, side: float) -> None:
        super().__init__(side, side)

    # Setting width without height (or vice versa) breaks the square invariant.
    # Code that expects Rectangle behavior will produce wrong results.

# GOOD: Use a common interface without forcing an "is-a" relationship
from abc import ABC, abstractmethod

class Shape(ABC):
    @abstractmethod
    def area(self) -> float: ...

class Rectangle(Shape):
    def __init__(self, width: float, height: float) -> None:
        self.width = width
        self.height = height

    def area(self) -> float:
        return self.width * self.height

class Square(Shape):
    def __init__(self, side: float) -> None:
        self.side = side

    def area(self) -> float:
        return self.side ** 2
```

### Interface Segregation Principle (ISP)

No client should be forced to depend on methods it does not use.

Prefer many small, focused interfaces over one fat interface.

#### TypeScript

```typescript
// BAD: Forces every listing source to implement methods it doesn't support
interface ListingSource {
  fetchListings(query: Query): Promise<Listing[]>;
  fetchFloorplans(listingId: string): Promise<Image[]>;
  calculateRoute(from: LatLng, to: LatLng): Promise<Route>;
  sendNotification(listing: Listing): Promise<void>;
}

// GOOD: Segregated interfaces — implement only what you provide
interface ListingFetcher {
  fetchListings(query: Query): Promise<Listing[]>;
}

interface FloorplanProvider {
  fetchFloorplans(listingId: string): Promise<Image[]>;
}

interface RouteCalculator {
  calculateRoute(from: LatLng, to: LatLng): Promise<Route>;
}
```

### Dependency Inversion Principle (DIP)

High-level modules should not depend on low-level modules. Both should depend on
abstractions.

#### Python

```python
# BAD: Business logic directly depends on infrastructure
from sqlalchemy.orm import Session

class ListingService:
    def __init__(self) -> None:
        self.db = Session()  # Hardcoded dependency on SQLAlchemy

    def get_affordable_listings(self, max_price: int) -> list[Listing]:
        return self.db.query(Listing).filter(Listing.price <= max_price).all()

# GOOD: Business logic depends on an abstraction
from abc import ABC, abstractmethod

class ListingRepository(ABC):
    @abstractmethod
    def find_by_max_price(self, max_price: int) -> list[Listing]: ...

class SqlAlchemyListingRepository(ListingRepository):
    def __init__(self, session: Session) -> None:
        self._session = session

    def find_by_max_price(self, max_price: int) -> list[Listing]:
        return self._session.query(Listing).filter(Listing.price <= max_price).all()

class ListingService:
    def __init__(self, repository: ListingRepository) -> None:
        self._repository = repository  # Depends on abstraction, not SQLAlchemy

    def get_affordable_listings(self, max_price: int) -> list[Listing]:
        return self._repository.find_by_max_price(max_price)
```

---

## 5. Error Handling

> "Error handling is important, but if it obscures logic, it's wrong."
> — Robert C. Martin

### Rules

- **Fail fast**: Detect errors at the earliest possible point. A corrupted input should
  be caught at the boundary, not three layers deep where it causes a cryptic failure.
- **Guard clauses at the top**: Validate preconditions first, return or raise early.
  The happy path should be the least-indented code.
- **Exceptions for exceptional things**: Don't use exceptions for control flow. If a
  user enters an invalid email, that's expected input — handle it with a validation
  return, not a thrown exception.
- **Don't return null/None**: Returning null forces every caller to add a null check.
  Return an empty collection, a Null Object, or use Optional types.
- **Don't pass null/None**: If a function doesn't expect null, passing it is a bug
  waiting to happen. Fix the caller, don't add a null guard to every function.
- **Write informative error messages**: Include the context: what was being attempted,
  what the actual value was, and what was expected.
- **Catch at the right level**: Catch exceptions where you can actually do something
  meaningful about them. Don't catch-and-rethrow just to add a log line.

### Python

```python
# BAD: Returns None, vague error, catches too broadly
def fetch_listing(listing_id: str) -> dict | None:
    try:
        response = requests.get(f"{API_URL}/listings/{listing_id}")
        return response.json()
    except Exception:
        logger.error("Something went wrong")
        return None

# GOOD: Specific exceptions, informative messages, no None return
class ListingNotFoundError(Exception):
    pass

class ListingFetchError(Exception):
    pass

def fetch_listing(listing_id: str) -> Listing:
    try:
        response = requests.get(
            f"{API_URL}/listings/{listing_id}",
            timeout=10,
        )
    except requests.ConnectionError as e:
        raise ListingFetchError(
            f"Failed to connect to API while fetching listing {listing_id}"
        ) from e

    if response.status_code == 404:
        raise ListingNotFoundError(
            f"Listing {listing_id} not found on Rightmove"
        )

    response.raise_for_status()
    return Listing.from_api_response(response.json())
```

```python
# BAD: Exception for control flow
def find_user_district(address: str) -> str:
    try:
        return district_lookup[address]
    except KeyError:
        raise DistrictNotFoundError(address)

# Caller:
try:
    district = find_user_district(address)
except DistrictNotFoundError:
    district = "Unknown"

# GOOD: Expected case handled with normal control flow
def find_user_district(address: str) -> str:
    return district_lookup.get(address, "Unknown")
```

### TypeScript

```typescript
// BAD: Returns undefined, caller must guess what went wrong
async function getListingDetails(id: string): Promise<ListingDetails | undefined> {
  try {
    const response = await fetch(`/api/listings/${id}`);
    return await response.json();
  } catch {
    return undefined;
  }
}

// GOOD: Typed errors, informative messages, never returns undefined
class ListingNotFoundError extends Error {
  constructor(public readonly listingId: string) {
    super(`Listing ${listingId} not found`);
    this.name = "ListingNotFoundError";
  }
}

async function getListingDetails(id: string): Promise<ListingDetails> {
  const response = await fetch(`/api/listings/${id}`);

  if (response.status === 404) {
    throw new ListingNotFoundError(id);
  }

  if (!response.ok) {
    throw new Error(
      `Failed to fetch listing ${id}: ${response.status} ${response.statusText}`,
    );
  }

  return (await response.json()) as ListingDetails;
}
```

```typescript
// BAD: Returns empty array for errors — caller can't distinguish "no results" from "failed"
async function searchListings(query: Query): Promise<Listing[]> {
  try {
    return await api.search(query);
  } catch {
    return [];  // Was this an empty search or a network failure?
  }
}

// GOOD: Use a Result type to distinguish success from failure
type Result<T, E = Error> =
  | { ok: true; value: T }
  | { ok: false; error: E };

async function searchListings(query: Query): Promise<Result<Listing[]>> {
  try {
    const listings = await api.search(query);
    return { ok: true, value: listings };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error : new Error(String(error)) };
  }
}
```

---

## 6. Code Structure and Dependencies

### The Dependency Rule (Clean Architecture)

Source code dependencies must point inward — from outer layers (frameworks, UI, DB)
toward inner layers (business rules, domain entities). Never let the core domain
know about infrastructure details.

```
Frameworks & Drivers  →  Interface Adapters  →  Use Cases  →  Entities
        (outer)                                              (inner)
```

### Separation of Concerns

Each module, class, and function should address a single concern. UI code doesn't
calculate business rules. Database code doesn't format user-facing messages.

### Composition Over Inheritance

Favor composing objects over inheriting behavior. Inheritance creates tight coupling
and fragile hierarchies. Composition lets you swap behaviors at runtime and avoids
the "diamond problem."

Use inheritance for genuine "is-a" relationships within a single conceptual hierarchy.
Use composition for "has-a" or "uses-a" relationships.

#### Python

```python
# BAD: Inheritance for code reuse — fragile, tightly coupled
class BaseProcessor:
    def fetch(self): ...
    def validate(self): ...
    def save(self): ...
    def notify(self): ...

class ListingProcessor(BaseProcessor):
    def process(self):
        self.fetch()     # Which fetch? What if I need a different one?
        self.validate()
        self.save()
        self.notify()

# GOOD: Composition — flexible, each piece is independent and swappable
class ListingProcessor:
    def __init__(
        self,
        fetcher: ListingFetcher,
        validator: ListingValidator,
        repository: ListingRepository,
        notifier: Notifier,
    ) -> None:
        self._fetcher = fetcher
        self._validator = validator
        self._repository = repository
        self._notifier = notifier

    def process(self, listing_id: str) -> None:
        listing = self._fetcher.fetch(listing_id)
        self._validator.validate(listing)
        self._repository.save(listing)
        self._notifier.notify_new_listing(listing)
```

### Law of Demeter

A method should only call methods on:
1. Its own object (`self`)
2. Objects passed as arguments
3. Objects it creates
4. Its direct component objects

#### TypeScript

```typescript
// BAD: Reaching through a chain of objects
function getListingCity(listing: Listing): string {
  return listing.getProperty().getAddress().getCity();
}

// GOOD: Ask the object directly
function getListingCity(listing: Listing): string {
  return listing.city;  // Listing exposes what callers need
}
```

### Tell, Don't Ask

Don't ask an object for data, make a decision, then tell it what to do. Instead, tell
the object to do the work.

#### Python

```python
# BAD: Ask, decide externally, then act
if listing.price is not None and listing.square_meters is not None:
    if listing.square_meters > 0:
        listing.price_per_sqm = listing.price / listing.square_meters

# GOOD: Tell the object to do its own work
listing.calculate_price_per_sqm()  # Listing owns this logic internally
```

---

## 7. Testing

> "Code without tests is bad code. It doesn't matter how well written it is."
> — Michael Feathers

### Kent Beck's First Rule of Simple Design

**Pass all the tests.** Everything else follows. Untested code is uncertain code.

### Rules

- **Test behavior, not implementation**: Tests should verify *what* code does, not *how*
  it does it. If you refactor internals and tests break, the tests are too coupled.
- **Arrange-Act-Assert**: Every test has three clear sections: set up the state, perform
  the action, verify the outcome. One blank line between each.
- **One assertion per test** (as a guideline): Each test should verify one logical
  concept. Multiple assertions are fine when they verify aspects of the same behavior.
- **Fast**: Tests that take seconds instead of milliseconds don't get run. Keep the
  feedback loop tight.
- **Independent**: Tests must not depend on each other or on execution order. No shared
  mutable state between tests.
- **Repeatable**: Same result every time, in any environment. No dependence on network,
  clock, or file system state.
- **Descriptive test names**: The name IS the documentation. A failing test name should
  tell you exactly what's broken without reading the test body.
- **Test the boundaries**: Zero, one, many. Empty, null, maximum. Off-by-one. Negative.
  Boundary conditions are where bugs hide.
- **Use test doubles wisely**: Mock external dependencies (APIs, databases, clocks),
  not internal collaborators. Over-mocking creates brittle tests that test nothing.

### Python (pytest)

```python
# BAD: Vague name, tests multiple things, no clear structure
def test_listing():
    listing = Listing(price=500000, square_meters=50)
    assert listing.price_per_sqm == 10000
    listing2 = Listing(price=None, square_meters=50)
    assert listing2.price_per_sqm is None
    listing3 = Listing(price=500000, square_meters=0)
    assert listing3.price_per_sqm is None

# GOOD: One behavior per test, descriptive names, Arrange-Act-Assert
def test_price_per_sqm_divides_price_by_area():
    listing = Listing(price=500_000, square_meters=50)

    result = listing.calculate_price_per_sqm()

    assert result == 10_000

def test_price_per_sqm_returns_none_when_price_missing():
    listing = Listing(price=None, square_meters=50)

    result = listing.calculate_price_per_sqm()

    assert result is None

def test_price_per_sqm_returns_none_when_area_is_zero():
    listing = Listing(price=500_000, square_meters=0)

    result = listing.calculate_price_per_sqm()

    assert result is None
```

```python
# BAD: Mocking internals — test is coupled to implementation
def test_fetch_listings(mocker):
    mock_session = mocker.patch("requests.Session")
    mock_response = mocker.Mock()
    mock_response.json.return_value = [{"id": "1"}]
    mock_session.return_value.get.return_value = mock_response

    result = fetch_listings(Query(min_price=1000))

    mock_session.return_value.get.assert_called_once_with(
        "https://api.rightmove.co.uk/api/rent/find",
        params={"minPrice": 1000},
    )
    # This test breaks if you change the HTTP library, URL structure, or param names

# GOOD: Mock at the boundary, test the behavior
def test_fetch_listings_returns_parsed_listings(fake_api: FakeRightmoveApi):
    fake_api.add_listing(id="123", price=2000, bedrooms=2)

    listings = fetch_listings(Query(min_price=1000))

    assert len(listings) == 1
    assert listings[0].id == "123"
    assert listings[0].price == 2000
```

### TypeScript (vitest/jest)

```typescript
// BAD: "test1", no structure
test("test1", () => {
  const svc = new ListingService(mockRepo);
  expect(svc.getAffordable(3000).length).toBe(2);
  expect(svc.getAffordable(3000)[0].price).toBeLessThanOrEqual(3000);
});

// GOOD: Descriptive name, clear AAA structure
describe("ListingService", () => {
  describe("getAffordableListings", () => {
    it("returns only listings at or below the price threshold", () => {
      const repository = new InMemoryListingRepository([
        createListing({ price: 2000 }),
        createListing({ price: 3000 }),
        createListing({ price: 5000 }),
      ]);
      const service = new ListingService(repository);

      const results = service.getAffordableListings(3000);

      expect(results).toHaveLength(2);
      expect(results.every((l) => l.price <= 3000)).toBe(true);
    });

    it("returns empty array when no listings are affordable", () => {
      const repository = new InMemoryListingRepository([
        createListing({ price: 5000 }),
      ]);
      const service = new ListingService(repository);

      const results = service.getAffordableListings(1000);

      expect(results).toHaveLength(0);
    });
  });
});
```

### The Testing Pyramid

1. **Many unit tests**: Fast, isolated, testing individual functions and classes
2. **Some integration tests**: Verify components work together correctly
3. **Few end-to-end tests**: Verify critical user journeys through the whole system

---

## 8. Kent Beck's Four Rules of Simple Design

In priority order:

1. **Passes all the tests** — Working software is the baseline. Nothing else matters if
   the code doesn't work.
2. **Reveals intention** — Code should communicate its purpose clearly. Another developer
   should understand *why* each piece exists.
3. **No duplication** — Every piece of knowledge should have a single, authoritative
   representation. DRY applies to concepts, not just characters.
4. **Fewest elements** — Remove anything that doesn't serve rules 1-3. No speculative
   generality. No unused abstractions. The simplest code that could work.

### Python

```python
# Violates Rule 2 (intention) and Rule 4 (fewest elements)
class AbstractListingFilterStrategyFactory:
    def create_filter_strategy(self, filter_type: str) -> AbstractFilterStrategy:
        ...

# Follows all four rules — simple, clear, tested, no duplication
def filter_by_price(listings: list[Listing], max_price: int) -> list[Listing]:
    return [l for l in listings if l.price <= max_price]
```

### TypeScript

```typescript
// Violates Rule 3 (duplication of knowledge)
function formatRentPrice(price: number): string {
  return `£${price.toLocaleString()} pcm`;
}
function formatBuyPrice(price: number): string {
  return `£${price.toLocaleString()}`;
}

// Follows all rules — one representation of "format price"
function formatPrice(price: number, suffix?: string): string {
  const formatted = `£${price.toLocaleString()}`;
  return suffix ? `${formatted} ${suffix}` : formatted;
}
```

---

## 9. Pragmatic Principles

From Hunt & Thomas:

- **DRY (Don't Repeat Yourself)**: Every piece of knowledge must have a single,
  unambiguous, authoritative representation within a system.
- **Orthogonality**: Components should be independent. Changing one should not affect
  others. If you change the database, the UI should not need to change.
- **Reversibility**: Don't bake in decisions that are hard to undo. Abstract external
  dependencies so you can swap them.
- **Tracer Bullets**: Build a thin end-to-end slice first. Get something working across
  all layers, then fill in the details. This reduces integration risk.
- **Broken Windows Theory**: Don't tolerate "broken windows" — bad designs, wrong
  decisions, poor code. Fix them as you find them, or they multiply.
  (This is Uncle Bob's Boy Scout Rule: "Leave the code cleaner than you found it.")
- **Good Enough Software**: Know when to stop. Don't over-polish at the expense of
  shipping. Perfection is the enemy of "done" — but sloppy is the enemy of "maintainable".

### Python — DRY violation and fix

```python
# BAD: Validation logic duplicated in two places
class RentListingService:
    def create(self, data: dict) -> RentListing:
        if data["price"] <= 0:
            raise ValueError("Price must be positive")
        if not data["address"]:
            raise ValueError("Address is required")
        ...

class BuyListingService:
    def create(self, data: dict) -> BuyListing:
        if data["price"] <= 0:
            raise ValueError("Price must be positive")
        if not data["address"]:
            raise ValueError("Address is required")
        ...

# GOOD: Single source of truth for validation
class ListingValidator:
    def validate(self, data: dict) -> None:
        if data["price"] <= 0:
            raise ValueError("Price must be positive")
        if not data["address"]:
            raise ValueError("Address is required")

class RentListingService:
    def __init__(self, validator: ListingValidator) -> None:
        self._validator = validator

    def create(self, data: dict) -> RentListing:
        self._validator.validate(data)
        ...
```

### TypeScript — Orthogonality

```typescript
// BAD: UI component knows about database schema
function ListingCard({ listing }: { listing: any }) {
  const price = listing.price_in_pence / 100; // knows DB stores pence
  const sqm = listing.floor_area_sqm ?? listing.epc_floor_area; // knows DB fallback logic
  return <div>{price} — {sqm}m²</div>;
}

// GOOD: UI receives a view model, doesn't know storage details
interface ListingCardProps {
  displayPrice: string;
  squareMeters: number | null;
}

function ListingCard({ displayPrice, squareMeters }: ListingCardProps) {
  return <div>{displayPrice} — {squareMeters}m²</div>;
}
```

---

## 10. Refactoring Discipline

From Martin Fowler:

- **Refactor continuously, not in big batches**: Small, frequent improvements integrated
  into daily work beat scheduled "refactoring sprints."
- **Each refactoring is a tiny, behavior-preserving change**: Run tests after every
  step. If a test breaks, undo and take a smaller step.
- **Code smells drive refactoring**: Don't refactor on a whim. Refactor when you smell:

| Smell | Symptom | Refactoring |
|---|---|---|
| **Long Method** | Scrolling to read a function | Extract Method |
| **Feature Envy** | Method uses another class's data more than its own | Move Method |
| **Data Clumps** | Same group of fields travel together | Extract Class / parameter object |
| **Primitive Obsession** | Strings/ints for domain concepts | Replace with Value Object |
| **Shotgun Surgery** | One change touches many files | Move / Inline to consolidate |
| **Divergent Change** | One class changes for unrelated reasons | Extract Class (SRP) |
| **Switch on type** | `if isinstance` / `switch(type)` chains | Replace with Polymorphism |

### Python — Primitive Obsession → Value Object

```python
# BAD: Price is just a float, no domain meaning
def apply_discount(price: float, discount_pct: float) -> float:
    return price * (1 - discount_pct / 100)

# What currency? Can it be negative? Is discount 0-100 or 0-1?

# GOOD: Value object encapsulates rules and meaning
@dataclass(frozen=True)
class Price:
    amount_pence: int
    currency: str = "GBP"

    def apply_discount(self, discount: Discount) -> "Price":
        reduced = int(self.amount_pence * (1 - discount.as_fraction()))
        return Price(amount_pence=max(0, reduced), currency=self.currency)

    def format(self) -> str:
        pounds = self.amount_pence / 100
        return f"£{pounds:,.2f}"

@dataclass(frozen=True)
class Discount:
    percentage: int  # 0-100

    def __post_init__(self) -> None:
        if not 0 <= self.percentage <= 100:
            raise ValueError(f"Discount must be 0-100, got {self.percentage}")

    def as_fraction(self) -> float:
        return self.percentage / 100
```

### TypeScript — Extract Method

```typescript
// BAD: Long function mixing abstraction levels
async function processListing(raw: RawListing): Promise<void> {
  // 15 lines of validation...
  // 10 lines of geocoding...
  // 20 lines of image processing...
  // 10 lines of database insert...
}

// GOOD: Each step is a named function at one level of abstraction
async function processListing(raw: RawListing): Promise<void> {
  const validated = validateListing(raw);
  const geocoded = await geocodeAddress(validated.address);
  const images = await processFloorplanImages(validated.imageUrls);
  await saveListing({ ...validated, coordinates: geocoded, images });
}
```

---

## 11. Working with Existing Code

From Michael Feathers:

- **Characterization tests first**: Before changing legacy code, write tests that
  capture its current behavior — even if that behavior is wrong. Now you have a safety
  net.
- **Find seams**: A seam is a place where you can alter behavior without editing the
  code in that place. Constructor injection, method overriding, and configuration
  switches are common seams.
- **The Strangler Fig Pattern**: When rewriting a system, wrap the old system with a new
  interface and incrementally replace pieces. Don't do big-bang rewrites.
- **Make the change easy, then make the easy change**: If the code isn't structured for
  the change you need, first refactor until the change is trivial, then make it.

### Python — Characterization test

```python
# Before modifying calculate_score(), lock down its current behavior
def test_calculate_score_characterization():
    """Captures existing behavior. If this fails after a refactor, investigate."""
    listing = Listing(
        price=350_000,
        square_meters=75,
        bedrooms=2,
        transit_minutes=25,
    )

    score = calculate_score(listing)

    # This is what the function currently returns — we're not asserting it's
    # correct, we're asserting it hasn't changed unexpectedly.
    assert score == 7.3
```

### TypeScript — Seam via constructor injection

```typescript
// Legacy code with hardcoded dependency (no seam)
class ListingImporter {
  async import(): Promise<void> {
    const response = await fetch("https://api.rightmove.co.uk/listings");
    // ...
  }
}

// Introduce a seam: inject the dependency so tests can substitute it
class ListingImporter {
  constructor(private readonly httpClient: HttpClient = new FetchHttpClient()) {}

  async import(): Promise<void> {
    const response = await this.httpClient.get("/listings");
    // ...
  }
}

// Now testable without hitting the network
const importer = new ListingImporter(new FakeHttpClient());
```

---

## Pre-Flight Checklist

Before submitting any code, mentally verify:

- [ ] **Can I explain every name without referring to the implementation?**
- [ ] **Does each function do exactly one thing?**
- [ ] **Are there any functions longer than ~20 lines that could be decomposed?**
- [ ] **Am I mixing levels of abstraction in any function?**
- [ ] **Are dependencies pointing inward (toward the domain)?**
- [ ] **Would a new team member understand this code without me explaining it?**
- [ ] **Are error cases handled at the right level with informative messages?**
- [ ] **Is there any duplication that represents duplicated knowledge (not coincidence)?**
- [ ] **Could I remove any code and still pass all tests?** (If yes, remove it.)
- [ ] **Have I left the code cleaner than I found it?**

---

## References

- Robert C. Martin, [*Clean Code: A Handbook of Agile Software Craftsmanship*](https://www.oreilly.com/library/view/clean-code-a/9780135398586/) (2008)
- Robert C. Martin, *Clean Architecture* (2017)
- John Ousterhout, *A Philosophy of Software Design* (2018)
- Kent Beck, *Four Rules of Simple Design* (late 1990s, XP)
- Martin Fowler, *Refactoring: Improving the Design of Existing Code* (1999, 2nd ed. 2018)
- Andrew Hunt & David Thomas, *The Pragmatic Programmer* (1999, 20th Anniversary Ed. 2019)
- Michael Feathers, *Working Effectively with Legacy Code* (2004)
- [Clean Code Summary (GitHub Gist)](https://gist.github.com/wojteklu/73c6914cc446146b8b533c0988cf8d29)
- [Clean Architecture Summary (GitHub Gist)](https://gist.github.com/ygrenzinger/14812a56b9221c9feca0b3621518635b)
- [A Philosophy of Software Design - Review](https://www.mattduck.com/2021-04-a-philosophy-of-software-design.html)
- [Kent Beck's 4 Rules of Simple Design](https://DEV.to/jmir17/the-4-rules-of-simple-design-14eo)
