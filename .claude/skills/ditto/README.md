# Ditto SDK Agent Skills

This directory contains Agent Skills for Ditto SDK 5.1 best practices. Flutter (Dart, package `ditto_live`) is the primary platform; JavaScript, Swift, and Kotlin are covered where their APIs or behavior differ.

## Overview

These Skills help Claude Code provide real-time guidance while you write offline-first applications with Ditto. They cover critical patterns for:
- DQL queries, writes, subscriptions, and store observers
- CRDT-safe data modeling
- Deletion, tombstones, soft delete, and eviction
- Transactions and attachments
- Observer performance, indexing, and logging
- Platform-specific API differences

All examples target Ditto SDK 5.1.0. Features introduced in 5.1 are labeled **(SDK 5.1+)**, and APIs marked experimental in the SDK are labeled **(Experimental)**.

## Available Skills

### 1. query-sync

**Focus**: DQL queries and writes, subscriptions, store observers

**Priority**: CRITICAL - Prevents silently wrong query results, rejected subscriptions, and leaked observers or observers that grow memory without bound

**Triggers**:
- Writing DQL for `ditto.store.execute()` or `tx.execute()`
- Creating subscriptions with `ditto.sync.registerSubscription()`
- Setting up observers with `registerObserver`, `registerObserverV2`, or `registerObserverWithSignalNext`
- Using `INSERT ... ON ID CONFLICT`, `UPDATE`, `RETURNING`, `DELETE`, or `EVICT`
- Writing `JOIN`, `GROUP BY`, `ORDER BY`, or `LIMIT` queries
- Handling `QueryResult`, `QueryResultItem`, `mutatedDocumentIDs()`, `commitID`, or `Differ`

**Key patterns**:
- Pass values as parameters (`:name`), never by string interpolation; quote every key in inline object literals
- MISSING vs NULL: filter with `coalesce(flag, false) = false` and `IS MISSING` / `IS NOT MISSING`
- Membership filters with `field IN :values` (not `IN (:values)`, not `ANY ... SATISFIES` in `WHERE`)
- Subscriptions select whole documents from one collection (`SELECT * FROM c [WHERE ...]`); keep `ORDER BY` and `LIMIT` in local queries
- Subscriptions are owned by long-lived services; filter locally instead of re-registering per screen
- The Flutter observer pattern: register without `onChange`, consume the `changes` stream, cancel both in `dispose()`
- `DO UPDATE_LOCAL_DIFF` for re-upserts; field-level `UPDATE` instead of whole-document rewrites
- `RETURNING` and `JOIN` **(SDK 5.1+)**; a `JOIN` needs an index on the inner collection's join key
- `DELETE` / `EVICT` by ID with `WHERE _id IN :ids`

[View Skill →](query-sync/SKILL.md)

---

### 2. data-modeling

**Focus**: CRDT-safe document design and merge behavior

**Priority**: CRITICAL - Prevents silent data loss and divergent data across devices

**Triggers**:
- Designing or reviewing document schemas and collections
- Arrays of objects that several devices edit (line items, participants, checklists)
- Assigning objects with `SET` or upserting with `ON ID CONFLICT`
- Choosing between embedding, separate collections, and `JOIN`
- Changing `DQL_STRICT_MODE` or declaring field types
- Counters, totals, balances, event history, and audit logs
- Generating document IDs, choosing timestamp formats

**Key patterns**:
- Model every field for its merge: scalars and arrays are last-writer-wins registers; objects merge per key
- Maps keyed by ID instead of arrays that several devices edit
- Under the default strict mode (`DQL_STRICT_MODE = false`), `SET obj = {...}` and `DO UPDATE` merge into existing objects; replace an object with `UNSET` then `SET` in one transaction
- Keep type declarations (`MAP`, `COUNTER`, `ATTACHMENT`) consistent across every statement that touches a field
- Embedding is the default; separate collections with `JOIN` **(SDK 5.1+)** when the data is shared, large, or independently updated
- `COUNTER` type instead of read-modify-write increments; no stored derived values
- Immutable, collision-free `_id` values (composite IDs for permission scoping)
- Document size: 256 KiB soft limit, 5 MiB hard limit
- UTC ISO-8601 timestamps with a zone designator, written by one helper with fixed precision

[View Skill →](data-modeling/SKILL.md)

---

### 3. storage-lifecycle

**Focus**: `DELETE`, soft delete, `EVICT`, tombstones, and local storage

**Priority**: CRITICAL - Prevents resurrected data, evicted documents syncing back, and soft-deleted documents that never disappear

**Triggers**:
- Writing `DELETE` or `EVICT` statements
- Implementing soft delete (`isDeleted` / `deletedAt`) and filtering deleted documents
- Designing retention policies and time-based or flag-based eviction
- Changing subscriptions around eviction
- Configuring `TOMBSTONE_TTL_HOURS` or other tombstone and reaping system parameters
- Monitoring local storage usage

