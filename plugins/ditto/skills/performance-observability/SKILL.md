---
name: performance-observability
description: Ditto SDK store observer performance and diagnostics, covering the changes stream, backpressure with registerObserverV2 and registerObserverWithSignalNext, Flutter rebuild scope and Differ, redundant writes, indexes with ADVISE, EXPLAIN, and PROFILE, DittoLogger, and system: collections. Use when a Ditto query is slow, a Flutter screen janks or memory grows with observers, upserts repeat on refresh, or when setting up Ditto logging.
---

# Ditto Performance and Observability

Keeps Ditto apps responsive and diagnosable: observers and backpressure, narrow rebuilds, redundant writes, indexes, logging, and diagnostics. Targets Ditto SDK 5.1.0; examples are Flutter (Dart).

## Before You Apply

- Check the project's Ditto SDK version (`ditto_live` in `pubspec.lock`, `@dittolive/ditto` in `package-lock.json`, `DittoSwift` in `Package.resolved`, `com.ditto` in Gradle files); these rules were verified with 5.1.0. **Note (SDK 5.1.0)** marks easy-to-miss 5.1.0 behavior (wrong results, lost data, crashes, hangs) and its safe pattern; on another version, confirm it (release notes, docs.ditto.live) first. **(SDK 5.1+)** marks features introduced in 5.1.
- Examples are Dart. For JavaScript, Swift, or Kotlin, translate with `§ Platform Differences` and do not port Flutter observer or transaction code one-to-one.
- `§ <Heading>` cites a section of the full guide: Grep the heading in `../guide/reference/ditto.md` and read it for the reasoning or a complete example.

**(Experimental)** marks `@experimental` APIs that may change (`registerObserverV2`, `registerObserverWithSignalNext`, `StoreObserverV2`).

## Prevents

- Unbounded memory growth from observers registered with `onChange` whose `changes` stream is never consumed (Flutter, SDK 5.1.0)
- Leaked observers and stream subscriptions (missing `cancel()` in `dispose()`)
- Slow or async work in `registerObserver` listeners without backpressure
- Observers that stop updating because `signalNext()` is never called
- Full-screen rebuilds from one broad observer at the root of a screen
- Redundant writes (`DO UPDATE` re-upserts, whole-document rewrites) that mark documents mutated and fire observers
- Collection scans from missing or unusable indexes, and strict mode disabling index scans
- `DittoLogger` used before `Ditto.init()`, and log forwarding lost after `ditto.close()`

## Workflow

Adding a screen that shows live data:

```
- [ ] Subscription exists at app or feature scope (observers do not sync data)
- [ ] Observer registered in initState() without onChange, with ORDER BY
- [ ] changes consumed by exactly one listener or StreamBuilder
- [ ] Values copied into plain maps or model objects
- [ ] Each region (badge, list, detail) has its own narrow observer
- [ ] Stream subscription and observer cancelled in dispose()
- [ ] Indexes for the observer's WHERE/ORDER BY created at startup
```

Investigating a slow query:

```
- [ ] EXPLAIN: look for scan instead of indexScan on large collections
- [ ] Check the index usage rules (functions on fields, OR branches, strict mode)
- [ ] ADVISE (SDK 5.1+) for suggested indexes; add them to startup code
- [ ] PROFILE: compare documentsIn and documentsOut of filter steps
- [ ] Narrow the query: WHERE, projection, ORDER BY ... LIMIT
- [ ] During development, lower DQL_SLOW_REQUEST_WARN_SECONDS (SDK 5.1+) after every open
```

## Rules

### 1. Consume observer results through the changes stream (CRITICAL)

Register the observer **without** `onChange`, consume `changes` with exactly one `StreamSubscription` (or one mounted `StreamBuilder`), and copy plain values out of each result. The `query-sync` skill owns the full observer pattern.

