---
name: performance-observability
description: "Ditto SDK store observer performance and diagnostics (Flutter, JavaScript, Kotlin, Swift): observer lifecycle, backpressure (registerObserverV2, signalNext, suspending handlers), narrow UI updates, differs, redundant writes, indexes, ADVISE, EXPLAIN, PROFILE, logging, and system: collections. Use when a Ditto query is slow, a screen showing Ditto data janks, Ditto observers grow memory, Ditto upserts repeat, or when setting up Ditto logging."
---

# Ditto Performance and Observability

Keeps Ditto apps responsive and diagnosable: observers and backpressure, narrow UI updates, redundant writes, indexes, logging, and diagnostics. Targets Ditto SDK 5.2.0 in every SDK.

## Before You Apply

- Identify the project's SDK and version: Flutter (`ditto_live` in `pubspec.yaml` / `pubspec.lock`), JavaScript (`@dittolive/ditto` in `package.json`), Kotlin (`com.ditto:ditto-kotlin` in Gradle files), or Swift (`DittoSwift` in `Package.swift`, `Package.resolved`, or the Xcode project). These rules target SDK 5.2.0; for devices that still run 5.1.0, also apply `§ Known Issues in SDK 5.1.0`. **Note (SDK 5.1.0 and 5.2.0)** and **Note (SDK 5.1.0)** mark easy-to-miss behavior seen on those releases, with the safe pattern; **(SDK 5.1+)** / **(SDK 5.2+)** mark features introduced in that release.
- For API calls, Grep the outline of that SDK's page, `../guide/reference/best-practices/platforms/<sdk>.md` (`flutter`, `javascript`, `kotlin`, `swift`), with `^#{1,3} ` and read only the section you need, not the whole page; sections are named `<Topic> in <SDK>`. DQL examples: `examples/*.sql` (every SDK); API examples: `examples/<sdk>/`, with the same base names in every SDK.
- `§ <Heading>` cites the full guide: Grep the heading as a fixed string in `../guide/reference/best-practices/` and `../guide/reference/knowledge/`, then read that section.
- Report each finding at the severity of its item in `§ Anti-Pattern Checklist` (the checklist decides; Grep a phrase of the item there). The labels below rank the rules, not each item in them.

**(Experimental)** marks APIs that the SDK marks as experimental (Flutter `registerObserverV2`, `registerObserverWithSignalNext`, `StoreObserverV2`).

## Prevents

- Memory growth from Flutter `onChange` observers whose `changes` stream is never consumed (SDK 5.1.0 and 5.2.0)
- Leaked observers (never released, registered in render code, or left to garbage collection)
- Slow or async work in default observer callbacks; observers stalled because `signalNext()` is never called
- Full-screen updates from one broad observer at the root of a screen
- Redundant writes (`DO UPDATE` re-upserts, whole-document rewrites) that mark documents mutated and fire observers
- Collection scans from missing or unusable indexes, and strict mode disabling index scans
- A logger configured after Ditto opens, and lost log forwarding

## Workflow

Adding a screen that shows live data:

```
- [ ] Subscription exists at app or feature scope (observers do not sync data)
- [ ] Observer registered once by the screen's owner (not in render code), with ORDER BY
- [ ] Results consumed in one place and copied into plain values
- [ ] Each region (badge, list, detail) has its own narrow observer
- [ ] Observer released when its owner goes away
- [ ] Indexes for the observer's WHERE/ORDER BY created at startup
```

Investigating a slow query:

```
- [ ] EXPLAIN: look for scan instead of indexScan on large collections
- [ ] Check the index usage rules (functions on fields, OR branches, strict mode)
- [ ] ADVISE (SDK 5.1+) for suggested indexes; add them to startup code
- [ ] PROFILE: compare documentsIn and documentsOut of filter steps
- [ ] Narrow the query: WHERE, projection, ORDER BY ... LIMIT
- [ ] During development, lower DQL_SLOW_REQUEST_WARN_SECONDS (SDK 5.1+) in the system parameters of DittoConfig
```