**Key patterns**:
- Target `DELETE` and `EVICT` with `WHERE` (including `WHERE _id IN :ids`)
- Tombstone TTL: a device offline longer than the TTL can resurrect deleted data; keep edge TTLs below the Ditto Server TTL
- Soft delete with `isDeleted` and `deletedAt`; filter with `coalesce(isDeleted, false) = false`
- Keep soft-deleted documents inside subscriptions until every device has the flag. Variant A: a whole-collection subscription with cleanup by a synced `DELETE`. Variant B: a retention-window subscription that allows device-side `EVICT`
- Evict only documents outside every active subscription (cancel or narrow the subscription first)
- Avoid husk documents by not deleting documents that are still being edited
- Evict on a schedule (at most about once a day), in batches

[View Skill →](storage-lifecycle/SKILL.md)

---

### 4. transactions-attachments

**Focus**: Transactions and attachments

**Priority**: CRITICAL - Prevents deadlocks, blocked writes, and missing or never-stopped attachment fetches

**Triggers**:
- Using `ditto.store.transaction()`, `tx.execute`, or `TransactionCompletionAction`
- Implementing atomic multi-document changes or read-check-write logic
- Shutting down a Ditto instance that may have transactions in flight
- Calling `newAttachment()`, `fetchAttachment()`, `AttachmentFetcher`, or `AttachmentMetadata`
- Declaring `ATTACHMENT` fields in `INSERT` or `UPDATE` statements
- Displaying photos, PDFs, signatures, or other binary files from Ditto documents

**Key patterns**:
- Use only `tx.execute` inside a transaction, and never nest read-write transactions
- Keep transactions short: no network calls, dialogs, or timers inside
- Commit by returning a value; roll back by throwing or returning `TransactionCompletionAction.rollback`
- Await pending transactions before `ditto.close()` (it does not wait for in-flight work)
- Subscriptions sync attachment tokens, not blobs: fetch explicitly, lazily, with your own timeout, and `stop()` the fetcher
- Attachments are immutable: replace them with a new attachment
- Thumbnail pattern for lists; full-size attachments only on demand

[View Skill →](transactions-attachments/SKILL.md)

---

### 5. performance-observability

**Focus**: Observer performance, Flutter UI updates, indexing, and logging

**Priority**: HIGH - Prevents unbounded memory growth, janky UIs, collection scans, and missing logs

**Triggers**:
- Registering store observers (`registerObserver`, `registerObserverV2`, `registerObserverWithSignalNext`)
- Building Flutter widgets or state controllers that display Ditto query results
- Using `Differ`, `AnimatedList`, or `StreamBuilder` with observer results
- Writing upserts or updates that run repeatedly (imports, refreshes, form saves)
- Creating indexes, or using `ADVISE`, `EXPLAIN`, or `PROFILE`
- Configuring `DittoLogger`, exporting logs, or querying `system:` virtual collections

**Key patterns**:
- Consume observer results through the `changes` stream; cancel observers and stream subscriptions in `dispose()`
- Keep `registerObserver` listeners fast; use `registerObserverV2` or `registerObserverWithSignalNext` (Experimental) for slow or async work
- Partial UI updates: small observers close to the widgets that need the data
- Avoid unnecessary writes (`DO UPDATE_LOCAL_DIFF`, field-level updates) so observers do not fire for unchanged data
- Create the indexes your queries need; composite indexes and `ADVISE` **(SDK 5.1+)**; confirm plans with `EXPLAIN` / `PROFILE`
- Configure logging before `Ditto.open`: `await Ditto.init()` then `DittoLogger.minimumLogLevel = kReleaseMode ? LogLevel.warning : LogLevel.debug`

[View Skill →](performance-observability/SKILL.md)

---

## How Skills Work Together

### Complementary Coverage

Each Skill focuses on a specific concern, but they work together:

```
data-modeling → Design your document structure
     ↓
query-sync → Subscribe to, query, and observe data
     ↓
storage-lifecycle → Manage data lifecycle (delete, soft delete, evict)
     ↓
performance-observability → Optimize observers, indexes, and logging

transactions-attachments (as needed for specific features)
```

### Example Workflow

**Scenario**: Building an offline-first task app

1. **data-modeling**: Design the task document structure
   ```json
   {
     "_id": "task_123",
     "title": "Buy groceries",
     "done": false,
     "isDeleted": false,
     "tags": {"urgent": true, "personal": true}
   }
   ```
   `tags` is a map keyed by tag name, not an array, so concurrent edits on different devices merge.

2. **query-sync**: Register the subscription in a long-lived service, and observe locally in the screen
   ```dart
   // Owned by an app-level service; cancelled when the feature is no longer needed.
   final subscription = ditto.sync.registerSubscription(
     'SELECT * FROM tasks',
   );

   // Owned by the screen; cancelled in dispose() together with the stream subscription.
   final observer = ditto.store.registerObserver(
     'SELECT * FROM tasks '
     'WHERE done = false AND coalesce(isDeleted, false) = false '
     'ORDER BY createdAt',
   );
   final changes = observer.changes.listen((result) {
     final tasks = result.items.map((item) => item.value).toList();
     // Update the UI with tasks.
   });
   ```

