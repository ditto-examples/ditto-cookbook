---
name: performance-observability
description: |
  Validates Ditto SDK 5.1 store observer performance, Flutter UI update patterns,
  index and query performance, unnecessary writes, and logging configuration.

  CRITICAL ISSUES PREVENTED:
  - Unbounded memory growth from observers registered with onChange whose changes stream is never consumed (Flutter, SDK 5.1.0)
  - Leaked observers and stream subscriptions (missing cancel() in dispose)
  - Slow or async work in registerObserver listeners without backpressure
  - Observers that stop updating because signalNext() is never called
  - Full-screen rebuilds from one broad observer at the root of a screen
  - Redundant writes (DO UPDATE re-upserts, whole-document rewrites) that mark documents mutated and fire observers
  - Collection scans from missing or unusable indexes, and strict mode disabling index scans
  - DittoLogger used before Ditto.init(), and log forwarding lost after ditto.close()

  TRIGGERS:
  - Registering store observers (registerObserver, registerObserverV2, registerObserverWithSignalNext)
  - Building Flutter widgets or state controllers that display Ditto query results
  - Using Differ, AnimatedList, or StreamBuilder with observer results
  - Writing upserts or updates that run repeatedly (imports, refreshes, form saves)
  - Creating indexes, or using ADVISE, EXPLAIN, or PROFILE
  - Configuring DittoLogger, exporting logs, or querying system: virtual collections

  PLATFORMS: Flutter (Dart, primary); JavaScript, Swift, Kotlin (observer backpressure differences only)
---

# Ditto Performance and Observability

Actionable patterns extracted from the Ditto best practices guide for **Ditto SDK 5.1.0**. The guide is the source of truth; every section below links to it.

## Table of Contents

