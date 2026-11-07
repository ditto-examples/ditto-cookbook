---
name: query-sync
description: Ditto SDK DQL reads and writes, subscriptions, and store observers (Flutter, JavaScript, Kotlin, Swift): query parameters, MISSING vs NULL, membership filters, subscription rules and lifecycle, observer lifecycle, upserts with ON ID CONFLICT, JOIN, RETURNING. Use when writing or reviewing ditto.store.execute, ditto.sync.registerSubscription, registerObserver, or any DQL statement, or when synced data does not appear or a query returns nothing.
---

# Ditto Query and Sync Patterns

DQL statements, subscriptions, and store observers: what syncs, what a query sees, and cheap observers and upserts. Targets Ditto SDK 5.2.0 in every SDK; DQL examples are SDK-neutral, API examples are per SDK.

## Before You Apply

- Identify the project's SDK and version: Flutter (`ditto_live` in `pubspec.yaml` / `pubspec.lock`), JavaScript (`@dittolive/ditto` in `package.json`), Kotlin (`com.ditto:ditto-kotlin` in Gradle files), or Swift (`DittoSwift` in `Package.swift`, `Package.resolved`, or the Xcode project). These rules target SDK 5.2.0; for devices that still run 5.1.0, also apply `§ Known Issues in SDK 5.1.0`. **Note (SDK 5.1.0 and 5.2.0)** marks easy-to-miss behavior confirmed on both releases, **Note (SDK 5.1.0)** behavior seen on 5.1.0 only; each gives the safe pattern. **(SDK 5.1+)** / **(SDK 5.2+)** mark features introduced in that release.
- Read that SDK's page, `../guide/reference/best-practices/platforms/<sdk>.md` (`flutter`, `javascript`, `kotlin`, `swift`), for the API calls; its sections are named `<Topic> in <SDK>`, such as *Store Observers in Swift*. DQL examples are `examples/*.sql` (every SDK); API examples are in `examples/<sdk>/` with the same base name in every SDK.
- `§ <Heading>` cites the full guide: Grep the heading in `../guide/reference/best-practices/` (including `platforms/`) and `../guide/reference/knowledge/`, then read that section.

## Prevents

- DQL built with string interpolation instead of parameters
- Filters that silently drop documents (MISSING vs NULL, `IN (:values)`, `ANY ... SATISFIES` over a parameter)
- "Synced data does not show": no subscription matches it
- Subscriptions rejected at registration (projections, `JOIN`, `LIMIT`/`ORDER BY`) or re-registered on every filter change
- Unreleased subscriptions and observers; observers registered in render code; Flutter `onChange` observers retaining every result
- Upserts that rewrite unchanged data and wake observers (`DO UPDATE` instead of `DO UPDATE_LOCAL_DIFF`)
- `JOIN` queries failing without an index on the inner collection
- Retained query result and row objects

## Workflow

Every DQL statement runs against the **local store**. Only `ditto.sync.registerSubscription` makes data sync from remote peers (while sync is running); `ditto.store.execute` (snapshot), `ditto.store.registerObserver` (live), and `ditto.store.transaction` read local data and never cause sync.

Subscriptions are long-lived, scoped by stable partition keys; observers and `execute` calls are short-lived and screen-specific. An empty result may mean nothing has synced yet or no subscription matches.

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

Keep `DQL_RESTRICT_SUBSCRIPTIONS` at its default (`true`): `false` allows `LIMIT`/`ORDER BY` as stateful subscriptions that degrade sync, and such a `LIMIT` bounds only the first download (5.1.0 and 5.2.0; later, every new or changed match syncs). Bound what syncs with `WHERE` (a stable key or a time window), not `LIMIT`.
**✅ DO**: filter by stable partition keys (tenant, store, region, team); use the same subscriptions on peers in the same role; keep predicates flat; give relay devices at least the subscriptions of the devices behind them.
**❌ DON'T**: subscribe to entire large collections "just in case" (acceptable only for a small reference-data collection every device needs); filter subscriptions on fields that change often (`status`, `assignee`).

Soft delete: relaying devices keep flagged documents in their subscriptions to pass the flag on; hide them locally with `coalesce(isDeleted, false) = false` (variants: `storage-lifecycle`).

