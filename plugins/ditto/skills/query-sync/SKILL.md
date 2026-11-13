---
name: query-sync
description: "Ditto SDK DQL reads and writes, subscriptions, and store observers (Flutter, JavaScript, Kotlin, Swift): query parameters, MISSING vs NULL, membership filters, subscription and observer lifecycle, ON ID CONFLICT upserts, JOIN, RETURNING. Use when writing or reviewing ditto.store.execute, ditto.sync.registerSubscription, registerObserver, or DQL in an app that uses Ditto, or when Ditto data does not sync or a Ditto query returns nothing."
---

# Ditto Query and Sync Patterns

DQL statements, subscriptions, and store observers: what syncs, what a query sees, and cheap observers and upserts. Targets Ditto SDK 5.2.0 in every SDK.

## Before You Apply

- Identify the project's SDK and version: Flutter (`ditto_live` in `pubspec.yaml` / `pubspec.lock`), JavaScript (`@dittolive/ditto` in `package.json`), Kotlin (`com.ditto:ditto-kotlin` in Gradle files), or Swift (`DittoSwift` in `Package.swift`, `Package.resolved`, or the Xcode project). These rules target SDK 5.2.0; for devices that still run 5.1.0, also apply `§ Known Issues in SDK 5.1.0`. **Note (SDK 5.1.0 and 5.2.0)** and **Note (SDK 5.1.0)** mark easy-to-miss behavior seen on those releases, with the safe pattern; **(SDK 5.1+)** / **(SDK 5.2+)** mark features introduced in that release.
- For API calls, Grep the outline of that SDK's page, `${CLAUDE_SKILL_DIR}/../guide/reference/best-practices/platforms/<sdk>.md` (`flutter`, `javascript`, `kotlin`, `swift`), with `^#{1,3} ` and read only the section you need, not the whole page; sections are named `<Topic> in <SDK>`. DQL examples: `examples/*.sql` (every SDK); API examples: `examples/<sdk>/`, with the same base names in every SDK.
- `§ <Heading>` cites the full guide: Grep the heading as a fixed string in `best-practices/` and `knowledge/` under `${CLAUDE_SKILL_DIR}/../guide/reference/`, then read that section.
- Report each finding at the severity of its item in `§ Anti-Pattern Checklist` (the checklist decides; Grep a phrase of the item there). The labels below rank the rules, not each item in them.

## Prevents

- DQL built with string interpolation; filters that silently drop documents (MISSING vs NULL, `IN (:values)`, `ANY ... SATISFIES`)
- "Synced data does not show": no subscription matches it, or none after a reopen
- Subscriptions rejected at registration or re-registered on every filter change
- Unreleased subscriptions and observers; Flutter `onChange` observers retaining every result
- Upserts that rewrite unchanged data; `JOIN` queries failing without an index; retained result objects

## Workflow

Data does not sync? First triage:
- No peer connects, `sync.start()` throws, or login fails: `sdk-setup`, section *Diagnose: Sync Never Starts or Devices Do Not Connect*.
- Peers connect but documents are missing: subscriptions here (rules 3 and 4). Evicted or deleted documents come back: `storage-lifecycle`.

Every DQL statement runs against the **local store**. Only `ditto.sync.registerSubscription` makes data sync from remote peers (while sync is running); `ditto.store.execute` (snapshot), `ditto.store.registerObserver` (live), and `ditto.store.transaction` read local data and never cause sync.

Subscriptions are long-lived, scoped by stable partition keys; observers and `execute` calls are short-lived and screen-specific. A result describes this device only: empty may mean nothing has synced yet or no subscription matches, not that data is absent (no defaults or uniqueness checks from it). Read synced data with an observer, not one `execute` after subscribing; subscribe to all a query, total, or `JOIN` reads. A returned write is known to be local only (`§ Monitoring Sync Status`).

`§ Where Queries Run`, `§ When Data Does Not Sync`, `§ When a Statement Fails or Returns Nothing`

A screen that shows synced data:

```
Progress:
- [ ] 1. Subscription: SELECT * FROM c WHERE <stable partition key> = :param, owned by an app/feature service
- [ ] 2. Indexes: CREATE INDEX IF NOT EXISTS at startup for filter, sort, and JOIN keys
- [ ] 3. Observer: registered once when the screen's owner starts (not in render code), with ORDER BY (+ _id tie-breaker) and LIMIT if large
- [ ] 4. Callback: copy row values into plain data or models; update UI state; no slow work
- [ ] 5. Cleanup: release the observer when its owner goes away; cancel subscriptions on logout or workspace change
```

## Rules

### 1. Pass values as parameters (CRITICAL)

Reference values with `:name` and pass them as arguments. Names are case-sensitive; a placeholder without an argument fails. Interpolation allows DQL injection, breaks on quotes and backslashes, and defeats the shared statement cache.
**✅ DO**: parameters for IDs, user input, dates, `LIMIT`/`OFFSET`, and whole documents (`INSERT INTO orders DOCUMENTS (:order)`); arrays for membership (`status IN :statuses`); plain JSON values (UTC date strings; *Arguments and value types in <SDK>*).
**❌ DON'T**: build statements with interpolation or concatenation; write `IN (:statuses)` (the array becomes one list element and nothing matches).

`§ Parameters and Literals` · Examples: [dql-queries-good.sql](examples/dql-queries-good.sql), [dql-queries-bad.sql](examples/dql-queries-bad.sql)

### 2. Treat MISSING and NULL explicitly in filters (CRITICAL)

A comparison with a missing or null field is neither true nor false, so the row is dropped.

| `WHERE` expression | Matches `false` | `null` | missing |
|---|---|---|---|
| `isDeleted != true` | ✓ | | | <!-- lint-ignore -->
| `coalesce(isDeleted, false) = false` | ✓ | ✓ | ✓ |
| `isDeleted IS NOT NULL` | ✓ | | ✓ | <!-- lint-ignore -->
| `isDeleted IS NOT MISSING` | ✓ | ✓ | |

**✅ DO**: filter optional booleans with `coalesce(field, default)` (`WHERE coalesce(isDeleted, false) = false`); test absence with `IS MISSING` / `IS NOT MISSING`; remove a field with `UNSET`.
**❌ DON'T**: use `field != true` or `NOT field` for "false or not set"; use `IS NOT NULL` to test existence. <!-- lint-ignore -->

`§ MISSING and NULL`

### 3. Subscribe with SELECT * and stable partition keys (CRITICAL)

A subscription selects whole documents from one collection: `SELECT * FROM <collection> [WHERE <condition>]`. `registerSubscription` fails for the features below, even before sync starts.

| Rejected in subscriptions | Do instead |
|---|---|
| Projections, aggregates, `DISTINCT`, `GROUP BY` | Subscribe with `SELECT *`; project in local queries |
| `JOIN` | Subscribe to each collection separately; join locally |
| `USE IDS` | `WHERE _id IN :ids` |
| `LIMIT`, `ORDER BY` | Sort and limit in the local query or observer |