3. **storage-lifecycle**: Implement soft delete
   ```dart
   Future<void> softDeleteTask(Ditto ditto, String taskId) async {
     await ditto.store.execute(
       'UPDATE tasks SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id',
       arguments: {
         'id': taskId,
         'deletedAt': DateTime.now().toUtc().toIso8601String(),
       },
     );
   }
   ```

4. **performance-observability**: Keep listeners fast, and move slow or async per-update work to `registerObserverV2` or `registerObserverWithSignalNext` (Experimental)
   ```dart
   // Requests the next result only after the async work has finished.
   StoreObserverV2 observeOpenTasks(
     Ditto ditto,
     Future<void> Function(List<Map<String, dynamic>> tasks) saveSnapshot,
   ) {
     final observer = ditto.store.registerObserverWithSignalNext(
       'SELECT * FROM tasks WHERE done = false ORDER BY createdAt',
     );
     // Cancel this stream subscription and the observer when you are done.
     observer.changes.listen((result) async {
       final tasks = result.items.map((item) => item.value).toList();
       try {
         await saveSnapshot(tasks);
       } finally {
         observer.signalNext(); // Always signal; otherwise updates stop.
       }
     });
     return observer;
   }
   ```

## Platform Notes

The concepts are the same on every platform, but some APIs behave differently (see the guide's [Platform Differences](../../guides/best-practices/ditto.md#platform-differences)):

| Topic | Flutter | JavaScript | Swift | Kotlin |
|---|---|---|---|---|
| Create / open | `await Ditto.open(DittoConfig(...))` | `await Ditto.open(new DittoConfig(...))`; on the Web, call `await init()` first | `try await Ditto.open(config:)` | `DittoFactory.create(config)` |
| Close | `await ditto.close()` | `await ditto.close()` | No public `close()`; release all references | `ditto.close()` |
| Login failure | Returns `AuthResponse` with `exception`; does not throw | Returns a result with `error`; does not throw | Reported to the completion handler as `error` | **Throws** |
| Observer backpressure | `registerObserver`: none. `registerObserverV2` (automatic) and `registerObserverWithSignalNext` (manual), both (Experimental) (SDK 5.1+) | `registerObserver` signals the next update when a synchronous handler returns; use `registerObserverWithSignalNext` for async work | `handler:` signals automatically; `handlerWithSignalNext:` is manual | No `signalNext`: suspend handlers and `collect` wait; `observe` returns a `Flow` |
| Release observers and subscriptions | `cancel()` | `cancel()` | `cancel()` | `close()` |
| Transaction completion | Return a value to commit; throw or return `TransactionCompletionAction.rollback` to roll back | Return a value, or `'rollback'` | Return a value, or `.rollback` | Must return `DittoTransaction.Result.Commit(value)` or `DittoTransaction.Result.Rollback` |
| `ditto.store.execute` inside a transaction | Throws `DittoException` | Can deadlock; never do it | Can deadlock; never do it | Can deadlock; never do it |
| Nested read-write transaction | Deadlocks (the SDK does not detect it); never do it | Deadlocks; never do it | Can deadlock; never do it | Can deadlock; never do it |

**Notes**:
- **Flutter**: Consume observer results through the `changes` stream. An observer registered with `onChange` whose `changes` stream is never listened to keeps every result in memory.
- **Flutter**: `Ditto` and `Store` cannot cross isolates; open one `Ditto` instance per persistence directory.
- **All platforms**: The DQL rules (parameters, MISSING vs NULL, subscription restrictions, `DELETE` / `EVICT` with `WHERE`) are identical.

## Relationship to Main Guide

**Source of Truth**: `.claude/guides/best-practices/ditto.md`

**Skills' Role**:
- Extract critical, automatable patterns from the main guide
- Focus on common issues Claude can detect during coding
- Provide immediate, actionable guidance

**Division of Labor**:

| Artifact | Purpose | Audience | Maintenance |
|----------|---------|----------|-------------|
| Main guide | Comprehensive reference | Human developers | Continuous (source of truth) |
| Skills | Autonomous detection | Claude Code AI | After every guide change + SDK updates |

**Update workflow**:
1. New patterns discovered → Update the main guide
2. After every guide edit → Propagate actionable changes into the Skills (see [Ditto Best Practices Synchronization](../../rules/workflows/ditto-best-practices-sync.md))
3. SDK updates → Update both immediately

## Getting Started

**For Developers**:
Just write Ditto code - Claude will automatically use Skills when relevant.

**For Contributors**:
See [../README.md](../README.md) for Skill authoring best practices.

## Learn More

- [Main Ditto Best Practices Guide](../../guides/best-practices/ditto.md)
- [Ditto SDK Documentation](https://docs.ditto.live/)
- [Agent Skills Overview](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview)