> **Note (SDK 5.1.0):** When an observer is registered with `onChange`, every result is **also** queued in its `changes` stream. If nothing listens to `changes`, those queued results stay in memory for the lifetime of the observer, so memory use grows with every update. The same applies to `registerObserverV2`, which starts observing as soon as it is registered, with or without `onChange`: listen to its `changes` stream right after registering it. If you need `onChange`, also drain the stream, for example with `observer.changes.listen((_) {})`.

**Detection**: `onChange:` with no `.changes.listen` / `await for` on the same observer; `QueryResult` or `QueryResultItem` objects in state or caches; displayed lists without `ORDER BY`.

**✅ DO**: add `ORDER BY` whenever result order matters, with `_id` as a tie-breaker (otherwise the order is not guaranteed); copy `item.value` or your own model objects into state.
**❌ DON'T**: pass `onChange` and leave `changes` unconsumed; listen to `changes` twice (it is a single-subscription stream and the second `listen()` throws a `StateError`).

`§ Store Observers in Flutter`, `§ Stable ordering`, `§ Working with Query Results` · Example: [examples/flutter-observer-performance.dart](examples/flutter-observer-performance.dart) (Pattern 1 is the full widget)

### 2. Cancel the stream subscription and the observer (CRITICAL)

Cancelling the `StreamSubscription` does not cancel a `StoreObserver`, and `await ditto.close()` does not close the `changes` stream of a `StoreObserver` or `StoreObserverV2` (`cancel()` does nothing once Ditto is closed). Cancel both in `dispose()`, before closing Ditto.

**✅ DO**: register observers in `initState()` or in a service or controller, never in `build()`; let observers follow screen scope and keep subscriptions at app or feature scope.
**❌ DON'T**: create an observer per list item (observe the list once and pass values down); rely on `ditto.close()` to end an `await for` loop over `registerObserver` results.