`§ Subscription Rules`, `§ Scope Balancing`, `§ Soft delete, subscriptions, and cleanup`

### 4. Own subscriptions in a long-lived service and cancel them (CRITICAL)

Changing subscriptions makes peers re-evaluate which documents to send; avoid changing them more often than about every 15 minutes (documents already held are not downloaded again).
**✅ DO**:
- Register at app start (every time Ditto opens; not persisted), after login, or on entering a workspace, in an app- or feature-level service; keep every subscription and release it (`cancel()`, `close()` in Kotlin) on logout or workspace change
- Change the **observer**, not the subscription, when the user changes a filter, search term, tab, or sort order
- Cancel subscriptions **before** evicting their data; cancelling alone does not delete local data

**❌ DON'T**: register in render code (a widget's `build()`, a SwiftUI `body`, a composable, a React render) or on every screen visit; drop a reference without releasing it (do not rely on garbage collection).

`sync.stop()` pauses subscriptions (resumed by `start()`); closing Ditto cancels them. What `sync.subscriptions` returns for a subscription's arguments differs by SDK.

> **Note (SDK 5.1.0 and 5.2.0):** In Flutter, do not read `queryArguments`, `queryArgumentsJsonString`, or `queryArgumentsCborBytes` from `ditto.sync.subscriptions` elements; for subscriptions without arguments this ended the app or threw in testing. Read only `queryString` and `isCancelled`; keep your own references.

`§ Subscription Lifecycle`, `§ Sync stop, close, and inspection` · Examples: `subscription-lifecycle-good` and `subscription-lifecycle-bad` in `examples/<sdk>/`

### 5. Register each observer once per owner and release it (CRITICAL)

An observer runs its query and holds memory until released. Give it one owner (a screen, view model, or service), register it when the owner starts, and release it when the owner goes away; copy plain values out of each result.

| SDK | Recommended pattern | Pitfalls |
|---|---|---|
| Flutter | `registerObserver` **without** `onChange`; consume `changes` with one `StreamSubscription`; cancel both in `dispose()` | `changes` is single-subscription; cancelling the stream subscription does not cancel the observer; `close()` does not close `changes` |
| JavaScript | `registerObserver(query, handler, args)` with a synchronous handler; `cancel()` in the component's cleanup | `async` handlers are not awaited |
| Kotlin | `observe(...)` (a `Flow`) collected in the owner's scope, or `registerObserver(query, args) { }` | Release: cancel the collector (`observe`) or `close()` |
| Swift | `registerObserver(query:arguments:handler:)`; keep the `DittoStoreObserver` and `cancel()` it | Delivered on the main queue by default |

> **Note (SDK 5.1.0 and 5.2.0):** In Flutter, with `onChange`, every result is also queued in `changes`; if nothing listens, those results stay in memory for the observer's lifetime. `registerObserverV2` starts observing on registration, with or without `onChange`: listen to its `changes` right away. If you need `onChange`, also drain the stream (`observer.changes.listen((_) {})`).

**✅ DO**: register in the owner's start hook, and again when the query's inputs change; give each screen region its own small observer; use `COUNT(*)` for badges; keep callbacks short.
**❌ DON'T**: register in render code; create an observer per list item; observe a whole collection at the screen root; rely on garbage collection or `close()`.