## Rules

### 1. Avoid unnecessary writes (CRITICAL)

`ON ID CONFLICT DO UPDATE` rewrites every supplied field even when unchanged, so the document is reported as mutated and observers can fire. `DO UPDATE_LOCAL_DIFF` writes only differing fields (nothing when nothing changed). `UPDATE ... SET f = <current value>` is still a mutation, appears in the result's mutated document IDs, and can wake observers.

**Detection**: periodic re-imports with `DO UPDATE`; read-modify-write of a whole document; `UPDATE` without a condition that skips documents already in the target state; an observer callback that writes or acts on each change.

```sql
-- Re-upserting unchanged data is a no-op
INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- Field-level update that skips documents already in the target state
-- (:none is a sentinel that never equals a real status, for example '')
UPDATE orders SET status = :status WHERE _id = :id AND coalesce(status, :none) != :status
```

**✅ DO**: use `DO UPDATE_LOCAL_DIFF` for upserts and re-imports; `SET` only changed fields, nested ones individually (`SET address.city = :city`); use `coalesce` in skip conditions so missing or `null` fields stay eligible; check the result's mutated document IDs to see whether anything was written.
**❌ DON'T**: read a document, modify it in app code, and write the whole document back with `DO UPDATE` or `DO UPDATE_LOCAL_DIFF` (stale values are written back); expect `DO UPDATE` or `SET obj = {...}` to replace an object (in default strict mode they merge; remove keys with `UNSET`); write from an observer callback unless the write is a no-op once applied and every device computes the same value (else devices loop).

`§ ON ID CONFLICT`, `§ Prefer field-level updates over whole-document rewrites`, `§ Assigning an object merges it`, `§ Writing from Observers` · Examples: [examples/unnecessary-deltas-good.sql](examples/unnecessary-deltas-good.sql), [examples/unnecessary-deltas-bad.sql](examples/unnecessary-deltas-bad.sql)

### 2. Create the indexes your queries need (HIGH; CRITICAL for strict mode and SDK 5.1.0 key order)

Indexes are local to each device and persist across restarts. They are used by `execute` and store observers (not by subscriptions), and in-memory stores (Flutter Web, the JavaScript SDK in browsers) do not support them.

```sql
-- Composite index (SDK 5.1+): equality field first, then the range or sort field
CREATE INDEX IF NOT EXISTS idx_orders_customer_createdAt ON orders (customerId, createdAt DESC)

-- Index-friendly: equality on the leading key, range and sort on the second key
SELECT * FROM orders WHERE customerId = :customerId AND createdAt >= :since ORDER BY createdAt DESC
```

- Index scans: `=`, `IN :values`, ranges, prefix `LIKE 'abc%'`, `!=`, `IS MISSING`
- **Collection scans**: any function applied to the field (`lower(name) = ...`, `starts_with(...)`, `coalesce(isDeleted, false) = false`), element lookups (`array_contains(tags, 'x')`), and `OR` when any branch is not indexed
- Match the sort direction of a composite index to avoid an extra sort step. On SDK 5.1.0, keep all keys in one direction (`(customerId, createdAt)`), also for `ADVISE` suggestions: mixed `ASC`/`DESC` keys return wrong order there (`§ Known Issues in SDK 5.1.0`)
- With `DQL_STRICT_MODE` set to `true`, the planner of SDK 5.1.0 and 5.2.0 does **not** use secondary indexes (ID lookups and full-collection `COUNT(*)` are not affected, and `ADVISE` returns no suggestions); keep the default (`false`) if you rely on indexes
- Keep a field's type declarations consistent: per Ditto's docs only its latest CRDT type is indexed (mixed REGISTER/MAP writes risk wrong results), and other declarations read other values