`§ Observer lifecycle and cleanup`, `§ Resource Cleanup and Shutdown` · Facts table: [reference](reference/optimization-patterns.md#observer-lifecycle-in-flutter) · Examples: [examples/flutter-state-management-good.dart](examples/flutter-state-management-good.dart), [examples/flutter-state-management-bad.dart](examples/flutter-state-management-bad.dart)

### 3. Keep registerObserver listeners fast (HIGH)

`registerObserver` has no backpressure: Ditto never waits for your code before delivering the next result. Pausing the `changes` stream of a `StoreObserver` does not slow Ditto down; results queue up in the stream instead.

**Detection**: an `async` listener on `StoreObserver.changes` that `await`s network, file, or database work; a listener that writes to its own collection without a guard.

**✅ DO**: keep the listener synchronous and short (copy values, map to models, call `setState`); move expensive computation off the UI isolate (`compute()` on copied plain values); throttle UI updates for very busy collections; use the backpressure APIs (rule 4) for slow or asynchronous work per update.

**❌ DON'T**: `await` slow work inside a `registerObserver` listener (the next results keep arriving while you wait); write to the same collection from inside its observer without a guard (each write triggers the observer again).

`§ Keep observer callbacks fast` · Example: [examples/flutter-observer-performance.dart](examples/flutter-observer-performance.dart) (Patterns 3 and 4, anti-patterns)

### 4. Use backpressure for slow or async work (HIGH)

Two **(Experimental)** Flutter APIs (SDK 5.1+) return a `StoreObserverV2`. While your code is busy, Ditto holds back further updates and later delivers the latest state, so intermediate results are merged instead of queued.

| Situation | API |
|---|---|
| Updating widgets from a query result | `registerObserver` + `changes` (stable, default) |
| Slow or `async` work per update that fits a loop | `registerObserverV2` + `await for` **(Experimental)** |
| The work for an update finishes elsewhere (after an animation or an external callback) | `registerObserverWithSignalNext` **(Experimental)** |

`registerObserverWithSignalNext` delivers one result and then waits for `signalNext()`. **If you never call it, the observer stops delivering updates.** Call it in `finally` so an error does not stall the observer, and do not pause or resume the `changes` stream of such an observer. `signalNext()` has no effect on `registerObserverV2` observers.

```dart
// ✅ GOOD: registerObserverWithSignalNext (Experimental): always signal, even after an error.
StreamSubscription<QueryResult> uploadWithSignalNext(
  StoreObserverV2 observer,
  Future<void> Function(List<Map<String, dynamic>> orders) upload,
) {
  return observer.changes.listen((result) async {
    try {
      await upload(result.items.map((item) => item.value).toList());
    } catch (error) {
      showError(error);
    } finally {
      observer.signalNext();
    }
  });
}
```

**Other platforms** differ (JavaScript does not await an `async` handler; Kotlin has no `signalNext`); see the platform table in [reference/optimization-patterns.md](reference/optimization-patterns.md#observer-behavior).

`§ Backpressure (SDK 5.1+)`, `§ registerObserverWithSignalNext (Experimental)`, `§ Choosing an observer API`, `§ Backpressure on other platforms` · Example: [examples/observer-backpressure.dart](examples/observer-backpressure.dart) · `await for` code: [reference](reference/optimization-patterns.md#backpressure-example-registerobserverv2)

### 5. Keep UI updates partial (HIGH)

An observer delivers a new result for **any** change that affects its query. A `setState` at the top of a large screen rebuilds the whole screen, which can drop frames and lose scroll position or input focus.

**Detection**: one whole-collection observer in the root widget; a badge that loads the full list to show `.length`.

**✅ DO**:
- Give each screen region its own small observer and widget
- Use `ListView.builder` with a `ValueKey(_id)` per row
- Use aggregate queries for summary widgets (`COUNT(*)` for a badge)
- With state management libraries (Riverpod, Bloc, Provider), let one provider or controller own each observer and cancel it in the dispose hook; `changes` can be listened to only once
- Map results to immutable model classes with `==` if you rely on equality to skip rebuilds (two `item.value` maps are never `==`)
- Use `Differ` only where you need to know what changed (for example `AnimatedList`)

**❌ DON'T**: rebuild the entire screen from one root observer on every change; diff large or unbounded result sets (`Differ` keeps the previous result in memory; bound diffed queries with `LIMIT`).

`Differ` index semantics: [reference/optimization-patterns.md](reference/optimization-patterns.md#differ).

`§ Partial UI Updates`, `§ Diffing Results` · Example: [examples/partial-ui-updates.dart](examples/partial-ui-updates.dart); external: [Flutter performance best practices](https://docs.flutter.dev/perf/best-practices)

### 6. Avoid unnecessary writes (HIGH)

`ON ID CONFLICT DO UPDATE` rewrites every supplied field even when unchanged, so the document is reported as mutated and observers can fire. `DO UPDATE_LOCAL_DIFF` writes only differing fields (nothing when nothing changed). `UPDATE ... SET f = <current value>` is still a mutation, appears in `mutatedDocumentIDs()`, and can wake observers.

**Detection**: periodic re-imports with `DO UPDATE`; read-modify-write of a whole document; `UPDATE` without a condition that skips documents already in the target state.

```sql
-- Re-upserting unchanged data is a no-op
INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- Field-level update that skips documents already in the target state
-- (:none is a sentinel that never equals a real status, for example '')
UPDATE orders SET status = :status WHERE _id = :id AND coalesce(status, :none) != :status
```

**✅ DO**: use `DO UPDATE_LOCAL_DIFF` for upserts and re-imports; `SET` only changed fields, nested ones individually (`SET address.city = :city`); use `coalesce` in skip conditions so missing or `null` fields stay eligible; check `result.mutatedDocumentIDs().isNotEmpty` to see whether anything was written.
**❌ DON'T**: read a document, modify it in Dart, and write the whole map back with `DO UPDATE` or `DO UPDATE_LOCAL_DIFF` (stale values are written back); expect `DO UPDATE` or `SET obj = {...}` to replace an object (in default strict mode they merge; remove keys with `UNSET`).

**Why**: Ditto syncs changes at field level. Rewriting a whole document makes the change larger, and an unchanged field written by this device can win a merge against a real concurrent change made on another device.

`§ ON ID CONFLICT`, `§ Prefer field-level updates over whole-document rewrites`, `§ Assigning an object merges it` · Examples: [examples/unnecessary-deltas-good.dart](examples/unnecessary-deltas-good.dart), [examples/unnecessary-deltas-bad.dart](examples/unnecessary-deltas-bad.dart)

### 7. Create the indexes your queries need (HIGH)

Indexes are local to each device and persist across restarts. They are used by `execute` and store observers (not by subscriptions), and in-memory stores (Flutter Web) do not support them.

```sql
-- Composite index (SDK 5.1+): equality field first, then the range or sort field
CREATE INDEX IF NOT EXISTS idx_orders_customer_createdAt ON orders (customerId, createdAt DESC)

-- Index-friendly: equality on the leading key, range and sort on the second key
SELECT * FROM orders WHERE customerId = :customerId AND createdAt >= :since ORDER BY createdAt DESC
```

- Index scans: `=`, `IN :values`, ranges, prefix `LIKE 'abc%'`, `!=`, `IS MISSING`
- **Collection scans**: any function applied to the field (`lower(name) = ...`, `starts_with(...)`, `coalesce(isDeleted, false) = false`), element lookups (`array_contains(tags, 'x')`), and `OR` when any branch is not indexed
- Match the sort direction of a composite index to avoid an extra sort step
- With `DQL_STRICT_MODE` set to `true`, the 5.1.0 planner does **not** use secondary indexes (ID lookups and full-collection `COUNT(*)` are not affected, and `ADVISE` returns no suggestions); keep the default (`false`) if you rely on indexes
- Keep a field's type declarations consistent: only its most recently written CRDT type is indexed, so a field written as both REGISTER and MAP can return incorrect or mis-ordered index results

**✅ DO**: create indexes at startup with `CREATE INDEX IF NOT EXISTS`, after `Ditto.open` and before queries and observers start; run `ADVISE` (SDK 5.1+) for important queries during development and copy the suggested statements into startup code; use `EXPLAIN` to check the access path and `PROFILE` to measure.
**❌ DON'T**: measure with `EXPLAIN` (it never runs the query); run `ADVISE AND PROVISION` in production (it creates indexes); index every field "just in case" (each costs write time and storage); expect `IF NOT EXISTS` to update a definition (it checks only the name).

Index usage table, `ADVISE` helper, `EXPLAIN`/`PROFILE` output, directives, query scope: [reference/optimization-patterns.md](reference/optimization-patterns.md#index-usage-rules).

`§ Indexing and Query Performance`, `§ Index Usage Rules`, `§ ADVISE (SDK 5.1+)`, `§ EXPLAIN and PROFILE` · Example: [examples/indexing-query-performance.dart](examples/indexing-query-performance.dart)

### 8. Configure logging before opening Ditto (HIGH)

Every `DittoLogger` member throws `Ditto not initialized` until the SDK is initialized. Call `await Ditto.init()` first, then configure `DittoLogger`, then `Ditto.open`, so startup is logged with your settings.

```dart
import 'package:flutter/foundation.dart';

// ✅ GOOD: Call before Ditto.open().
Future<void> configureDittoLogging() async {
  await Ditto.init(); // DittoLogger throws until Ditto is initialized.
  DittoLogger.isEnabled = true;
  DittoLogger.minimumLogLevel = kReleaseMode ? LogLevel.warning : LogLevel.debug;
}
```

- `LogLevel`: `error`, `warning`, `info`, `debug`, `verbose`; default `info`. Use `warning` in production, `debug` while debugging; `verbose` can significantly slow down replication.
- `ditto.close()` resets `DittoLogger.customLogCallback` to `null` for the whole process. Set the callback again before every `Ditto.open()` (after `Ditto.init()`), so logs emitted while Ditto opens are forwarded too.
- `DittoLogger.exportLogs(path)` fails if the file exists or its directory does not; use a fresh, timestamped `.jsonl.gz` path. On-disk log details: [reference/optimization-patterns.md](reference/optimization-patterns.md#logging-details).

**❌ DON'T**: set `DittoLogger` properties before `Ditto.init()` (or `Ditto.open`) has completed; leave `LogLevel.verbose` enabled in production; change the `ROTATING_LOG_FILE_*` parameters unless Ditto support advises otherwise.

`§ Logging`, `§ Ditto.open, Ditto.openSync, and Ditto.init` · Examples: [examples/logging-configuration-good.dart](examples/logging-configuration-good.dart), [examples/logging-configuration-bad.dart](examples/logging-configuration-bad.dart)

### 9. Query system: collections on demand, not with long-lived observers (MEDIUM)

`system:` virtual collections (`system:system_info`, `system:indexes`, `system:data_sync_info`, `system:active_requests`, and others) are local, read only, and snapshot-based. Query them with `execute` when needed.

**✅ DO**: for live sync status, use one observer with a trivial callback; apply diagnostic parameters (`ALTER SYSTEM SET DQL_SLOW_REQUEST_WARN_SECONDS = 10`) after every `Ditto.open`, before `ditto.sync.start()` (they are not persisted).
**❌ DON'T**: register long-lived observers on `system:system_info`, or observers on `system:data_sync_info` in many places.

Collections, sample queries, and diagnostic parameters: [reference/optimization-patterns.md](reference/optimization-patterns.md#system-virtual-collections).

`§ System Virtual Collections`, `§ Monitoring Sync Status`, `§ System Parameters Reference` · Example: [examples/logging-configuration-good.dart](examples/logging-configuration-good.dart)

## Checklist

- [ ] No `onChange` without consuming `changes` (Note (SDK 5.1.0))
- [ ] `ORDER BY` on every observer whose order is displayed
- [ ] Observers registered outside `build()`, one per region, not per item
- [ ] `StreamSubscription.cancel()` and `observer.cancel()` in `dispose()`
- [ ] No slow `await` inside `registerObserver` listeners
- [ ] No writes to the observed collection from inside its own observer without a guard
- [ ] `registerObserverV2` / `registerObserverWithSignalNext` labeled **(Experimental)**; `signalNext()` in `finally`
- [ ] Observer result sets bounded with `WHERE` and `LIMIT`; `Differ` only on bounded results
- [ ] `DO UPDATE_LOCAL_DIFF` for upserts; field-level `UPDATE` with `coalesce` skip conditions
- [ ] `CREATE INDEX IF NOT EXISTS` at startup (not on Flutter Web)
- [ ] Composite indexes: equality fields first, matching sort direction; no functions on indexed fields
- [ ] Strict mode left at `false` when relying on indexes
- [ ] One `IN :ids` query instead of one query per ID; constant query strings with parameters
- [ ] `await Ditto.init()` before `DittoLogger`; `LogLevel.warning` in production, no `verbose`
- [ ] `customLogCallback` set again before every `Ditto.open()`; log export path is new
- [ ] No long-lived observers on `system:system_info`

## More

- Reference: [reference/optimization-patterns.md](reference/optimization-patterns.md) - observer APIs and lifecycle, `Differ`, index rules, `ADVISE`/`EXPLAIN`/`PROFILE`, query scope, long-running requests, write policies, logging, `system:` collections and parameters
- Examples: [examples/](examples/) - observers, backpressure, state management, partial UI updates, unnecessary writes, indexing, logging
- Related skills: `query-sync` (owns the observer and subscription lifecycle pattern, DQL, upserts), `data-modeling` (field-level updates and CRDT merge behavior), `storage-lifecycle` (deletion, eviction, and storage)
- Guide: `§ Observing Changes`, `§ Indexing and Query Performance`, `§ Logging and Observability`