`§ Observer Lifecycle`, `§ Store Observers in Flutter`, `§ Observer lifecycle in Flutter` · Examples: `observer-patterns-good` and `observer-patterns-bad` in `examples/<sdk>/` · Details: [reference/subscriptions-and-observers.md](reference/subscriptions-and-observers.md#observer-lifecycle)

### 6. Filter membership with IN :values (HIGH)

| Goal | Expression |
|---|---|
| Field equals one of several values | `status IN :statuses` (array parameter; can use an index) |
| Literal list | `status IN ('open', 'pending')` |
| Array field contains a value | `:tag IN tags` or `array_contains(tags, :tag)` (no index) |
| ❌ Array parameter in parentheses | `status IN (:statuses)` matches nothing |

> **Note (SDK 5.1.0 and 5.2.0):** `ANY ... SATISFIES ... END` in `WHERE` over a parameter or literal array returns no rows (5.0.3 returned matches). Use `status IN :statuses` or `array_contains(:statuses, status)`. Only local queries and observers are affected; a subscription with the same predicate syncs the documents, so the data arrives but the list shows empty.

`§ Filtering by Membership`

### 7. Upsert with DO UPDATE_LOCAL_DIFF and update fields, not documents (HIGH)

| `ON ID CONFLICT` | Existing document |
|---|---|
| `FAIL` (default) | Statement fails |
| `DO NOTHING` | Unchanged |
| `DO UPDATE` | Supplied fields merged in, even if identical (mutation recorded, observers can fire again) |
| `DO UPDATE_LOCAL_DIFF` | Only differing fields written; nothing written if nothing changed |

**✅ DO**: `INSERT INTO products DOCUMENTS (:item) ON ID CONFLICT DO UPDATE_LOCAL_DIFF` for upserts and re-imports; change only changed fields with `UPDATE ... SET`; remove fields with `UNSET`; replace an object with `UNSET obj` then `SET obj = :value` in one transaction (two statements on the transaction object).
**❌ DON'T**: read-modify-write whole documents with `DO UPDATE` or `DO UPDATE_LOCAL_DIFF` (a stale in-memory value differs from the stored one and is written back); expect `DO UPDATE` or `SET obj = {...}` to remove keys (with the default `DQL_STRICT_MODE = false`, objects merge; merge semantics: `data-modeling`).

`§ INSERT and Conflict Handling`, `§ UPDATE` · Example: [dql-writes.sql](examples/dql-writes.sql)

### 8. Index the inner collection of a JOIN (SDK 5.1+) (HIGH)

Joins (`INNER`, `LEFT`, `RIGHT` as first join only) run on local data. The inner collection's join key needs an index, or the join must be on its `_id`; otherwise the query fails with `Joining to "c" disallowed without appropriate index support`.
**✅ DO**: `CREATE INDEX IF NOT EXISTS idx_orders_customerId ON orders (customerId)` for `... JOIN orders o ON o.customerId = c._id`; qualify every field with its alias and alias colliding fields; subscribe to each joined collection separately; filter the outer collection selectively.
**❌ DON'T**: use `JOIN` in subscriptions or on Ditto Server; use `USE INDEX ''` on large collections to silence the index error.

`§ Joining Collections (SDK 5.1+)`

### 9. Put ORDER BY and LIMIT in local queries, with a tie-breaker (HIGH)

Without `ORDER BY` (observers included) order is not guaranteed. Add a unique tie-breaker (`ORDER BY createdAt DESC, _id`); combine `LIMIT`/`OFFSET` with `ORDER BY`; prefer keyset pagination. Existence: `SELECT _id ... LIMIT 1`; counts: `COUNT(*)`. Missing values sort last ascending, first with `DESC`.

`§ ORDER BY`, `§ LIMIT and OFFSET` · Details: [reference/dql-reference.md](reference/dql-reference.md#order-by-limit-and-offset), [reference/query-optimization.md](reference/query-optimization.md#pagination)

### 10. Copy values out of query results right away (HIGH)

A result's rows (`items`) and their values reference native memory. Whether reading a row again decodes it again or returns the same object differs by SDK; in Kotlin, a result is a resource that you `close()` (or read inside the mapping function of `execute`).
**✅ DO**: read the rows once and convert them to plain values or models; project only the fields you need; read the mutated document IDs once; track a commit ID only when the result lists mutated document IDs.
**❌ DON'T**: store result or row objects in state, caches, or across observer callbacks; change a row's value to edit the document (write with `UPDATE`).

`§ Working with Query Results` · Example: `query-result-handling` in `examples/<sdk>/` · Member table: [reference/query-optimization.md](reference/query-optimization.md#query-results)

### 11. Quote every key in inline object literals (HIGH)

Unquoted keys are rejected in `INSERT` and silently produce `{}` in `SELECT`; prefer document parameters. Backticks quote identifiers and reserved words (`collection`).

<!-- expect-error -->
```sql
-- ❌ BAD: Rejected ("Cannot convert to a literal")
INSERT INTO orders DOCUMENTS ({_id: 'order-1', status: 'open'})
```

✅ Quoted: `DOCUMENTS ({'_id': 'order-1', 'status': 'open'})`.

`§ Quote every key in inline object literals`, `§ Literals` · Details: [reference/dql-reference.md](reference/dql-reference.md#literals-and-identifiers)

### 12. Delete and evict by ID with WHERE (HIGH)

Select by ID with `WHERE _id = :id` or `WHERE _id IN :ids`: planned as an ID lookup, it works on every release. On SDK 5.1.0, `DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate (no `WHERE` clause, or `WHERE true`) removes nothing, without an error (`§ Known Issues in SDK 5.1.0`).

`DELETE` removes on all peers (tombstone); `EVICT` on this device only. Strategy: `storage-lifecycle`.

`§ DELETE and EVICT`

### 13. Use RETURNING instead of write-then-read (SDK 5.1+) (MEDIUM)

`RETURNING` on `INSERT`, `UPDATE`, `DELETE`, or `EVICT` returns the affected documents in `items` (after the update; before removal), e.g. `... WHERE _id IN :ids RETURNING _id, status`. Project `_id` when you need the IDs.

`§ RETURNING (SDK 5.1+)` · Details: [reference/dql-reference.md](reference/dql-reference.md#returning-sdk-51)

### 14. Repeat expressions in GROUP BY and HAVING (MEDIUM)

`GROUP BY` and `HAVING` cannot reference projection aliases (`ORDER BY` can); every non-aggregate projection must be a `GROUP BY` key. Aggregates other than `COUNT` return MISSING over zero rows: `ifmissing(SUM(total), 0)`. `COUNT(field)` skips `false`. No `DISTINCT` with `_id` or `*`.

`§ Aggregates`, `§ GROUP BY and HAVING` · Details: [reference/dql-reference.md](reference/dql-reference.md#projections-distinct-and-aggregates)

### 15. Use a differ only for item-level changes (MEDIUM)

The differ (`Differ`; `DittoDiffer` in Swift; Kotlin's observer `DittoDiff`) reports insertions, deletions, updates, and moves by `_id`; project `_id`. It is expensive, so bound diffed queries with `LIMIT`. A list keyed by `_id` does not need it; use it for explicit insert, remove, and move calls such as an animated list.

`§ Diffing Results` · Example: `observer-differ` in `examples/<sdk>/`

### 16. Hand slow observer work to performance-observability (MEDIUM)

For slow or `async` per-update work, use the SDK's backpressure API **(SDK 5.1+)**: Flutter `registerObserverV2` or `registerObserverWithSignalNext` (both Experimental), JavaScript `registerObserverWithSignalNext`, Swift `handlerWithSignalNext:`, Kotlin a suspending handler or `collect`. Details: `performance-observability`.

`§ Backpressure (SDK 5.1+)`, `§ Choosing an observer API`, `§ Partial UI Updates` · Example: `observer-backpressure` in `examples/<sdk>/`

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
- [ ] Subscriptions: `SELECT *` on stable partition keys, owned by a service, cancelled on logout and before evicting, not re-registered for UI filters
- [ ] Observers registered once per owner, outside render code, and released when the owner goes away (Flutter: no `onChange`; stream subscription and observer cancelled in `dispose()`)
- [ ] Callbacks copy row values into plain data; no result or row object retained

## More

- Reference: [reference/dql-reference.md](reference/dql-reference.md) - literals, MISSING/NULL, USE IDS, aggregates, ORDER BY type order, JOIN, write semantics, RETURNING
- Reference: [reference/subscriptions-and-observers.md](reference/subscriptions-and-observers.md) - subscription errors, scope, lifecycle, observer APIs of each SDK and their lifecycle, backpressure, differ
- Reference: [reference/query-optimization.md](reference/query-optimization.md) - query result members, pagination, counting, index-friendly predicates, JOIN performance
- Examples: [examples/](examples/) - `.sql` for every SDK, `examples/<sdk>/` for API code; `-good` / `-bad` pairs
- Related skills: `data-modeling` (CRDT merge semantics), `storage-lifecycle` (DELETE/EVICT strategy), `performance-observability` (backpressure, partial UI updates, indexes, logging), `transactions-attachments`