- [Purpose](#purpose)
- [When This Skill Applies](#when-this-skill-applies)
- [Critical Patterns](#critical-patterns)
  - [1. Consume Observer Results Through the changes Stream](#1-consume-observer-results-through-the-changes-stream-critical)
  - [2. Observer Lifecycle and Cleanup](#2-observer-lifecycle-and-cleanup-critical)
  - [3. Keep registerObserver Listeners Fast](#3-keep-registerobserver-listeners-fast-high)
  - [4. Backpressure for Slow or Async Work](#4-backpressure-for-slow-or-async-work-high)
  - [5. Partial UI Updates](#5-partial-ui-updates-high)
  - [6. Avoid Unnecessary Writes](#6-avoid-unnecessary-writes-high)
  - [7. Create the Indexes Your Queries Need](#7-create-the-indexes-your-queries-need-high)
  - [8. Configure Logging Before Opening Ditto](#8-configure-logging-before-opening-ditto-high)
- [Common Workflows](#common-workflows)
- [Quick Reference Checklist](#quick-reference-checklist)
- [See Also](#see-also)

---

## Purpose

This skill keeps Ditto apps responsive and diagnosable. It covers how observers deliver results and how to consume them safely, how to keep widget rebuilds narrow, how to avoid writes that change nothing, how the query planner uses indexes, and how to configure logging and on-device diagnostics. Detailed rules (index usage table, EXPLAIN and PROFILE output, query scope, system parameters) are in [reference/optimization-patterns.md](reference/optimization-patterns.md).

Labels: **(SDK 5.1+)** marks features introduced in 5.1. **(Experimental)** marks APIs annotated `@experimental` that may change (`registerObserverV2`, `registerObserverWithSignalNext`, `StoreObserverV2`, `Store.experimentalSkipExecuteIsolateOffload`). **Note (SDK 5.1.0)** marks behavior that silently produces wrong results, crashes, or deadlocks, together with the safe pattern.

## When This Skill Applies

- Code calls `registerObserver`, `registerObserverV2`, or `registerObserverWithSignalNext`
- A widget, controller, or provider owns an observer or calls `setState` from observer results
- Code writes with `ON ID CONFLICT DO UPDATE`, or reads a document and writes it back
- Code runs `CREATE INDEX`, `ADVISE`, `EXPLAIN`, or `PROFILE`, or a query is slow
- Code touches `DittoLogger`, `exportLogs`, or `system:` virtual collections

---

## Critical Patterns

### 1. Consume Observer Results Through the changes Stream (CRITICAL)

**Guide**: [Store Observers in Flutter](../../../guides/best-practices/ditto.md#store-observers-in-flutter)

Register the observer **without** `onChange`, consume `changes` with one `StreamSubscription`, and cancel both in `dispose()`.

> **Note (SDK 5.1.0):** When an observer is registered with `onChange`, every result is **also** queued in its `changes` stream. If nothing listens to `changes`, those queued results stay in memory for the lifetime of the observer, so memory use grows with every update. The same applies to `registerObserverV2`, which starts observing as soon as it is registered, with or without `onChange`: listen to its `changes` stream right after registering it. If you need `onChange`, also drain the stream, for example with `observer.changes.listen((_) {})`.

**Detection** (red flags):
- `registerObserver(..., onChange: ...)` or `registerObserverV2(..., onChange: ...)` with no `.changes.listen` / `await for` on the same observer
- `QueryResult` or `QueryResultItem` objects stored in state or caches
- Queries without `ORDER BY` whose result order is shown in a list

```dart
// ✅ GOOD: The recommended observer pattern for widgets.
class OrdersList extends StatefulWidget {
  const OrdersList({super.key, required this.ditto});
  final Ditto ditto;
  @override
  State<OrdersList> createState() => _OrdersListState();
}

class _OrdersListState extends State<OrdersList> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id',
      arguments: {'status': 'open'},
    );
    _changes = _observer.changes.listen((result) {
      setState(() {
        // Copy plain values; do not keep QueryResult objects in state.
        _orders = result.items.map((item) => item.value).toList();
      });
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
        itemCount: _orders.length,
        itemBuilder: (context, index) {
          final order = _orders[index];
          return ListTile(key: ValueKey(order['_id']), title: Text('${order['_id']}'));
        },
      );
}
```

```dart
// ❌ BAD: onChange only; the unconsumed changes stream keeps every result in memory (SDK 5.1.0).
StoreObserver observeOrdersWithCallbackOnly(Ditto ditto, void Function(int) onCount) {
  return ditto.store.registerObserver(
    'SELECT * FROM orders ORDER BY createdAt DESC',
    onChange: (result) => onCount(result.items.length),
  );
}
```

**✅ DO:**
- Add `ORDER BY` whenever result order matters (use `_id` as a tie-breaker); without it the order of observer results is not guaranteed ([Stable Ordering](../../../guides/best-practices/ditto.md#stable-ordering))
- Copy values out of the result (`item.value` or your own model objects) ([Working with Query Results](../../../guides/best-practices/ditto.md#working-with-query-results))

**❌ DON'T:**
- Pass `onChange` and leave `changes` unconsumed
- Listen to `changes` twice; it is a single-subscription stream

**See**: [examples/flutter-observer-performance.dart](examples/flutter-observer-performance.dart)

---

### 2. Observer Lifecycle and Cleanup (CRITICAL)

**Guide**: [Observer Lifecycle and Cleanup](../../../guides/best-practices/ditto.md#observer-lifecycle-and-cleanup), [Resource Cleanup and Shutdown](../../../guides/best-practices/ditto.md#resource-cleanup-and-shutdown)

| Behavior (`registerObserver`) | What to do |
|---|---|
| Without `onChange`, the query starts when `changes` is first listened to | Listen right after registering |
| `changes` is single-subscription; a second `listen()` throws a `StateError` (`Bad state: Stream has already been listened to.`), even after the first subscription was cancelled | Hand the stream to exactly one listener or `StreamBuilder`, and keep that `StreamBuilder` mounted |
| Cancelling the `StreamSubscription` does not cancel a `StoreObserver` | Always call `observer.cancel()` as well |
| `observer.cancel()` closes `changes` | A pending `await for` loop ends |
| `await ditto.close()` does not close the `changes` stream of a `StoreObserver` or `StoreObserverV2`, and `cancel()` does nothing once Ditto is closed | Cancel stream subscriptions and observers before closing |
| Cancelling the stream subscription of a `StoreObserverV2` also cancels the observer | Still call `cancel()` in your cleanup path for clarity |

**✅ DO:**
- Register observers in `initState()` or in a service or controller, never in `build()`
- Cancel the stream subscription **and** the observer in `dispose()`
- Let observers follow screen scope; keep subscriptions at app or feature scope

**❌ DON'T:**
- Create an observer per list item; observe the list once and pass values down
- Rely on `ditto.close()` to end an `await for` loop over `registerObserver` results

**See**: [examples/flutter-state-management-good.dart](examples/flutter-state-management-good.dart), [examples/flutter-state-management-bad.dart](examples/flutter-state-management-bad.dart)

---

### 3. Keep registerObserver Listeners Fast (HIGH)

**Guide**: [Keep Observer Callbacks Fast](../../../guides/best-practices/ditto.md#keep-observer-callbacks-fast)

`registerObserver` has no backpressure: Ditto never waits for your code before delivering the next result. Pausing the `changes` stream of a `StoreObserver` does not slow Ditto down; results queue up in the stream instead.

**Detection**: an `async` listener on `StoreObserver.changes` that `await`s network calls, file I/O, or database writes; a listener that writes to the collection it observes without a guard.

**✅ DO:**
- Keep the listener synchronous and short: copy values, map them to model objects, call `setState`
- Move expensive computation off the UI isolate (for example, Flutter's `compute()` on plain values copied out of the result)
- Throttle UI updates for very busy collections if the user cannot perceive every intermediate state
- Use the backpressure APIs (pattern 4) when each update triggers slow or asynchronous work

**❌ DON'T:**
- `await` slow work inside a `registerObserver` listener; the next results keep arriving while you wait
- Write to the same collection from inside its observer without a guard; each write triggers the observer again

**See**: [examples/flutter-observer-performance.dart](examples/flutter-observer-performance.dart) (patterns 3 and 4, anti-patterns)

---

### 4. Backpressure for Slow or Async Work (HIGH)

**Guide**: [Backpressure (SDK 5.1+)](../../../guides/best-practices/ditto.md#backpressure-sdk-51), [Choosing an Observer API](../../../guides/best-practices/ditto.md#choosing-an-observer-api)

Two experimental Flutter APIs (SDK 5.1+) return a `StoreObserverV2`. While your code is busy, Ditto holds back further updates and later delivers the latest state, so intermediate results are merged instead of queued.

| Situation | API |
|---|---|
| Updating widgets from a query result | `registerObserver` + `changes` (stable, default) |
| Slow or `async` work per update that fits a loop | `registerObserverV2` + `await for` **(Experimental)** |
| The work for an update finishes elsewhere (after an animation or an external callback) | `registerObserverWithSignalNext` **(Experimental)** |

```dart
// ✅ GOOD: registerObserverV2 (Experimental) with await for: one update at a time.
Future<void> exportOpenOrders(
  Ditto ditto,
  Future<void> Function(List<Map<String, dynamic>> orders) export,
) async {
  final observer = ditto.store.registerObserverV2(
    'SELECT * FROM orders WHERE status = :status ORDER BY createdAt',
    arguments: {'status': 'open'},
  );
  // await for pauses the stream while the body runs; Ditto holds back the next update.
  await for (final result in observer.changes) {
    await export(result.items.map((item) => item.value).toList());
  }
  // The loop ends when observer.cancel() is called elsewhere.
}
```

`registerObserverWithSignalNext` delivers one result and then waits for `signalNext()`. **If you never call it, the observer stops delivering updates.** Call it in `finally` so an error does not stall the observer, and do not pause or resume the `changes` stream of such an observer.

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

Facts to keep in mind:
- `signalNext()` has no effect on observers registered with `registerObserverV2`.
- Results passed to `onChange` of either API are also queued in `changes`; pattern 1 applies.
- The experimental APIs may change in a future release; `registerObserver` remains the default for UI code.

**Other platforms** ([Backpressure on Other Platforms](../../../guides/best-practices/ditto.md#backpressure-on-other-platforms)): do not port Flutter code one-to-one. JavaScript `registerObserver` signals automatically when the handler returns and does not await an `async` handler (use `registerObserverWithSignalNext` for async work). Swift signals when the handler returns, with `handlerWithSignalNext:` for manual control. Kotlin has no `signalNext`; a suspending handler or a `Flow` (with `.conflate()` for slow collectors) provides backpressure.

**See**: [examples/observer-backpressure.dart](examples/observer-backpressure.dart)

---

### 5. Partial UI Updates (HIGH)

**Guide**: [Partial UI Updates](../../../guides/best-practices/ditto.md#partial-ui-updates), [Diffing Results](../../../guides/best-practices/ditto.md#diffing-results)

An observer delivers a new result for **any** change that affects its query. A `setState` at the top of a large screen rebuilds the whole screen, which can drop frames and lose scroll position or input focus.

**Detection**: one observer of a whole collection in the root widget; app bar, filters, and list rebuilt together; a badge that loads the full list to show `.length`.

**✅ DO:**
- Give each screen region its own small observer and widget
- Use `ListView.builder` with a `ValueKey(_id)` per row
- Use aggregate queries for summary widgets (`COUNT(*)` for a badge)
- With state management libraries (Riverpod, Bloc, Provider), let one provider or controller own each observer and cancel it in the dispose hook; `changes` can be listened to only once
- Map results to immutable model classes that implement `==` if you rely on equality to skip rebuilds; `item.value` creates a new `Map` for every result, and two maps with identical contents are never `==`
- Use `Differ` only where you need to know what changed (for example `AnimatedList`); a `ListView.builder` with keys does not need it

**❌ DON'T:**
- Observe a whole collection in the root widget and rebuild the entire screen on every change
- Diff large or unbounded result sets; `Differ` keeps the previous result in memory and diffing is expensive (keep diffed queries bounded with `LIMIT`)

`Differ` facts: `diff()` takes a `List<QueryResultItem>` (pass `result.items.toList()`); the first call reports every item as an insertion; `deletions` index the **old** list, `insertions` and `updates` index the **new** list; it does not give you the old items, so keep previous values yourself.

**See**: [examples/partial-ui-updates.dart](examples/partial-ui-updates.dart)

---

### 6. Avoid Unnecessary Writes (HIGH)

**Guide**: [ON ID CONFLICT](../../../guides/best-practices/ditto.md#on-id-conflict), [Prefer field-level updates over whole-document rewrites](../../../guides/best-practices/ditto.md#prefer-field-level-updates-over-whole-document-rewrites), [Assigning an object merges it](../../../guides/best-practices/ditto.md#assigning-an-object-merges-it)

| Write | Effect when values are unchanged |
|---|---|
| `ON ID CONFLICT DO UPDATE` | Every supplied field is written again; the document is reported as mutated and observers can fire again |
| `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` | Only fields whose values differ are written; nothing is written when nothing changed |
| `UPDATE ... SET f = <current value>` | Still recorded as a mutation, appears in `mutatedDocumentIDs()`, can wake observers |

**Detection**: periodic re-imports with `DO UPDATE`; read-modify-write of a whole document; `UPDATE` without a condition that skips documents already in the target state.

```dart
// ✅ GOOD: Re-upserting unchanged data is a no-op.
Future<bool> upsertProduct(Ditto ditto, Map<String, dynamic> product) async {
  final result = await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {'product': product},
  );
  return result.mutatedDocumentIDs().isNotEmpty; // Empty when nothing changed.
}

// ✅ GOOD: Field-level update that skips documents already in the target state.
Future<bool> setStatus(Ditto ditto, String orderId, String status) async {
  final result = await ditto.store.execute(
    'UPDATE orders SET status = :status '
    'WHERE _id = :id AND coalesce(status, :none) != :status',
    arguments: {'id': orderId, 'status': status, 'none': ''},
  );
  return result.mutatedDocumentIDs().isNotEmpty;
}
```

**✅ DO:**
- Use `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` for upserts and re-imports
- Use `UPDATE ... SET` for the fields that changed; update nested fields individually (`SET address.city = :city`)
- Use `coalesce` in the skip condition so documents with a missing or `null` field stay eligible

**❌ DON'T:**
- Read a document, modify it in Dart, and write the whole map back with `DO UPDATE` or `DO UPDATE_LOCAL_DIFF` (a stale value that differs from the stored one is written back)
- Expect `DO UPDATE` or `SET obj = {...}` to replace an object; with the default strict mode they merge, and fields not supplied remain (remove keys with `UNSET`)

**Why**: Ditto syncs changes at field level. Rewriting a whole document makes the change larger, and an unchanged field written by this device can win a merge against a real concurrent change made on another device.

**See**: [examples/unnecessary-deltas-good.dart](examples/unnecessary-deltas-good.dart), [examples/unnecessary-deltas-bad.dart](examples/unnecessary-deltas-bad.dart)

---

### 7. Create the Indexes Your Queries Need (HIGH)

**Guide**: [Indexing and Query Performance](../../../guides/best-practices/ditto.md#indexing-and-query-performance), [Index Usage Rules](../../../guides/best-practices/ditto.md#index-usage-rules), [ADVISE (SDK 5.1+)](../../../guides/best-practices/ditto.md#advise-sdk-51), [EXPLAIN and PROFILE](../../../guides/best-practices/ditto.md#explain-and-profile)

Indexes are local to each device and persist across restarts. They are used by `execute` and store observers (not by subscriptions), and in-memory stores (Flutter Web) do not support them.

```sql
-- Composite index (SDK 5.1+): equality field first, then the range or sort field
CREATE INDEX IF NOT EXISTS idx_orders_customer_createdAt ON orders (customerId, createdAt DESC)

-- Index-friendly: equality on the leading key, range and sort on the second key
SELECT * FROM orders WHERE customerId = :customerId AND createdAt >= :since ORDER BY createdAt DESC
```

Key usage rules (full table in [reference/optimization-patterns.md](reference/optimization-patterns.md#index-usage-rules)):
- Index scans: `=`, `IN :values`, ranges, prefix `LIKE 'abc%'` (literal or parameter), `!=`, `IS MISSING`
- **Collection scans**: any function applied to the field (`lower(name) = ...`, `starts_with(...)`, `coalesce(isDeleted, false) = false`), element lookups (`array_contains(tags, 'x')`), and `OR` when any branch is not indexed
- Match the sort direction of a composite index to avoid an extra sort step
- With `DQL_STRICT_MODE` set to `true`, the 5.1.0 planner does **not** use secondary indexes (ID lookups and full-collection `COUNT(*)` are not affected, and `ADVISE` returns no suggestions); keep the default (`false`) if you rely on indexes
- Keep type declarations consistent: only the most recently written CRDT type of a field is indexed, so a field written with different declarations (for example `REGISTER` and `MAP`) can produce incorrect or mis-ordered index results

**✅ DO:**
- Create indexes at startup with `CREATE INDEX IF NOT EXISTS`, after `Ditto.open` and before queries and observers start
- Run `ADVISE` (SDK 5.1+) for important queries during development and copy the suggested statements into startup code
- Use `EXPLAIN` to check the access path and `PROFILE` to measure

**❌ DON'T:**
- Use `EXPLAIN` to measure performance; it never runs the query
- Run `ADVISE AND PROVISION` from production code paths; it creates indexes as a side effect
- Index every field "just in case"; every index costs write time and storage
- Expect `IF NOT EXISTS` to update an index definition; it checks only the name

```dart
// ✅ GOOD: Development-only helper that prints index suggestions (SDK 5.1+).
Future<void> printOrderIndexAdvice(Ditto ditto) async {
  final result = await ditto.store.execute(
    'ADVISE SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC',
    arguments: {'status': 'open'},
  );
  final advice = result.items.first.value['advice'] as Map<String, dynamic>;
  final suggested = (advice['suggestedIndexes'] as List<dynamic>?) ?? const [];
  if (suggested.isEmpty) debugPrint('No suggestions: ${advice['outcome']}');
  for (final index in suggested) {
    debugPrint('${(index as Map<String, dynamic>)['statement']}');
  }
}
```

**See**: [examples/indexing-query-performance.dart](examples/indexing-query-performance.dart)

---

### 8. Configure Logging Before Opening Ditto (HIGH)

**Guide**: [Logging](../../../guides/best-practices/ditto.md#logging), [Ditto.open, Ditto.openSync, and Ditto.init](../../../guides/best-practices/ditto.md#dittoopen-dittoopensync-and-dittoinit)

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

| Fact | Consequence |
|---|---|
| `LogLevel`: `error`, `warning`, `info`, `debug`, `verbose`; default `info` | Set the level explicitly: `warning` in production, `debug` while debugging |
| `LogLevel.verbose` can significantly slow down replication | Use it only for short, targeted investigations |
| `ditto.close()` resets `DittoLogger.customLogCallback` to `null` for the whole process | Set the callback again before every `Ditto.open()` (after `Ditto.init()`), so logs emitted while Ditto opens are forwarded too |
| On-disk logs always include debug-level entries, independent of `minimumLogLevel` | A `warning` console level in production does not reduce what support can retrieve |
| `DittoLogger.exportLogs(path)` writes gzip-compressed JSON Lines and returns the byte count; the file must not exist and its directory must exist | Use a fresh, timestamped `.jsonl.gz` path |

**❌ DON'T:**
- Set `DittoLogger` properties before `Ditto.init()` (or `Ditto.open`) has completed
- Leave `LogLevel.verbose` enabled in production
- Register long-lived observers on `system:system_info`, or observers on `system:data_sync_info` in many places; query them with `execute` when needed, and for live sync status use a single observer with a trivial callback ([System Virtual Collections](../../../guides/best-practices/ditto.md#system-virtual-collections), [Monitoring Sync Status](../../../guides/best-practices/ditto.md#monitoring-sync-status))
- Change the `ROTATING_LOG_FILE_*` parameters unless Ditto support advises otherwise

**See**: [examples/logging-configuration-good.dart](examples/logging-configuration-good.dart), [examples/logging-configuration-bad.dart](examples/logging-configuration-bad.dart)

---

## Common Workflows

### Workflow 1: Adding a Screen That Shows Live Data

```
- [ ] Subscription exists at app or feature scope (observers do not sync data)
- [ ] Observer registered in initState() without onChange, with ORDER BY
- [ ] changes consumed by exactly one listener or StreamBuilder
- [ ] Values copied into plain maps or model objects
- [ ] Each region (badge, list, detail) has its own narrow observer
- [ ] Stream subscription and observer cancelled in dispose()
- [ ] Indexes for the observer's WHERE/ORDER BY created at startup
```

### Workflow 2: Investigating a Slow Query

```
- [ ] EXPLAIN: look for scan instead of indexScan on large collections
- [ ] Check the index usage rules (functions on fields, OR branches, strict mode)
- [ ] ADVISE (SDK 5.1+) for suggested indexes; add them to startup code
- [ ] PROFILE: compare documentsIn and documentsOut of filter steps
- [ ] Narrow the query: WHERE, projection, ORDER BY ... LIMIT
- [ ] During development, lower DQL_SLOW_REQUEST_WARN_SECONDS (SDK 5.1+) after every open
```

---

## Quick Reference Checklist

### Observers
- [ ] No `onChange` without consuming `changes` (Note (SDK 5.1.0))
- [ ] `ORDER BY` on every observer whose order is displayed
- [ ] Observers registered outside `build()`, one per region, not per item
- [ ] `StreamSubscription.cancel()` and `observer.cancel()` in `dispose()`
- [ ] No slow `await` inside `registerObserver` listeners
- [ ] No writes to the observed collection from inside its own observer without a guard
- [ ] `registerObserverV2` / `registerObserverWithSignalNext` labeled **(Experimental)**; `signalNext()` in `finally`
- [ ] Observer result sets bounded with `WHERE` and `LIMIT`; `Differ` only on bounded results

### Writes
- [ ] `DO UPDATE_LOCAL_DIFF` for upserts and re-imports
- [ ] Field-level `UPDATE` instead of whole-document rewrites
- [ ] Skip conditions use `coalesce` for missing or `null` fields

### Queries and Indexes
- [ ] `CREATE INDEX IF NOT EXISTS` at startup (not on Flutter Web)
- [ ] Composite indexes: equality fields first, matching sort direction
- [ ] No functions applied to indexed fields in `WHERE`
- [ ] Strict mode left at `false` when relying on indexes
- [ ] One `IN :ids` query instead of one query per ID
- [ ] Constant query strings with parameters

### Logging
- [ ] `await Ditto.init()` before `DittoLogger`
- [ ] `LogLevel.warning` in production, no `verbose`
- [ ] `customLogCallback` set again before every `Ditto.open()`
- [ ] Log export path is new and its directory exists

---

## See Also

### Main Guide
- [Observing Changes](../../../guides/best-practices/ditto.md#observing-changes)
- [Indexing and Query Performance](../../../guides/best-practices/ditto.md#indexing-and-query-performance)
- [Logging and Observability](../../../guides/best-practices/ditto.md#logging-and-observability)
- [INSERT and Conflict Handling](../../../guides/best-practices/ditto.md#insert-and-conflict-handling)
- [Resource Cleanup and Shutdown](../../../guides/best-practices/ditto.md#resource-cleanup-and-shutdown)

### Other Skills
- [query-sync](../query-sync/SKILL.md): subscriptions and query patterns
- [Flutter performance best practices](https://docs.flutter.dev/perf/best-practices) (external)
- [data-modeling](../data-modeling/SKILL.md): field-level updates and CRDT merge behavior
- [storage-lifecycle](../storage-lifecycle/SKILL.md): deletion, eviction, and storage

### Examples
- [examples/flutter-observer-performance.dart](examples/flutter-observer-performance.dart): recommended observer pattern, StreamBuilder variant, fast listeners
- [examples/observer-backpressure.dart](examples/observer-backpressure.dart): `registerObserverV2` and `registerObserverWithSignalNext` (Experimental)
- [examples/flutter-state-management-good.dart](examples/flutter-state-management-good.dart): controller-owned observers and scoped rebuilds
- [examples/flutter-state-management-bad.dart](examples/flutter-state-management-bad.dart): state management anti-patterns
- [examples/partial-ui-updates.dart](examples/partial-ui-updates.dart): per-region observers, `ValueKey`, `Differ` with `AnimatedList`
- [examples/unnecessary-deltas-good.dart](examples/unnecessary-deltas-good.dart) / [examples/unnecessary-deltas-bad.dart](examples/unnecessary-deltas-bad.dart): avoiding redundant writes
- [examples/indexing-query-performance.dart](examples/indexing-query-performance.dart): startup indexes, ADVISE, EXPLAIN, PROFILE
- [examples/logging-configuration-good.dart](examples/logging-configuration-good.dart) / [examples/logging-configuration-bad.dart](examples/logging-configuration-bad.dart): logging setup and export