Keep `DQL_RESTRICT_SUBSCRIPTIONS` at its default (`true`); `false` allows stateful `LIMIT`/`ORDER BY` subscriptions whose `LIMIT` bounds only the first download ([details](reference/subscriptions-and-observers.md#subscription-rules)). Bound what syncs with `WHERE` (a stable key or a time window).
**✅ DO**: filter by stable partition keys (tenant, store, region, team); use the same subscriptions on peers in the same role; keep predicates flat; give relay devices at least the subscriptions of the devices behind them.
**❌ DON'T**: subscribe to entire large collections "just in case" (except small reference data that every device needs); filter subscriptions on fields that change often (`status`, `assignee`): a document that stops matching stays as a stale copy that local queries return, without later edits or its deletion.

Soft delete: relaying devices keep flagged documents in their subscriptions; hide them locally with `coalesce(isDeleted, false) = false` (`storage-lifecycle`).

`§ Subscription Rules`, `§ Scope Balancing`, `§ Soft delete, subscriptions, and cleanup`

### 4. Own subscriptions in a long-lived service and cancel them (CRITICAL)

Changing subscriptions makes peers re-evaluate which documents to send; avoid changing them more often than about every 15 minutes.
**✅ DO**:
- Register at app start (every time Ditto opens; not persisted), after login, or on entering a workspace, in an app- or feature-level service; keep every subscription and release it (`cancel()`, `close()` in Kotlin) on logout or workspace change
- Change the **observer**, not the subscription, when the user changes a filter, search term, tab, or sort order
- Cancel subscriptions **before** evicting their data; cancelling alone does not delete local data

**❌ DON'T**: register in render code (`build()`, a SwiftUI `body`, a composable, a React render) or on every screen visit; drop a reference without releasing it (do not rely on garbage collection).

`sync.stop()` pauses subscriptions (resumed by `start()`); closing Ditto cancels them.

> **Note (SDK 5.1.0 and 5.2.0):** In Flutter, do not read `queryArguments`, `queryArgumentsJsonString`, or `queryArgumentsCborBytes` from `ditto.sync.subscriptions` elements; for subscriptions without arguments this ended the app or threw in testing. Read only `queryString` and `isCancelled`; keep your own references.

`§ Subscription Lifecycle`, `§ Sync stop, close, and inspection` · Examples: `subscription-lifecycle-good` and `subscription-lifecycle-bad` in `examples/<sdk>/`

### 5. Filter membership with IN :values (CRITICAL)

| Goal | Expression |
|---|---|
| Field equals one of several values | `status IN :statuses` (array parameter; can use an index) |
| Array field contains a value | `:tag IN tags` or `array_contains(tags, :tag)` (no index) |
| ❌ Array parameter in parentheses | `status IN (:statuses)` matches nothing |

> **Note (SDK 5.1.0 and 5.2.0):** `ANY ... SATISFIES ... END` in `WHERE` over a parameter or literal array returns no rows. Use `status IN :statuses` or `array_contains(:statuses, status)`. A subscription with it still syncs the documents; only the list is empty.

`§ Filtering by Membership`

### 6. Upsert with DO UPDATE_LOCAL_DIFF and update fields, not documents (CRITICAL)

| `ON ID CONFLICT` | Existing document |
|---|---|
| `FAIL` (default) | Statement fails |
| `DO NOTHING` | Unchanged |
| `DO UPDATE` | Supplied fields written even if identical (observers can fire again) |
| `DO UPDATE_LOCAL_DIFF` | Only differing fields written; nothing written if nothing changed |

**✅ DO**: `INSERT INTO products DOCUMENTS (:item) ON ID CONFLICT DO UPDATE_LOCAL_DIFF` for upserts and re-imports; change only changed fields with `UPDATE ... SET`; remove fields with `UNSET`; replace an object with `UNSET obj` then `SET obj = :value` in one transaction.
**❌ DON'T**: read-modify-write whole documents with `DO UPDATE` or `DO UPDATE_LOCAL_DIFF` (a stale in-memory value differs from the stored one and is written back); expect `DO UPDATE` or `SET obj = {...}` to remove keys (by default, objects merge; see `data-modeling`).

`§ INSERT and Conflict Handling`, `§ UPDATE` · Example: [dql-writes.sql](examples/dql-writes.sql)

### 7. Index the inner collection of a JOIN (SDK 5.1+) (CRITICAL)

Joins (`INNER`, `LEFT`, `RIGHT` as first join only) run on local data. The inner collection's join key needs an index, or the join must be on its `_id`; otherwise the query fails (`disallowed without appropriate index support`).
**✅ DO**: `CREATE INDEX IF NOT EXISTS idx_orders_customerId ON orders (customerId)` for `... JOIN orders o ON o.customerId = c._id`; qualify every field with its alias and alias colliding fields; subscribe to each joined collection separately; filter the outer collection selectively.
**❌ DON'T**: use `JOIN` in subscriptions or on Ditto Server; use `USE INDEX ''` on large collections to silence the index error.

`§ Joining Collections (SDK 5.1+)`

### 8. Copy values out of query results right away (CRITICAL)

A result's rows (`items`) and their values reference native memory. In Kotlin, a result is a resource that you `close()` (or read inside the mapping function of `execute`).
**✅ DO**: read the rows once and convert them to plain values or models; project only the fields you need; read the mutated document IDs once; track a commit ID only when the result lists mutated document IDs.
**❌ DON'T**: store result or row objects in state, caches, or across observer callbacks; change a row's value to edit the document (write with `UPDATE`); in Kotlin, use typed accessors such as `.string` on fields that can be missing or `null` (they throw `DittoException.FatalException`; use the `...OrNull` forms).

`§ Working with Query Results`, `§ Query results in Kotlin` · Example: `query-result-handling` in `examples/<sdk>/` · Member table: [reference/query-optimization.md](reference/query-optimization.md#query-results)

### 9. Quote every key in inline object literals (CRITICAL)

Unquoted keys are rejected in `INSERT` and silently produce `{}` in `SELECT`; prefer document parameters. Backticks quote identifiers and reserved words (`collection`).

<!-- expect-error -->
```sql
-- ❌ BAD: Rejected ("Cannot convert to a literal")
INSERT INTO orders DOCUMENTS ({_id: 'order-1', status: 'open'})
```

✅ Quoted: `DOCUMENTS ({'_id': 'order-1', 'status': 'open'})`.

`§ Quote every key in inline object literals`, `§ Literals` · Details: [reference/dql-reference.md](reference/dql-reference.md#literals-and-identifiers)

### 10. Delete and evict by ID with WHERE (CRITICAL)

Select by ID with `WHERE _id = :id` or `WHERE _id IN :ids`: planned as an ID lookup, it works on every release. On SDK 5.1.0, `DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate removes nothing, without an error (`§ Known Issues in SDK 5.1.0`).

`DELETE` removes on all peers (tombstone); `EVICT` on this device only. Strategy: `storage-lifecycle`.

`§ DELETE and EVICT`

### 11. Register each observer once per owner and release it (HIGH)

An observer runs its query and holds memory until released. Give it one owner (a screen, view model, or service), register it when the owner starts, and release it when the owner goes away.

| SDK | Recommended pattern | Pitfalls |
|---|---|---|
| Flutter | `registerObserver` **without** `onChange`; consume `changes` with one `StreamSubscription`; cancel both in `dispose()` | `changes` is single-subscription; cancelling its stream subscription does not cancel the observer |
| JavaScript | `registerObserver(query, handler, args)` with a synchronous handler; `cancel()` in the component's cleanup | `async` handlers are not awaited |
| Kotlin | `observe(...)` (a `Flow`) collected in the owner's scope, or `registerObserver(query, args) { }` | Release: cancel the collector (`observe`) or `close()` |
| Swift | `registerObserver(query:arguments:handler:)`; keep the `DittoStoreObserver` and `cancel()` it | Delivered on the main queue by default |

> **Note (SDK 5.1.0 and 5.2.0):** In Flutter, with `onChange` (and always with `registerObserverV2`), every result is also queued in `changes`, and memory grows until something listens: listen right after registering, or drain it (`observer.changes.listen((_) {})`).

**✅ DO**: register in the owner's start hook, and again when the query's inputs change; give each screen region its own small observer; use `COUNT(*)` for badges; keep callbacks short.
**❌ DON'T**: register in render code; create an observer per list item; observe a whole collection at the screen root; rely on garbage collection or `close()`.

`§ Observer Lifecycle`, `§ Store Observers in Flutter`, `§ Observer lifecycle in Flutter` · Examples: `observer-patterns-good` and `observer-patterns-bad` in `examples/<sdk>/` · Details: [reference/subscriptions-and-observers.md](reference/subscriptions-and-observers.md#observer-lifecycle)

### 12. Hand slow observer work to performance-observability (HIGH)

For slow or `async` per-update work, use the SDK's backpressure API **(SDK 5.1+)**: Flutter `registerObserverV2` or `registerObserverWithSignalNext` (both Experimental), JavaScript `registerObserverWithSignalNext`, Swift `handlerWithSignalNext:`, Kotlin a suspending handler or `collect`.

`§ Backpressure (SDK 5.1+)`, `§ Choosing an observer API` · Example: `observer-backpressure` in `examples/<sdk>/`

### 13. Put ORDER BY and LIMIT in local queries, with a tie-breaker (MEDIUM)

Without `ORDER BY` (observers included) order is not guaranteed. Add a unique tie-breaker (`ORDER BY createdAt DESC, _id`); combine `LIMIT`/`OFFSET` with `ORDER BY`; prefer keyset pagination. Existence: `SELECT _id ... LIMIT 1`; counts: `COUNT(*)`.

`§ ORDER BY`, `§ LIMIT and OFFSET` · Details: [reference/dql-reference.md](reference/dql-reference.md#order-by-limit-and-offset), [reference/query-optimization.md](reference/query-optimization.md#pagination)

### 14. Use RETURNING instead of write-then-read (SDK 5.1+) (MEDIUM)

`RETURNING` on `INSERT`, `UPDATE`, `DELETE`, or `EVICT` returns the affected documents in `items` (after the update; before removal).

`§ RETURNING (SDK 5.1+)` · Details: [reference/dql-reference.md](reference/dql-reference.md#returning-sdk-51)

### 15. Repeat expressions in GROUP BY and HAVING (MEDIUM)

`GROUP BY` and `HAVING` cannot reference projection aliases (`ORDER BY` can); every non-aggregate projection must be a `GROUP BY` key. Aggregates other than `COUNT` return MISSING over zero rows: `ifmissing(SUM(total), 0)`. `COUNT(field)` skips `false`.

`§ Aggregates`, `§ GROUP BY and HAVING` · Details: [reference/dql-reference.md](reference/dql-reference.md#projections-distinct-and-aggregates)

### 16. Use a differ only for item-level changes (MEDIUM)

The differ (`Differ`; `DittoDiffer` in Swift; Kotlin's observer `DittoDiff`) reports insertions, deletions, updates, and moves by `_id`; it is expensive, so bound diffed queries with `LIMIT`. Use it only for explicit insert, remove, and move calls such as an animated list.

`§ Diffing Results` · Example: `observer-differ` in `examples/<sdk>/`

## Checklist

- [ ] Values passed as `:parameters`; arrays as `IN :values` (no parentheses)
- [ ] Inline object literal keys quoted; documents passed as `DOCUMENTS (:doc)`
- [ ] Optional booleans filtered with `coalesce(field, false)`; existence tested with `IS [NOT] MISSING`
- [ ] No `ANY` or `EVERY ... SATISFIES` over a parameter or literal array in `WHERE`
- [ ] `ORDER BY` with `_id` tie-breaker wherever order matters; `LIMIT` combined with `ORDER BY`
- [ ] `GROUP BY` / `HAVING` repeat expressions; empty aggregates wrapped with `ifmissing`
- [ ] JOIN inner keys indexed (or joined on `_id`); fields qualified with aliases
- [ ] Upserts use `ON ID CONFLICT DO UPDATE_LOCAL_DIFF`; fields removed with `UNSET`
- [ ] `DELETE` / `EVICT` by ID use `WHERE _id IN :ids`
- [ ] Subscriptions: `SELECT *` on stable partition keys, owned by a service, registered again after every `Ditto.open()`, cancelled on logout and before evicting, not re-registered for UI filters
- [ ] Every local query, observer, aggregate, and `JOIN` reads only documents that a subscription covers, with the same arguments
- [ ] No empty result or count of 0 taken as proof that data does not exist; no single `execute` right after subscribing
- [ ] Observers registered once per owner, outside render code, and released when the owner goes away (Flutter: no `onChange`; stream subscription and observer cancelled in `dispose()`)
- [ ] Callbacks copy row values into plain data; no result or row object retained (Kotlin: `...OrNull` accessors for optional fields)

## More

- Reference: [reference/dql-reference.md](reference/dql-reference.md) (DQL syntax and semantics), [reference/subscriptions-and-observers.md](reference/subscriptions-and-observers.md) (subscription and observer APIs and lifecycle), [reference/query-optimization.md](reference/query-optimization.md) (result members, pagination, index-friendly predicates)
- Examples: [examples/](examples/) - `.sql` for every SDK, `examples/<sdk>/` for API code; `-good` / `-bad` pairs
- Related skills: `data-modeling` (merge semantics), `storage-lifecycle` (DELETE/EVICT strategy), `performance-observability` (backpressure, indexes, logging), `transactions-attachments`, `sdk-setup` (connection problems)