**✅ DO**: create indexes at startup with `CREATE INDEX IF NOT EXISTS`, after Ditto opens and before queries and observers start; run `ADVISE` (SDK 5.1+) for important queries during development and copy the suggested statements into startup code; use `EXPLAIN` to check the access path and `PROFILE` to measure.
**❌ DON'T**: measure with `EXPLAIN` (it never runs the query); run `ADVISE AND PROVISION` in production (it creates indexes); index every field "just in case" (each costs write time and storage); expect `IF NOT EXISTS` to update a definition (it checks only the name).

Index usage table, `EXPLAIN`/`PROFILE` output, directives, query scope: [reference/optimization-patterns.md](reference/optimization-patterns.md#index-usage-rules).

`§ Indexing and Query Performance`, `§ Index Usage Rules`, `§ ADVISE (SDK 5.1+)`, `§ EXPLAIN and PROFILE` · Example: [examples/indexing-query-performance.sql](examples/indexing-query-performance.sql)

### 3. Consume observer results in one place and copy them out (HIGH)

Copy plain values (or your own model objects) out of each result and keep no result or row objects. The `query-sync` skill owns the full observer pattern.

| SDK | Consume results | Pitfalls |
|---|---|---|
| Flutter | `registerObserver` **without** `onChange`; exactly one `StreamSubscription` on `changes` (or one mounted `StreamBuilder`) | `changes` is single-subscription: a second `listen()` throws a `StateError` |
| JavaScript | A synchronous handler passed to `registerObserver` | An `async` handler is not awaited, so updates overlap |
| Kotlin | Collect `observe(...)` in the owner's scope, or a suspending handler | Released with `close()` (or by cancelling the collecting coroutine), not `cancel()` |
| Swift | The `handler:` of `registerObserver` | Runs on the main queue unless you pass `deliverOn:` |

> **Note (SDK 5.1.0 and 5.2.0):** In Flutter, with `onChange` (and always with `registerObserverV2`), every result is **also** queued in `changes`, and memory grows with every update until something listens: listen right after registering, or drain it (`observer.changes.listen((_) {})`).

**Detection**: Flutter `onChange:` with no `.changes.listen` / `await for` on the same observer; result or row objects in state or caches; displayed lists without `ORDER BY`.

**✅ DO**: add `ORDER BY` whenever result order matters, with `_id` as a tie-breaker (otherwise the order is not guaranteed).
**❌ DON'T**: keep result or row objects across callbacks.

`§ Observer Lifecycle`, `§ Store Observers in Flutter`, `§ Stable ordering`, `§ Working with Query Results` · Example: `observer-performance` in `examples/<sdk>/`

### 4. Release every observer (HIGH)

An observer runs until it is released: `cancel()` in Flutter, JavaScript, and Swift, `close()` in Kotlin (or cancel the collecting coroutine). Do not rely on garbage collection (in JavaScript, in testing, garbage-collected observers kept running) or on closing Ditto. In Flutter, cancelling the `StreamSubscription` does not cancel a `StoreObserver`, and `await ditto.close()` does not close the `changes` stream (`cancel()` does nothing once Ditto is closed): cancel both in `dispose()`, before closing Ditto.

**✅ DO**: register observers in the owner's start hook (Flutter `initState()`, a view model, a service), never in render code; let observers follow screen scope and keep subscriptions at app or feature scope.
**❌ DON'T**: create an observer per list item (observe the list once and pass values down); rely on closing Ditto to end a loop over observer results.

`§ Observer Lifecycle`, `§ Observer lifecycle in Flutter`, `§ Resource Cleanup and Shutdown` · Facts: [reference](reference/optimization-patterns.md#observer-lifecycle) · Examples: `state-management-good`, `state-management-bad` in `examples/<sdk>/`

### 5. Keep default observer callbacks fast (HIGH)

Without backpressure, Ditto does not wait for your code before delivering the next result: in Flutter, pausing `changes` of a `StoreObserver` only queues results; in JavaScript, `async` handlers overlap and an older result can finish last.

**Detection**: an `async` callback that `await`s network, file, or database work.

**✅ DO**: keep the callback synchronous and short (copy values, map to models, update UI state); move heavy computation off the UI thread on copied values; throttle UI updates for very busy collections; use backpressure (rule 6) for slow or async work per update.

**❌ DON'T**: wait for slow work inside a default callback.

`§ Keep observer callbacks fast` · Example: `observer-performance` in `examples/<sdk>/`

### 6. Use backpressure for slow or async work (HIGH)

While your code is busy, Ditto holds back further updates and later delivers the latest state, so intermediate results are merged instead of queued (SDK 5.1+).

| Situation | Flutter | JavaScript | Kotlin | Swift |
|---|---|---|---|---|
| UI state | `registerObserver` + `changes` | `registerObserver` | `observe(...)` | `registerObserver(... handler:)` |
| Slow or `async` work per update | `registerObserverV2` + `await for` **(Experimental)** | `registerObserverWithSignalNext` | Suspending handler, or `collect` | `handlerWithSignalNext:`, with `deliverOn:` |
| Work that finishes elsewhere | `registerObserverWithSignalNext` **(Experimental)** | `registerObserverWithSignalNext` | Suspend until done | `handlerWithSignalNext:` |
| Only the latest state matters | `registerObserverV2` with a slow consumer | Throttle | `observe(...).conflate()` | Throttle |

With `signalNext`, the observer delivers one result and then waits. **If you never call it, the observer stops delivering updates.** Call it in `finally` (or `defer`) so an error does not stall the observer. In Flutter, do not pause or resume the `changes` stream of such an observer; `signalNext()` has no effect on `registerObserverV2` observers.

`§ Backpressure (SDK 5.1+)`, `§ Choosing an observer API`, `§ Backpressure in Flutter` · Example: `observer-backpressure` in `examples/<sdk>/` · Flutter `await for` code: [reference](reference/optimization-patterns.md#backpressure-example-registerobserverv2)

### 7. Keep UI updates partial (HIGH)

An observer delivers a new result for **any** change that affects its query. Updating state at the top of a large screen renders the whole screen again, which can drop frames and lose scroll position or input focus.

**Detection**: one whole-collection observer at the root of a screen; a badge that loads the full list to count it.

**✅ DO**:
- Give each screen region its own small observer, owned by the component that shows it
- Use lazy lists that render only visible rows, with a row identity of `_id`
- Use aggregate queries for summary components (`COUNT(*)` for a badge), and skip the update when the value is unchanged
- With a state management library, let one store, provider, or view model own each observer and release it in its dispose hook
- Map results to immutable models that compare by content if you rely on equality to skip updates
- Use a differ only where you need to know what changed (for example an animated list)

**❌ DON'T**: register an observer per list row (60+ stall on 5.1.0); update the entire screen from one root observer on every change; diff large or unbounded result sets (the differ keeps the previous result in memory; bound diffed queries with `LIMIT`).

Differ index semantics: [reference/optimization-patterns.md](reference/optimization-patterns.md#differ).

`§ Partial UI Updates`, `§ Diffing Results` · Example: `partial-ui-updates` in `examples/<sdk>/`

### 8. Configure logging before opening Ditto (HIGH)

Configure the logger before Ditto opens, so startup is logged with your settings.

| | Flutter | JavaScript | Kotlin | Swift |
|---|---|---|---|---|
| Logger | `DittoLogger` (after `await Ditto.init()`; it throws before) | `Logger` | `DittoLogger` | `DittoLogger` |
| Forward events | `customLogCallback` (reset by `ditto.close()`: set it again before every open) | `setCustomLogCallback` | `observeLogEvents()` (a `Flow`) | `setCustomLogCallback(_:)` |
| Export on-disk logs | `exportLogs(path)` | `exportToFile(path)` | `exportToFile(path)` | `export(to:)` |

- Levels: `error`, `warning`, `info`, `debug`, `verbose`; default `info`. Use `warning` in production, `debug` while debugging; `verbose` multiplies the log output.
- The export fails if the file exists or its directory does not; use a fresh, timestamped `.jsonl.gz` path. On-disk log details: [reference/optimization-patterns.md](reference/optimization-patterns.md#logging-details).

**❌ DON'T**: leave `verbose` enabled in production; change the `ROTATING_LOG_FILE_*` parameters unless Ditto support advises otherwise.

`§ Logging`, `§ Configuring logging`, `§ Logging in Flutter` · Examples: `logging-configuration-good`, `logging-configuration-bad` in `examples/<sdk>/`

### 9. Query system: collections on demand, not with long-lived observers (HIGH)

`system:` virtual collections (`system:system_info`, `system:indexes`, `system:data_sync_info`, `system:active_requests`, and others) are local, read only, and snapshot-based. Query them with `execute` when needed.

**✅ DO**: for live sync status, use one observer with a trivial callback; pass diagnostic parameters in the system parameters of `DittoConfig` on every open (not persisted; on SDK 5.1, `ALTER SYSTEM` after open, before sync) and use `ALTER SYSTEM` for run-time changes such as a support session; include `system:sync_degradations` (SDK 5.2+) in diagnostics; create support bundles with `EXECUTE FUNCTION system_request_support_bundle()` (SDK 5.2+).
**❌ DON'T**: register long-lived observers on `system:system_info`, or observers on `system:data_sync_info` in many places.

Collections, sample queries, and diagnostic parameters: [reference/optimization-patterns.md](reference/optimization-patterns.md#system-virtual-collections).

`§ System Virtual Collections`, `§ Monitoring Sync Status`, `§ System Parameters Reference`, `§ Support bundles (SDK 5.2+)` · Example: `logging-configuration-good` in `examples/<sdk>/`

## Checklist

- [ ] `ORDER BY` on every observer whose order is displayed
- [ ] Observers registered outside render code, one per region, not per item
- [ ] Every observer released by its owner (Flutter: `StreamSubscription.cancel()` and `observer.cancel()` in `dispose()`; Kotlin: `close()`, or cancelling the coroutine that collects `observe`)
- [ ] No slow work inside default observer callbacks: Flutter, no `onChange` without consuming `changes`; JavaScript, no `async` `registerObserver` handler; Kotlin, no blocking handler on the default (main-thread) scope and no `store.execute` on the main thread; Swift, no slow `.main` handler or `Task` per update
- [ ] Backpressure APIs for slow work; `signalNext()` in `finally`; experimental APIs labeled **(Experimental)**
- [ ] Observer result sets bounded with `WHERE` and `LIMIT`; differs only on bounded results
- [ ] `DO UPDATE_LOCAL_DIFF` for upserts; field-level `UPDATE` with `coalesce` skip conditions
- [ ] `CREATE INDEX IF NOT EXISTS` at startup (not on in-memory stores)
- [ ] Composite indexes: equality fields first, matching sort direction; no functions on indexed fields
- [ ] Strict mode left at `false` when relying on indexes
- [ ] One `IN :ids` query instead of one query per ID; constant query strings with parameters
- [ ] Logger configured before Ditto opens; `warning` in production, no `verbose`
- [ ] Flutter: `customLogCallback` set again before every `Ditto.open()`; log export path is new
- [ ] No long-lived observers on `system:system_info`

## More

- Reference: [reference/optimization-patterns.md](reference/optimization-patterns.md) - observer APIs, differs, index rules, `ADVISE`/`EXPLAIN`/`PROFILE`, query scope, write policies, logging, `system:` collections
- Examples: [examples/](examples/) - DQL (`.sql`): unnecessary writes, indexing; `examples/<sdk>/`: observers, backpressure, state management, partial UI updates, logging
- Related skills: `query-sync` (observer and subscription lifecycle, DQL, upserts), `data-modeling` (merge behavior), `storage-lifecycle` (deletion, eviction)
- Guide: `§ Observing Changes`, `§ Indexing and Query Performance`, `§ Logging and Observability`
