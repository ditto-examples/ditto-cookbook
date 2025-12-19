# Ditto SDK Best Practices

This document provides comprehensive best practices and anti-patterns for Ditto SDK integration, focused on offline-first architecture and distributed data synchronization.

## Understanding Ditto

### What is Ditto?

Ditto is an **offline-first local database SDK** with built-in **P2P mesh networking capabilities**:

- **Local Database**: Schema-less document database that works without internet
- **P2P Mesh Network**: Synchronizes via Bluetooth, P2P Wi-Fi (AWDL/Wi-Fi Aware), and LAN using multiple transports
- **Cloud Sync**: Syncs with Ditto Server (cloud) when internet is available
- **Distributed Architecture**: Designed as a distributed database using CRDTs (Conflict-free Replicated Data Types)

**Architecture:**
- **Edge Peers (Small Peers)**: Devices running Ditto SDK (mobile devices, IoT devices, edge devices)
- **Ditto Cloud/Server**: Optional cloud cluster providing cloud sync, identity management, and monitoring

### Key Characteristics

**Offline-First Operation:**
- Apps continue to function without connectivity
- Database remains fully readable and writable offline
- Data automatically merges when devices reconnect

**Distributed Synchronization:**
- No central server required for basic operation
- Each peer operates independently (a device can run multiple peers via multiple apps or instances)
- Peers subscribe to and share data when in proximity or connected
- Uses multiple transports: Bluetooth LE (L2CAP/GATT), P2P Wi-Fi (AWDL/Wi-Fi Aware), LAN, and WebSockets

**Conflict Resolution:**
- Built-in CRDT implementation handles conflicts automatically
- Data from disconnected devices merges intelligently upon reconnection
- Uses Hybrid Logical Clocks (HLC) to track mutation timestamps
- Each peer has a unique Actor identifier (SiteID + Epoch) to track mutation sources

---

## Critical Design Principle

**⚠️ MOST IMPORTANT: Design for Distributed Data Merge**

When designing data models and app specifications, always consider:
- Multiple devices will modify the same data while disconnected
- Changes will merge when devices reconnect
- Your data structure must support safe merging without data loss

**✅ DO:**
- Design data models that merge well (append-only, increment counters, etc.)
- Use field-level updates rather than document replacement
- Consider how concurrent edits should be resolved

**❌ DON'T:**
- Design data models that assume single-writer scenarios
- Replace entire documents when only updating specific fields
- Ignore the distributed nature of Ditto

**Why**: Ditto's CRDT implementation ensures eventual consistency, but your data model determines whether merges produce the intended result.

---

## API Version Awareness (CRITICAL)

**⚠️ MOST IMPORTANT: Always Use Current Ditto API**

Ditto has evolved significantly, and using outdated APIs will cause implementation failures:

**Current API (v4.x+): DQL String-Based Queries**
- All operations use `ditto.store.execute(query, args)` with SQL-like DQL strings
- Subscriptions: `ditto.sync.registerSubscription(query)`
- Observers: `ditto.store.registerObserverWithSignalNext(query, callback, args)`
- Counter operations:
  - **All versions**: `PN_INCREMENT BY` operator (legacy PN_COUNTER CRDT)
  - **Ditto 4.14.0+**: `COUNTER` type with `INCREMENT BY`, `RESTART WITH`, `RESTART` operations

**⚠️ Flutter SDK Limitation (v4.x):**

The Flutter SDK (v4.14.0 and earlier) does not support `registerObserverWithSignalNext`. Flutter SDK only provides `registerObserver` without `signalNext` parameter. Backpressure control via `signalNext` will be available in Flutter SDK v5.0.

- **Flutter SDK v4.x**: Use `registerObserver` (no backpressure control)
- **Non-Flutter SDKs**: Use `registerObserverWithSignalNext` (recommended)

**Legacy API (DEPRECATED - Applicable to non-Flutter SDKs only):**
- Builder methods: `.collection()`, `.find()`, `.findById()`, `.update()`, `.upsert()`, `.remove()`, `.exec()`
- **Flutter SDK users**: This legacy API was never provided in Flutter SDK, so no concern
- **Non-Flutter SDK users**: These methods are **fully deprecated in SDK 4.12+** and will be removed in SDK v5

**✅ DO:**
- Reference official Ditto documentation before writing code
- Use DQL string queries exclusively
- Check SDK version to understand available features

```dart
// ✅ CURRENT API: DQL string queries (all SDKs including Flutter)
await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);
```

**❌ DON'T (non-Flutter SDKs only):**
- Use builder API methods (legacy, **fully deprecated in SDK 4.12+, will be removed in SDK v5**)
- Assume API patterns from older documentation

```dart
// ❌ LEGACY API (DEPRECATED - REMOVED IN SDK v5): Builder methods
// Note: Flutter SDK never had this API
final orders = await ditto.store
  .collection('orders')
  .find("status == 'active'")
  .exec();
// This API is fully deprecated as of SDK 4.12 and will be removed in v5
// Migration to DQL required before upgrading to SDK v5
```

---

## Migration Strategies

Critical migration paths for upgrading Ditto SDK implementations:

- **[Legacy API to DQL Quick Reference](#legacy-api-to-dql-quick-reference)** (SDK 4.12+): CRUD operation mapping
- **[Upgrading from Legacy API to DQL](#upgrading-from-legacy-api-to-dql-sdk-412)**: Step-by-step migration process
- **[COUNTER Type Adoption](#upgrading-to-counter-type-sdk-4140)** (SDK 4.14.0+): New counter CRDT type
- **[Store Observer with Differ](#replacing-legacy-observelocal-with-store-observers-sdk-412)**: Replacing legacy observeLocal (applicable to non-Flutter SDKs)
- **[DQL Subscription Forward-Compatibility](#dql-subscription-forward-compatibility-sdk-45)**: SDK v4.5+ deployment constraints

**⚠️ CRITICAL**: Non-Flutter SDKs must migrate to DQL before SDK v5 (legacy API removed). Flutter SDK: No migration needed.

### Upgrading from Legacy API to DQL (SDK 4.12+)

**⚠️ CRITICAL: Plan Your Migration**

If you're upgrading from SDK versions prior to 4.12 (applicable to non-Flutter SDKs only), you must migrate from the legacy builder API to DQL string queries.

**Migration Steps:**

1. **Audit your codebase**: Search for all legacy API method calls
   - `.collection()`, `.find()`, `.findById()`
   - `.update()`, `.upsert()`, `.remove()`, `.exec()`

2. **Convert queries systematically**:

```dart
// Legacy API (DEPRECATED)
final orders = await ditto.store
  .collection('orders')
  .find("status == 'active'")
  .exec();

// ↓ Migrate to DQL

// Current API (DQL)
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);
final orders = result.items.map((item) => item.value).toList();
```

3. **Update subscriptions**:

```dart
// Legacy API (DEPRECATED)
final subscription = ditto.store
  .collection('orders')
  .find("status == 'active'")
  .subscribe();

// ↓ Migrate to DQL

// Current API (DQL)
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);
```

4. **Update observers**:

```dart
// Legacy API (DEPRECATED)
final observer = ditto.store
  .collection('orders')
  .find("status == 'active'")
  .observe((docs) {
    updateUI(docs);
  });

// ↓ Migrate to DQL

// Current API (DQL) - Non-Flutter SDKs
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders WHERE status = :status',
  onChange: (result, signalNext) {
    final orders = result.items.map((item) => item.value).toList();
    updateUI(orders);
    signalNext();
  },
  arguments: {'status': 'active'},
);

// Current API (DQL) - Flutter SDK v4.x
final observer = ditto.store.registerObserver(
  'SELECT * FROM orders WHERE status = :status',
  onChange: (result) {
    final orders = result.items.map((item) => item.value).toList();
    updateUI(orders);
  },
  arguments: {'status': 'active'},
);
```

5. **Test thoroughly**: Verify all queries return expected results after migration

**See Also**: [`.claude/skills/ditto/reference/legacy-api-migration.md`](../../skills/ditto/reference/) for detailed migration patterns

### Legacy API to DQL Quick Reference

**⚠️ Non-Flutter SDKs Only** — Flutter SDK never had legacy builder API

Method-by-method mapping for migrating from legacy builder API to DQL. For detailed examples and patterns, see existing sections linked below.

| Category | Legacy Builder API | Current DQL API | SDK Version |
|----------|-------------------|-----------------|-------------|
| **Create Documents** |
| Insert/Upsert | `.collection('x').upsert(doc)` | `INSERT INTO x DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE` | All |
| Insert INITIAL | N/A (legacy only had upsert) | `INSERT INTO x INITIAL DOCUMENTS (:doc)` | 4.11+ |
| Insert DIFF | N/A | `INSERT INTO x DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE_LOCAL_DIFF` | 4.12+ |
| **Read Documents** |
| Find all | `.collection('x').find(query).exec()` | `SELECT * FROM x WHERE condition` | All |
| Find by ID | `.collection('x').findById(id).exec()` | `SELECT * FROM x WHERE _id = :id` | All |
| Find with LIMIT | `.find(query).limit(n).exec()` | `SELECT * FROM x WHERE condition LIMIT n` | All |
| **Update Documents** |
| Update field | `.findById(id).update(u => u.set('field', val))` | `UPDATE x SET field = :val WHERE _id = :id` | All |
| Update nested | `.update(u => u.set('obj.field', val))` | `UPDATE COLLECTION x (obj MAP) SET obj.field = :val WHERE _id = :id` | Strict mode |
| Increment counter | `.update(u => u.increment('count', 1))` | `UPDATE x APPLY count PN_INCREMENT BY 1.0 WHERE _id = :id` | All |
| Counter type | N/A | `UPDATE COLLECTION x (count COUNTER) APPLY count INCREMENT BY 1 WHERE _id = :id` | 4.14.0+ |
| **Delete Documents** |
| Delete (tombstone) | `.collection('x').findById(id).remove()` | `DELETE FROM x WHERE _id = :id` | All |
| Evict (local only) | `.collection('x').findById(id).evict()` | `EVICT FROM x WHERE _id = :id` | All |
| **Observe Changes** |
| Observe local | `.find(query).observeLocal((docs, event) => {})` | See [Replacing observeLocal](#replacing-legacy-observelocal-with-store-observers-sdk-412) | All → 4.12+ |
| **Subscribe (Sync)** |
| Subscribe | `.find(query).subscribe()` | `ditto.sync.registerSubscription('SELECT * FROM x WHERE condition')` | All → 4.5+ |
| **Attachments** |
| Store methods | `ditto.store.newAttachment()` | Unchanged (not deprecated) | All |
| Collection methods | `.collection('x').newAttachment()` | Use `ditto.store.newAttachment()` instead | Deprecated |

**Example Migration**:

```javascript
// ❌ Legacy API (DEPRECATED - removed in SDK v5)
const orders = await ditto.store
  .collection('orders')
  .find("status == 'active'")
  .limit(10)
  .exec();

// ✅ Current DQL API
const result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status LIMIT 10',
  { arguments: { status: 'active' } }
);
const orders = result.items.map(item => item.value);
```

**Key Differences**:
- DQL uses `=` (not `==`) for equality
- DQL requires parameterized arguments (`:param`)
- Nested field updates in strict mode require MAP declaration
- observeLocal replaced with two-step pattern (subscription + observer + Differ)
- DQL subscriptions require SDK v4.5+ on all peers

**See Also**:
- [INITIAL Documents](#initial-documents-for-default-data) for device-local templates
- [DO UPDATE_LOCAL_DIFF](#do-update_local_diff-for-efficient-upserts-sdk-412) for efficient upserts
- [Replacing observeLocal](#replacing-legacy-observelocal-with-store-observers-sdk-412) for observer migration
- [DQL Subscription Forward-Compatibility](#dql-subscription-forward-compatibility-sdk-45) for deployment constraints

---

### Upgrading to COUNTER Type (SDK 4.14.0+)

**⚠️ IMPORTANT: Understand Migration Implications**

Ditto SDK 4.14.0 introduced the `COUNTER` type as the recommended approach for distributed counters, alongside the existing `PN_INCREMENT BY` operator.

**Current Status:**
- **PN_INCREMENT BY**: Available in all SDK versions, uses legacy PN_COUNTER CRDT
- **COUNTER type**: Available in SDK 4.14.0+, uses native COUNTER CRDT with additional operations

**Should You Migrate?**

| Situation | Recommendation |
|-----------|----------------|
| New projects starting with SDK 4.14.0+ | ✅ Use COUNTER type |
| Existing projects using PN_INCREMENT | ⚠️ **Contact Ditto support before migrating** |
| Need `RESTART WITH` or `RESTART` operations | ✅ Upgrade to COUNTER type (requires 4.14.0+) |
| Only need increment/decrement operations | ✅ PN_INCREMENT BY remains fully supported |

**⚠️ CRITICAL: CRDT Type Migration Requires Careful Planning**

Migrating from PN_INCREMENT to COUNTER type involves changing the underlying CRDT type of fields. This requires careful planning to avoid data inconsistencies:

1. **Contact Ditto support** for migration guidance specific to your use case
2. **Test migration in staging environment** before production
3. **Ensure all peers upgrade simultaneously** or follow phased rollout plan

**Code Comparison:**

```dart
// PN_INCREMENT BY (all SDK versions)
await ditto.store.execute(
  'UPDATE products APPLY viewCount PN_INCREMENT BY 1.0 WHERE _id = :productId',
  arguments: {'productId': productId},
);

// ↓ Migrate to COUNTER (SDK 4.14.0+)

// COUNTER type (SDK 4.14.0+)
await ditto.store.execute(
  '''UPDATE COLLECTION products (viewCount COUNTER)
     APPLY viewCount INCREMENT BY 1
     WHERE _id = :productId''',
  arguments: {'productId': productId},
);
```

**New COUNTER Operations (SDK 4.14.0+):**

```dart
// Set counter to specific value
await ditto.store.execute(
  '''UPDATE COLLECTION products (viewCount COUNTER)
     APPLY viewCount RESTART WITH 100
     WHERE _id = :productId''',
  arguments: {'productId': productId},
);

// Reset counter to zero
await ditto.store.execute(
  '''UPDATE COLLECTION products (viewCount COUNTER)
     APPLY viewCount RESTART
     WHERE _id = :productId''',
  arguments: {'productId': productId},
);
```

**Why Migrate?**
- Explicit type declaration clarifies intent
- `RESTART WITH` enables controlled value setting
- Better semantic match for counters needing periodic resets
- Last-write-wins semantics for `RESTART` operations

**Why Stay with PN_INCREMENT?**
- Simple increment/decrement operations only
- Avoiding CRDT type migration complexity
- Backward compatibility with older SDK versions

---

### Counter Anti-Patterns and Alternatives

**⚠️ CRITICAL: Don't Use Counters for Derived Values**

Before implementing a counter field, ask: "Can this be calculated from existing data?"

❌ **DON'T**: Use counters for values derivable from existing data

```dart
// ❌ BAD: Inventory counter requiring synchronization
{
  "_id": "product_123",
  "initialStock": 100,
  "currentStock": 85  // COUNTER type - updated on every order
}

// Problem: Requires cross-collection updates (orders → products)
// When order created → decrement product.currentStock
// Complexity: Synchronization, error handling, rollback on cancellation
```

✅ **DO**: Calculate derived values in application code

```dart
// ✅ GOOD: Calculate inventory on-demand
{
  "_id": "product_123",
  "initialStock": 100  // REGISTER - never changes
}

// orders collection (separate, independent)
{
  "_id": "order_456",
  "items": {
    "product_123": {"quantity": 5}
  }
}

// Calculate current stock in app
final ordersResult = await ditto.store.execute(
  'SELECT items FROM orders WHERE items.product_123 != null'
);
final totalOrdered = ordersResult.items.fold<int>(
  0,
  (sum, order) => sum + (order.value['items']['product_123']['quantity'] as int)
);
final currentStock = initialStock - totalOrdered;
```

**Why Calculate Instead of Counter?**
- ✅ Single source of truth (no synchronization needed)
- ✅ Simpler logic (no cross-collection updates)
- ✅ Easier debugging (audit trail in order history)
- ✅ Avoids JOIN complexity (no foreign key updates)
- ✅ Self-correcting (recalculate from orders if mismatch)

**When Counters ARE Appropriate**:
- View counts, like counts (independent of other data)
- Session counters, usage metrics (not derived from documents)
- Vote tallies, rating scores (aggregated from many sources)

**Decision Tree**:
```
Need to track a numeric value?
  ↓
Can it be calculated from existing documents? (e.g., sum, count)
  ↓ YES → Calculate in app (DON'T use counter)
  ↓ NO
  ↓
Is it independent data? (not derived)
  ↓ YES → Use COUNTER type (SDK 4.14.0+) or PN_INCREMENT
  ↓ NO → Reconsider design
```

---

### DQL Subscription Forward-Compatibility (SDK 4.5+)

**⚠️ CRITICAL**: DQL subscriptions require SDK v4.5+ on ALL peers. Different wire protocol format prevents older peers from processing DQL subscription requests.

**Compatibility Matrix**:

| Feature | SDK Version Requirement | Backward Compatible |
|---------|------------------------|---------------------|
| DQL subscriptions | v4.5+ (all peers) | No - all peers must be v4.5+ |
| DQL queries/observers | v4.0+ | Yes - local operations only |
| Legacy subscriptions | All versions | Yes - works across all versions |

**Deployment Decision Table**:

| Scenario | Action |
|----------|--------|
| All devices upgraded to SDK v4.5+ | ✅ Safe to migrate subscriptions to DQL |
| Mixed SDK versions (some <v4.5) | ⚠️ Use phased rollout strategy (see below) |
| IoT devices with infrequent updates | ⚠️ Delay DQL subscription migration until all upgraded |
| Controlled enterprise deployment | ✅ Coordinate upgrade across fleet, then migrate |

**Phased Rollout Strategy**:

1. **Upgrade all peers to SDK v4.5+** (keep legacy subscriptions during upgrade)
2. **Verify all devices connected and upgraded** (check logs, device registry)
3. **Migrate subscriptions to DQL format** (deploy app update with DQL subscriptions)
4. **Monitor for devices with older SDK versions** (check sync logs for compatibility issues)

**Best Practice**: If uncertain whether all devices have upgraded, delay DQL subscription migration. Local DQL queries and observers can be used immediately (v4.0+) without coordination — only subscriptions have the forward-compatibility constraint.

**Detection Example** (Dart):

```dart
final sdkVersion = ditto.sdkVersion; // Returns "4.14.0" etc.
final versionParts = sdkVersion.split('.');
final majorVersion = int.parse(versionParts[0]);
final minorVersion = int.parse(versionParts[1]);

if (majorVersion == 4 && minorVersion >= 5) {
  // Safe to use DQL subscriptions
}
```

**See Also**: [SDK Version Upgrade Checklist](#sdk-version-upgrade-checklist) for coordinated upgrade process

---

### SDK Version Upgrade Checklist

When upgrading Ditto SDK to a new major or minor version:

**Pre-Upgrade:**
1. ✅ Review [Ditto SDK release notes](https://docs.ditto.live) for breaking changes
2. ✅ Check deprecation warnings in current codebase
3. ✅ Identify features dependent on specific SDK versions
4. ✅ Plan testing strategy (unit tests, integration tests, conflict scenarios)
5. ✅ Review skill synchronization requirements (if using Agent Skills)

**During Upgrade:**
1. ✅ Update `pubspec.yaml` (Flutter) or equivalent package manager
2. ✅ Run `flutter pub get` or equivalent dependency resolution
3. ✅ Fix deprecation warnings and API changes
4. ✅ Update code to use new recommended patterns (if applicable)
5. ✅ Verify all tests pass

**Post-Upgrade:**
1. ✅ Test offline sync scenarios across multiple devices
2. ✅ Verify conflict resolution behavior matches expectations
3. ✅ Test subscription and observer lifecycle
4. ✅ Validate attachment fetch/sync behavior
5. ✅ Update documentation to reflect new SDK version
6. ✅ Monitor for issues in staging/production environments

**Version-Specific Breaking Changes:**

| SDK Version | Key Changes |
|-------------|-------------|
| **v5.0** (Future) | Legacy builder API removed (non-Flutter SDKs) |
| **v4.14.0** | COUNTER type introduced, registerObserverWithSignalNext available |
| **v4.12** | Legacy builder API fully deprecated, `DO UPDATE_LOCAL_DIFF` introduced |
| **v4.11** | Transaction API introduced, DQL_STRICT_MODE default true |

---

## Ditto Query Language (DQL)

### Overview

Ditto uses **DQL (Ditto Query Language)**, a SQL-like query language with important differences:

**Characteristics:**
- SQL-like string syntax for familiarity
- Schema-less (no rigid table definitions)
- Document-oriented (JSON-like structure)
- All operations use `ditto.store.execute()` with DQL strings

**Important Limitations:**
- **No JOIN operations** (current Ditto versions do not support JOIN)
- Normalized (split) collections require multiple queries
- Complex cross-collection operations can impact performance

### Query Best Practices

**✅ DO:**
- Use denormalized data structures for related data that needs to be queried together
- Keep related data together in single documents to avoid multiple queries
- Separate independent data into different collections for parallel synchronization efficiency
- Limit query complexity for performance
- Use DQL string queries with parameterized arguments

**✅ GOOD**: Denormalize—embed items in order document (single query). Use DQL strings with parameterized arguments.
**❌ BAD**: Normalize—split orders and items into separate collections (requires multiple serial queries, no JOIN support).

**Why**: Without JOIN support (current Ditto versions), splitting related data into multiple collections requires multiple serial queries and complex application-level merging, severely impacting performance. However, independent data (e.g., users vs. products, current state vs. historical events) benefits from being in separate collections as they can synchronize in parallel. DQL has Ditto-specific behaviors that differ from standard SQL.

---

### Query Result Handling

**⚠️ CRITICAL: Treat QueryResults as Database Cursors**

Query results and QueryResultItems should be treated like database cursors that manage memory carefully. They use lazy-loading for memory efficiency: items materialize into memory only when accessed.

**✅ DO**: Extract data immediately via `item.value`, convert to models, let QueryResultItems be cleaned up automatically. Don't retain QueryResultItems between callbacks.

**Why**: QueryResultItems hold references to underlying data. Retaining them causes memory bloat. Extract data immediately, convert to models, let items auto-cleanup.

**Alternative formats**: `item.value` (Map, default), `item.cborData()` (Uint8List), `item.jsonString()` (String). CBOR/JSON are uncached.

### Diffing Query Results

`DittoDiffer` tracks changes between query emissions—including insertions, deletions, updates, and moves—enabling efficient UI updates. Use this when you need granular change information rather than full dataset reloads. For large datasets, debounce the diffing operation to maintain performance.

**Legacy observeLocal migration**: See [Replacing observeLocal](#replacing-legacy-observelocal-with-store-observers-sdk-412)

**Official Reference**: [Ditto Read Documentation](https://docs.ditto.live/sdk/latest/crud/read)

---

## SELECT Statements

### Basic Syntax

```sql
SELECT [DISTINCT] projection FROM collection
[WHERE condition]
[GROUP BY expr1, expr2, ...] [HAVING condition]
[ORDER BY expr1, expr2, ... [ASC|DESC]]
[LIMIT n] [OFFSET m]
```

**Projections**: `*` | `field1, field2` | `expr AS alias` | aggregate functions

---

### Projections (Field Selection)

**⚠️ CRITICAL**: In P2P mesh, every field syncs across peers. `SELECT *` wastes bandwidth.

**✅ DO**: Select only needed fields, use aliases for calculated fields
**❌ DON'T**: Use `SELECT *` when you only need specific fields

```dart
// ✅ GOOD: Specific fields only
final result = await ditto.store.execute(
  'SELECT make, model, year FROM cars WHERE color = :color',
  arguments: {'color': 'blue'},
);

// ✅ GOOD: Calculated fields with alias
final result = await ditto.store.execute(
  'SELECT make, model, price * 0.9 AS discounted_price FROM cars',
);

// ❌ BAD: SELECT * syncs all fields (unnecessary traffic)
final result = await ditto.store.execute(
  'SELECT * FROM cars WHERE color = :color',
  arguments: {'color': 'blue'},
);
```

**See Also**: [Exclude Unnecessary Fields from Documents](#exclude-unnecessary-fields-from-documents)

---

### DISTINCT Keyword

**⚠️ CRITICAL**: `DISTINCT` buffers all rows in memory (high memory impact on mobile devices).

**✅ DO**: Use only for small, filtered result sets
**❌ DON'T**: Use with `_id` (already unique), or on unbounded datasets

```dart
// ✅ GOOD: DISTINCT on small, filtered set
final result = await ditto.store.execute(
  'SELECT DISTINCT color FROM cars WHERE year >= :year',
  arguments: {'year': 2020},
);

// ❌ BAD: DISTINCT with _id (redundant, wastes memory)
final result = await ditto.store.execute(
  'SELECT DISTINCT _id, color FROM cars',
);

// ❌ BAD: Unbounded (can crash mobile devices)
final result = await ditto.store.execute(
  'SELECT DISTINCT customerId FROM orders',
);
```

**Why**: `_id` is unique per document—`DISTINCT` adds no value but buffers all rows.

---

### Aggregate Functions

**⚠️ CRITICAL**: Aggregates buffer all matching documents in memory (non-streaming "dam" in pipeline).

**Implications**: High memory usage, latency until all docs processed, no incremental streaming

**✅ DO**: Filter with `WHERE` before aggregating, use `GROUP BY` to reduce size
**❌ DON'T**: Unbounded aggregates, `COUNT(*)` for existence checks (use `LIMIT 1`), aggregates in high-frequency observers

```dart
// ✅ GOOD: Filtered aggregate
final result = await ditto.store.execute(
  '''SELECT COUNT(*) AS active_orders, AVG(total) AS avg_total
     FROM orders WHERE status = :status AND createdAt >= :cutoff''',
  arguments: {
    'status': 'active',
    'cutoff': DateTime.now().subtract(Duration(days: 30)).toIso8601String(),
  },
);

// ❌ BAD: Unbounded aggregate (buffers all docs)
final result = await ditto.store.execute('SELECT COUNT(*) FROM orders');

// ❌ BAD: COUNT(*) for existence check
final hasActive = (await ditto.store.execute(
  'SELECT COUNT(*) FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
)).items.first.value['($1)'] > 0;

// ✅ BETTER: LIMIT 1 for existence check
final hasActive = (await ditto.store.execute(
  'SELECT _id FROM orders WHERE status = :status LIMIT 1',
  arguments: {'status': 'active'},
)).items.isNotEmpty;
```

**Supported Functions**: `COUNT(*)`, `COUNT(field)`, `COUNT(DISTINCT field)`, `SUM(field)`, `AVG(field)`, `MIN(field)`, `MAX(field)`

---

### GROUP BY

**⚠️ IMPORTANT**: No JOIN support—cannot group across collections.

**✅ DO**: Ensure non-aggregate projections are in `GROUP BY`, use for analytics
**❌ DON'T**: Use as JOIN substitute, include non-grouped projections

```dart
// ✅ GOOD: Group by status
final result = await ditto.store.execute(
  '''SELECT status, COUNT(*) AS count, AVG(total) AS avg_total
     FROM orders GROUP BY status''',
);

// ❌ BAD: Non-aggregate projection without GROUP BY
final result = await ditto.store.execute(
  'SELECT status, customerId, COUNT(*) FROM orders GROUP BY status',
);
// ERROR: customerId not in GROUP BY

// ❌ BAD: Attempting JOIN with GROUP BY
final result = await ditto.store.execute(
  '''SELECT orders.customerId, customers.name, COUNT(*) AS order_count
     FROM orders GROUP BY orders.customerId''',
);
// ERROR: No JOIN support
```

**See Also**: [Denormalization for Performance](#denormalization-for-performance)

---

### HAVING

Filters grouped results (post-aggregation). `WHERE` filters before grouping (more efficient).

```dart
// ✅ GOOD: HAVING filters groups
final result = await ditto.store.execute(
  '''SELECT color, COUNT(*) AS count FROM cars
     GROUP BY color HAVING COUNT(*) > 5''',
);

// ✅ GOOD: Combine WHERE (pre-filter) and HAVING (post-filter)
final result = await ditto.store.execute(
  '''SELECT make, COUNT(*) AS count, AVG(price) AS avg_price FROM cars
     WHERE year >= :year GROUP BY make
     HAVING COUNT(*) >= 3 AND AVG(price) > 30000''',
  arguments: {'year': 2020},
);
```

---

### ORDER BY

Sorts results. Default: `ASC` (ascending).

**✅ DO**: Use with `LIMIT` for "top N", use expression-based sorting
**❌ DON'T**: Omit when using `LIMIT` (unpredictable results)

```dart
// ✅ GOOD: Basic sorting
final result = await ditto.store.execute(
  'SELECT * FROM cars ORDER BY year DESC, mileage ASC',
);

// ✅ GOOD: Expression-based (blue cars first)
final result = await ditto.store.execute(
  'SELECT * FROM cars ORDER BY color = \'blue\' DESC, make ASC',
);

// ✅ GOOD: Top 10 most expensive
final result = await ditto.store.execute(
  'SELECT make, model, price FROM cars ORDER BY price DESC LIMIT 10',
);
```

**Type Hierarchy (ASC)**: boolean → number → binary → string → array → object → null → missing
**DESC**: Reverse order

---

### LIMIT and OFFSET

**`LIMIT`**: Restricts number of documents
**`OFFSET`**: Skips documents before returning

**✅ DO**: Use `LIMIT` for pagination/"top N", combine with `ORDER BY`
**❌ DON'T**: Large `OFFSET` (linear performance degradation), `LIMIT` without `ORDER BY`

```dart
// ✅ GOOD: Pagination
final result = await ditto.store.execute(
  'SELECT * FROM orders ORDER BY createdAt DESC LIMIT 20 OFFSET 40',
);

// ✅ GOOD: Existence check with LIMIT 1
final hasActive = (await ditto.store.execute(
  'SELECT _id FROM orders WHERE status = :status LIMIT 1',
  arguments: {'status': 'active'},
)).items.isNotEmpty;

// ❌ BAD: Large OFFSET (performance degrades)
final result = await ditto.store.execute(
  'SELECT * FROM orders LIMIT 20 OFFSET 10000',
);

// ❌ BAD: LIMIT without ORDER BY (unpredictable)
final result = await ditto.store.execute(
  'SELECT * FROM cars LIMIT 10',
);
```

---

### Performance Best Practices

1. **Minimize Result Sets**: `WHERE` filters early, avoid `SELECT *`, use `LIMIT`
2. **Memory Management**: `DISTINCT`/aggregates buffer in memory, mobile constraints stricter
3. **Anti-Patterns**: Unbounded aggregates, `DISTINCT` with `_id`, large `OFFSET`, `SELECT *` in high-frequency queries, `COUNT(*)` for existence

**See Also**: [Query Result Handling](#query-result-handling), [Subscribe Broadly, Filter Narrowly](#subscribe-broadly-filter-narrowly)

---

## DQL Operator Expressions

### Date and Time Operators (SDK 4.11+)

**⚠️ SDK Version Requirement**: Date operators require SDK 4.11+

**Migration Context**: Historically, date comparisons used ISO-8601 strings (see [Timestamp Challenges](#timestamp-challenges-and-clock-drift)). SDK 4.11+ adds native date functions for more powerful temporal queries.

**Core Operators**: `date_cast`, `date_format`, `date_add`, `date_sub`, `date_diff`, `date_part`, `date_trunc`, `clock`, `tz_offset`

---

#### date_cast() - Parse String to Date

**Syntax**: `date_cast(stringExpr, formatString)` → date (epoch milliseconds UTC)

**✅ DO**: Parse custom date formats, handle multiple input formats
**❌ DON'T**: Use for ISO-8601 in WHERE (direct string comparison works)

```dart
// ✅ GOOD: Parse custom date format
final result = await ditto.store.execute(
  'SELECT * FROM events WHERE date_cast(dateStr, :format) > date_cast(:cutoff, :format)',
  arguments: {'format': '%Y-%m-%d', 'cutoff': '2025-01-01'},
);

// ❌ BAD: Unnecessary for ISO-8601 in WHERE
WHERE date_cast(createdAt, '%Y-%m-%dT%H:%M:%SZ') > '2025-01-01T00:00:00Z'
// Direct string comparison works: WHERE createdAt > '2025-01-01T00:00:00Z'
```

**Common Formats**: `%Y-%m-%d` (date), `%Y-%m-%dT%H:%M:%SZ` (ISO-8601), `%m/%d/%Y` (US date)

---

#### date_format() - Format Date as String

**Syntax**: `date_format(dateExpr, formatString)` → string

**✅ DO**: Format for display, extract date components for grouping
**❌ DON'T**: Use when date_part() is clearer for component extraction

```dart
// ✅ GOOD: Format for display
final result = await ditto.store.execute(
  'SELECT orderId, date_format(createdAt, :format) AS formattedDate FROM orders',
  arguments: {'format': '%B %d, %Y'}, // "January 15, 2025"
);

// ✅ GOOD: Extract month-year for grouping
final result = await ditto.store.execute(
  'SELECT date_format(createdAt, :format) AS month, COUNT(*) AS count FROM orders GROUP BY month',
  arguments: {'format': '%Y-%m'},
);
```

---

#### date_add() / date_sub() - Date Arithmetic

**Syntax**: `date_add(dateExpr, interval, unit)` → date, `date_sub(dateExpr, interval, unit)` → date

**Units**: `'year'`, `'month'`, `'day'`, `'hour'`, `'minute'`, `'second'`

**✅ DO**: Use for relative date queries (last N days, next N hours)
**❌ DON'T**: Pre-calculate dates in app when query-time calculation works

```dart
// ✅ GOOD: Last 30 days query
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE createdAt >= date_sub(clock(), :days, :unit)',
  arguments: {'days': 30, 'unit': 'day'},
);

// ✅ GOOD: Upcoming events (next 7 days)
final result = await ditto.store.execute(
  'SELECT * FROM events WHERE startDate BETWEEN clock() AND date_add(clock(), :days, :unit)',
  arguments: {'days': 7, 'unit': 'day'},
);

// ❌ BAD: Pre-calculated in app (less maintainable)
final cutoff = DateTime.now().subtract(Duration(days: 30)).toIso8601String();
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE createdAt >= :cutoff',
  arguments: {'cutoff': cutoff},
);
// Works, but query-time calculation is more maintainable
```

**Why**: Query-time calculation ensures consistency and avoids timezone/clock drift issues from client-side calculations.

---

#### date_diff() - Calculate Time Difference

**Syntax**: `date_diff(date1, date2, unit)` → number (integer)

**✅ DO**: Calculate duration between dates, filter by age
**❌ DON'T**: Use for simple "before/after" comparisons (use comparison operators)

```dart
// ✅ GOOD: Orders older than 7 days
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE date_diff(clock(), createdAt, :unit) > :threshold',
  arguments: {'unit': 'day', 'threshold': 7},
);

// ✅ GOOD: Calculate age in projection
final result = await ditto.store.execute(
  'SELECT userId, date_diff(clock(), birthdate, :unit) AS age FROM users',
  arguments: {'unit': 'year'},
);

// ❌ BAD: Simple comparison (use operators)
date_diff(createdAt, clock(), 'day') < 0 // Use createdAt > clock() instead
```

---

#### date_part() - Extract Date Components

**Syntax**: `date_part(dateExpr, part)` → number

**Parts**: `'year'`, `'month'`, `'day'`, `'hour'`, `'minute'`, `'second'`, `'dow'` (day of week 1-7, Monday=1), `'doy'` (day of year)

**✅ DO**: Filter by specific date components, group by day/month/weekday
**❌ DON'T**: Use for full date formatting (use date_format())

```dart
// ✅ GOOD: Filter by month (December)
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE date_part(createdAt, :part) = :month',
  arguments: {'part': 'month', 'month': 12},
);

// ✅ GOOD: Group by day of week
final result = await ditto.store.execute(
  'SELECT date_part(createdAt, :part) AS dayOfWeek, COUNT(*) AS count FROM orders GROUP BY dayOfWeek',
  arguments: {'part': 'dow'},
);
```

---

#### date_trunc() - Truncate to Period Start

**Syntax**: `date_trunc(dateExpr, unit)` → date

**Units**: `'year'`, `'month'`, `'day'`, `'hour'`, `'minute'`, `'second'`

**✅ DO**: Group by time periods (day, month, hour), find period boundaries
**❌ DON'T**: Use when date_part() suffices for component extraction

```dart
// ✅ GOOD: Group by day (ignoring time)
final result = await ditto.store.execute(
  'SELECT date_trunc(createdAt, :unit) AS day, COUNT(*) AS count FROM orders GROUP BY day',
  arguments: {'unit': 'day'},
);

// ✅ GOOD: Events starting this month
final result = await ditto.store.execute(
  'SELECT * FROM events WHERE createdAt >= date_trunc(clock(), :unit)',
  arguments: {'unit': 'month'},
);
```

---

#### clock() - Current Timestamp

**Syntax**: `clock()` → date (current UTC time as epoch milliseconds)

**⚠️ CAUTION**: Subject to device clock drift (see [Timestamp Challenges](#timestamp-challenges-and-clock-drift))

**✅ DO**: Use for relative queries (overdue tasks, expired sessions)
**❌ DON'T**: Rely on for strict ordering across devices (use createdAt comparisons)

```dart
// ✅ GOOD: Overdue tasks
final result = await ditto.store.execute(
  'SELECT * FROM tasks WHERE dueDate < clock() AND completed = false',
);

// ⚠️ CAUTION: Clock drift may cause inconsistencies across devices
// Consider using createdAt for ordering instead of clock() comparisons
```

---

#### tz_offset() - Timezone Conversion

**Syntax**: `tz_offset(dateExpr, timezone)` → date

**✅ DO**: Convert to local timezone for display
**❌ DON'T**: Store timezone-specific dates (store UTC, convert for display)

```dart
// ✅ GOOD: Convert to local timezone for display
final result = await ditto.store.execute(
  'SELECT orderId, tz_offset(createdAt, :tz) AS localTime FROM orders',
  arguments: {'tz': 'America/New_York'},
);
```

---

#### Migration Guide: ISO-8601 Strings → Date Operators

**Before (SDK <4.11)**:
```dart
// String comparison (lexicographic)
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE createdAt >= :cutoff',
  arguments: {'cutoff': '2025-01-01T00:00:00Z'},
);

// Pre-calculated cutoff in app
final cutoff = DateTime.now().subtract(Duration(days: 30)).toIso8601String();
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE createdAt >= :cutoff',
  arguments: {'cutoff': cutoff},
);
```

**After (SDK 4.11+)**:
```dart
// Native date parsing
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE createdAt >= date_cast(:cutoff, :format)',
  arguments: {'cutoff': '2025-01-01', 'format': '%Y-%m-%d'},
);

// Query-time calculation
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE createdAt >= date_sub(clock(), :days, :unit)',
  arguments: {'days': 30, 'unit': 'day'},
);
```

**When to Migrate**:
- ✅ Complex date queries (ranges, arithmetic, grouping)
- ✅ Timezone-aware queries
- ❌ Simple ISO-8601 comparisons (direct string comparison still works and is simpler)

**See Also**: [Timestamp Challenges and Clock Drift](#timestamp-challenges-and-clock-drift) (lines 3841-3996)

---

### Conditional Operators

**Purpose**: SQL-style null handling and conditional logic for schema-less documents

---

#### coalesce() - First Non-Null Value

**Syntax**: `coalesce(val1, val2, ..., valN)` → first non-null value

**✅ DO**: Multi-field fallback chains, default values
**❌ DON'T**: Use for single field (use nvl() instead)

```dart
// ✅ GOOD: Multi-field fallback
final result = await ditto.store.execute(
  'SELECT coalesce(preferredEmail, workEmail, personalEmail, :default) AS email FROM users',
  arguments: {'default': 'no-email'},
);

// ✅ GOOD: Default value for optional field
final result = await ditto.store.execute(
  'SELECT orderId, coalesce(discount, :defaultDiscount) AS finalDiscount FROM orders',
  arguments: {'defaultDiscount': 0.0},
);

// ❌ BAD: Single field (use nvl instead for clarity)
coalesce(status, 'pending') // Use nvl(status, 'pending') instead
```

---

#### nvl() - Null Value Replacement

**Syntax**: `nvl(input, default)` → input if not null, else default

**✅ DO**: Simple null-to-default conversions, null-safe arithmetic
**❌ DON'T**: Use for multi-field fallback (use coalesce())

```dart
// ✅ GOOD: Simple default
final result = await ditto.store.execute(
  'SELECT orderId, nvl(notes, :empty) AS orderNotes FROM orders',
  arguments: {'empty': ''},
);

// ✅ GOOD: Null-safe arithmetic
final result = await ditto.store.execute(
  'SELECT orderId, price * nvl(taxRate, :defaultRate) AS tax FROM orders',
  arguments: {'defaultRate': 0.0},
);
```

---

#### decode() - SQL-Style Value Mapping

**Syntax**: `decode(input, comp1, res1, comp2, res2, ..., default)` → matched result or default

**✅ DO**: Simple value mappings, status translations, priority scoring
**❌ DON'T**: Use for complex nested logic (better in app code)

```dart
// ✅ GOOD: Status display mapping
final result = await ditto.store.execute(
  '''SELECT orderId, decode(status,
       'pending', 'Pending',
       'shipped', 'Shipped',
       'delivered', 'Delivered',
       'Unknown') AS statusDisplay
     FROM orders''',
);

// ✅ GOOD: Priority scoring
final result = await ditto.store.execute(
  'SELECT taskId, decode(priority, \'high\', 3, \'medium\', 2, \'low\', 1, 0) AS score FROM tasks',
);

// ❌ BAD: Complex nested logic (do in app code)
decode(status, 'a', decode(subStatus, 'x', 1, 'y', 2, 3), 'b', 4, 5) // Too nested
```

**Why**: Simple value mappings in DQL reduce data transfer. Complex logic in app code is more maintainable.

---

### Type Checking Operators

**Purpose**: Runtime type validation for schema-less Ditto documents

**Use Cases**: Input validation, polymorphic queries, data quality checks

---

#### is_boolean(), is_number(), is_string() - Type Predicates

**Syntax**: `is_boolean(expr)`, `is_number(expr)`, `is_string(expr)` → boolean

**✅ DO**: Schema validation, polymorphic field handling, data quality checks
**❌ DON'T**: Rely on type checking for CRDT safety (design schema properly)

```dart
// ✅ GOOD: Validate before processing
final result = await ditto.store.execute(
  'SELECT * FROM events WHERE is_number(value) AND value > :threshold',
  arguments: {'threshold': 100},
);

// ✅ GOOD: Filter valid email strings
final result = await ditto.store.execute(
  'SELECT * FROM users WHERE is_string(email) AND email LIKE :pattern',
  arguments: {'pattern': '%@%.%'},
);

// ✅ GOOD: Polymorphic field handling
final result = await ditto.store.execute(
  '''SELECT * FROM logs WHERE
       (is_string(data) AND data LIKE :errorPattern) OR
       (is_number(data) AND data > :errorThreshold)''',
  arguments: {'errorPattern': '%error%', 'errorThreshold': 1000},
);

// ❌ BAD: Type checking instead of proper schema design
// Better: Store errorMessage and errorCode in separate fields
```

**Why**: Type checking adds query overhead. Validate at insert time to ensure type safety without runtime checks.

---

#### type() - Get Type Name

**Syntax**: `type(expr)` → string (`'boolean'`, `'number'`, `'string'`, `'array'`, `'object'`, `'null'`)

**✅ DO**: Debugging type mismatches, data quality analysis
**❌ DON'T**: Use in high-frequency queries (expensive)

```dart
// ✅ GOOD: Debugging type mismatches
final result = await ditto.store.execute(
  'SELECT _id, type(value) AS valueType FROM events WHERE type(value) != :expectedType',
  arguments: {'expectedType': 'number'},
);

// ✅ GOOD: Type distribution analysis
final result = await ditto.store.execute(
  'SELECT type(metadata) AS metadataType, COUNT(*) AS count FROM documents GROUP BY metadataType',
);
```

---

#### Use Case: Schema-less Validation Patterns

```dart
// ✅ GOOD: Defensive queries for user-generated data
final result = await ditto.store.execute(
  '''SELECT * FROM userInputs
     WHERE is_string(textField)
       AND is_number(ageField)
       AND ageField >= :minAge
       AND ageField <= :maxAge''',
  arguments: {'minAge': 0, 'maxAge': 120},
);

// ✅ GOOD: Identify malformed documents
final result = await ditto.store.execute(
  '''SELECT _id, type(requiredField) AS fieldType
     FROM collection
     WHERE type(requiredField) != :expectedType OR requiredField IS NULL''',
  arguments: {'expectedType': 'string'},
);
```

**See Also**: [Document Model and Data Types](#document-model-and-data-types) - Schema-less patterns

---

### String Operators

**Current Coverage**: LIKE operator (line 4385-4387)

**Expansion**: Concatenation, prefix/suffix matching, length functions, advanced patterns

---

#### || (Concatenation Operator)

**Syntax**: `str1 || str2 || ... || strN` → concatenated string
**Alias**: `concat(str1, str2, ...)`

**✅ DO**: Projections for display, composite key construction
**❌ DON'T**: Use in WHERE on large collections (pre-concatenate in app)

```dart
// ✅ GOOD: Display name formatting
final result = await ditto.store.execute(
  'SELECT firstName || \' \' || lastName AS fullName FROM users',
);

// ✅ GOOD: Composite key construction
final result = await ditto.store.execute(
  'SELECT customerId || \'_\' || orderId AS compositeKey FROM orders',
);

// ⚠️ CAUTION: In WHERE clause (less efficient than separate field queries)
WHERE firstName || ' ' || lastName = :fullName
// Better: WHERE firstName = :first AND lastName = :last
```

---

#### starts_with() / ends_with() - Prefix/Suffix Matching

**Syntax**: `starts_with(str, prefix)`, `ends_with(str, suffix)` → boolean

**✅ DO**: Prefix matching (index-friendly), domain filtering
**❌ DON'T**: Overuse suffix matching (full scan, no index)

```dart
// ✅ GOOD: Prefix matching (index can help)
final result = await ditto.store.execute(
  'SELECT * FROM products WHERE starts_with(sku, :prefix)',
  arguments: {'prefix': 'ELEC-'},
);

// ✅ GOOD: Domain filtering
final result = await ditto.store.execute(
  'SELECT * FROM users WHERE ends_with(email, :domain)',
  arguments: {'domain': '@company.com'},
);
```

**Index Usage**: `starts_with()` can use indexes (prefix scan), `ends_with()` cannot (full scan)

**LIKE Equivalent**: `starts_with(sku, 'ELEC-')` ≡ `sku LIKE 'ELEC-%'`, `ends_with(email, '@company.com')` ≡ `email LIKE '%@company.com'`

---

#### LIKE - Pattern Matching

**Syntax**: `field LIKE 'pattern'` (% = wildcard, _ = single char)

**Existing Documentation**: Lines 4385-4387 (index support for prefix patterns)

**✅ DO**: Prefix patterns (index-friendly), simple wildcards
**❌ DON'T**: Suffix/infix patterns without WHERE filters (full collection scan)

```dart
// ✅ GOOD: Prefix pattern (index can help)
final result = await ditto.store.execute(
  'SELECT * FROM products WHERE name LIKE :pattern',
  arguments: {'pattern': 'Apple%'},
);

// ❌ BAD: Suffix pattern (full scan, no index help)
final result = await ditto.store.execute(
  'SELECT * FROM products WHERE name LIKE :pattern',
  arguments: {'pattern': '%Phone'},
);

// ⚠️ CAUTION: Infix pattern (full scan, acceptable if result set small)
final result = await ditto.store.execute(
  'SELECT * FROM products WHERE category = :cat AND name LIKE :pattern',
  arguments: {'cat': 'electronics', 'pattern': '%Watch%'},
);
```

**See Also**: [Index Limitations](#index-limitations-and-considerations) (lines 4369-4393)

---

#### SIMILAR TO - Regex-Style Pattern Matching

**Syntax**: `field SIMILAR TO 'pattern'` (SQL standard regex subset)

**Patterns**: `%` (wildcard), `_` (single char), `[abc]` (character class), `(a|b)` (alternation)

**✅ DO**: Complex patterns, validation (phone numbers, formats)
**❌ DON'T**: Overuse (performance impact), use when LIKE suffices

```dart
// ✅ GOOD: Phone number validation
final result = await ditto.store.execute(
  'SELECT * FROM contacts WHERE phone SIMILAR TO :pattern',
  arguments: {'pattern': '[0-9]{3}-[0-9]{3}-[0-9]{4}'},
);

// ✅ GOOD: Multiple suffix matching
final result = await ditto.store.execute(
  'SELECT * FROM files WHERE filename SIMILAR TO :pattern',
  arguments: {'pattern': '%(%.jpg|%.png|%.gif)'},
);

// ❌ BAD: Simple pattern (use LIKE)
SIMILAR TO 'Apple%' // Use LIKE 'Apple%' instead
```

**Performance**: Slower than LIKE, no index support

---

#### byte_length() / char_length() - String Length

**Syntax**: `byte_length(str)`, `char_length(str)` → number

**✅ DO**: Filter by length, storage analysis
**❌ DON'T**: Use for empty string checks (use comparison operators)

```dart
// ✅ GOOD: Filter by character length
final result = await ditto.store.execute(
  'SELECT * FROM posts WHERE char_length(content) > :minLength',
  arguments: {'minLength': 100},
);

// ✅ GOOD: Storage analysis
final result = await ditto.store.execute(
  'SELECT char_length(description) AS descLength FROM products ORDER BY descLength DESC',
);
```

**Difference**: `byte_length()` counts UTF-8 bytes, `char_length()` counts Unicode characters

---

### Object Operators (SDK 4.x+)

**Purpose**: Inspect MAP CRDT structure dynamically for debugging and schema discovery

**Use Cases**: MAP introspection, debugging nested objects, data quality checks

---

#### object_keys() - Get Object Keys

**Syntax**: `object_keys(objectExpr)` → array of strings

**✅ DO**: Schema discovery, debugging, find unexpected keys
**❌ DON'T**: Use in high-frequency queries (expensive operation)

```dart
// ✅ GOOD: Debugging - find documents with unexpected keys
final result = await ditto.store.execute(
  'SELECT _id, object_keys(metadata) FROM orders WHERE :key IN object_keys(metadata)',
  arguments: {'key': 'unexpectedKey'},
);

// ✅ GOOD: Schema discovery (one-time analysis)
final result = await ditto.store.execute(
  'SELECT DISTINCT object_keys(customFields) AS fieldNames FROM products',
);
```

**Why**: `object_keys()` requires loading full object into memory. Use sparingly in observers.

---

#### object_values() - Get Object Values

**Syntax**: `object_values(objectExpr)` → array of values

**✅ DO**: Check if any nested value matches search term
**❌ DON'T**: Use in high-frequency observers (expensive)

```dart
// ✅ GOOD: Check if any nested value matches
final result = await ditto.store.execute(
  'SELECT * FROM documents WHERE :searchTerm IN object_values(tags)',
  arguments: {'searchTerm': 'important'},
);
```

**⚠️ CAUTION**: Returns mixed types (arrays not type-homogeneous)

---

#### object_length() - Count Object Keys

**Syntax**: `object_length(objectExpr)` → number

**✅ DO**: Filter by MAP size, identify sparse vs dense objects
**❌ DON'T**: Use to check if empty (use `IS NULL` or key existence)

```dart
// ✅ GOOD: Filter objects with many keys
final result = await ditto.store.execute(
  'SELECT * FROM users WHERE object_length(preferences) > :threshold',
  arguments: {'threshold': 10},
);

// ✅ GOOD: Identify sparse vs dense objects
final result = await ditto.store.execute(
  'SELECT _id, object_length(customFields) AS fieldCount FROM products ORDER BY fieldCount DESC',
);

// ❌ BAD: Check if empty (use IS NULL)
object_length(obj) = 0 // Use obj IS NULL instead
```

---

#### Use Case: MAP CRDT Debugging

```dart
// ✅ GOOD: Find orders with specific item keys
final result = await ditto.store.execute(
  'SELECT _id, object_keys(items) AS itemKeys FROM orders WHERE object_length(items) > 0',
);

// ✅ GOOD: Detect schema drift
final result = await ditto.store.execute(
  'SELECT _id FROM documents WHERE NOT (:requiredField IN object_keys(data))',
  arguments: {'requiredField': 'requiredField'},
);
```

**See Also**: [Array Limitations](#array-limitations) - Why MAP is preferred over arrays

---

### Collection Operators

**Purpose**: Membership testing with IN/NOT IN

---

#### IN Operator

**Syntax**: `value IN (val1, val2, ..., valN)` or `value IN arrayExpr`

**✅ DO**: Filter by multiple values, array membership
**❌ DON'T**: Use with unbounded lists (pre-filter in app)

```dart
// ✅ GOOD: Status filtering (value list)
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status IN (:statuses)',
  arguments: {'statuses': ['pending', 'processing', 'shipped']},
);

// ✅ GOOD: Array membership (tags field is array)
final result = await ditto.store.execute(
  'SELECT * FROM products WHERE :tag IN tags',
  arguments: {'tag': 'electronics'},
);

// ❌ BAD: Large lists (hundreds of values, pre-filter in app)
final largeList = List.generate(500, (i) => 'val$i');
WHERE status IN (:largeList) // Better: Multiple queries or restructure data
```

**Array Support**: Works with array fields (checks if value is array element)

---

#### NOT IN Operator

**Syntax**: `value NOT IN (val1, val2, ..., valN)` or `value NOT IN arrayExpr`

**✅ DO**: Exclude specific values
**❌ DON'T**: Use with NULL values without understanding behavior

```dart
// ✅ GOOD: Exclude statuses
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status NOT IN (:excludedStatuses)',
  arguments: {'excludedStatuses': ['canceled', 'returned']},
);

// ✅ GOOD: Exclude tagged products
final result = await ditto.store.execute(
  'SELECT * FROM products WHERE :excludedTag NOT IN tags',
  arguments: {'excludedTag': 'deprecated'},
);
```

**⚠️ NULL Behavior**: If value is NULL, `NOT IN` returns NULL (not true), filtering out the row

---

#### Performance Considerations

**Index Usage**: `IN` operator can use indexes (SDK 4.13+ with union scans)

```dart
// ✅ GOOD: Index-friendly (SDK 4.13+)
// CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status IN (:statuses)',
  arguments: {'statuses': ['pending', 'processing']},
);
// Uses union scan across multiple index values
```

**See Also**: [Union and Intersect Scans](#advanced-index-usage-sdk-4130) (lines 4327-4356)

---

### Operator Performance Considerations

**General Principles**:
1. **Type checking**: Slower than schema design (validate at insert time)
2. **String operations**: LIKE prefix > starts_with ≈ LIKE suffix > SIMILAR TO
3. **Date operators**: Negligible overhead vs string comparison (SDK 4.11+ optimized)
4. **Object introspection**: Expensive (`object_keys`, `object_values`) - avoid in hot paths
5. **IN operator**: Efficient for small lists (<50 values), inefficient for large lists

---

#### Index-Friendly Operators (SDK 4.13+)

**Can Use Indexes**:
- `IN` with value lists (union scans)
- `starts_with()` / `LIKE 'prefix%'` (prefix scans)
- Date comparisons with `date_cast()` (if indexed field)

**Cannot Use Indexes**:
- `ends_with()` / `LIKE '%suffix'` (full scan)
- `SIMILAR TO` (full scan)
- `object_keys()`, `object_values()` (requires loading full object)
- Type checking operators (requires loading values)

---

#### Memory Impact

**Low Memory**:
- `coalesce()`, `nvl()`, `decode()` - Minimal overhead
- `char_length()`, `byte_length()` - Constant memory

**Medium Memory**:
- `date_*()` operators - Temporary date objects
- String concatenation (`||`) - Allocates new strings

**High Memory**:
- `object_keys()`, `object_values()` - Allocates arrays for all keys/values

---

#### Best Practices

**✅ DO**:
- Use specific operators over generic (starts_with > LIKE > SIMILAR TO)
- Combine operators with WHERE filters (reduce working set first)
- Use indexes for operators that support them
- Validate types at insert time (not query time)

**❌ DON'T**:
- Chain expensive operators without WHERE filters
- Use object introspection in high-frequency observers
- Use complex patterns when simpler alternatives work
- Rely on type checking for correctness (design schema properly)

**See Also**: [Index Limitations](#index-limitations-and-considerations) (lines 4369-4393), [Query Performance](#performance-best-practices) (lines 735-742)

---

## Document Model and Data Types

### Supported Data Types

Ditto documents support JSON-like data types with CRDT backing:

**Scalar Types:**
- Strings, numbers, booleans
- Dates and timestamps

**Complex Types:**
- Objects (nested documents) - stored as MAP CRDT
- Arrays - see critical warning below
- Attachments (large binary files)

**Important**: Each field value is stored as a specific CRDT type (MAP, REGISTER, etc.) for automatic conflict resolution.

### ⚠️ CRITICAL: Array Limitations

**Arrays have significant limitations in Ditto due to CRDT merge conflicts:**

**See Also**:
- [Event History and Audit Logs](#event-history-and-audit-logs) - Recommended patterns for append-only data
- [Glossary: REGISTER](#glossary) - CRDT type details for arrays

**❌ DON'T:**
- Use arrays for data that multiple peers may modify concurrently
- Store mutable items in arrays that need to be updated individually

```dart
// ❌ BAD: Array with concurrent updates causes conflicts
{
  "_id": "order_123",
  "items": [
    {"id": "item1", "quantity": 2},  // Multiple peers updating quantity
    {"id": "item2", "quantity": 1}
  ]
}
// When offline peers reconnect, array merge conflicts can occur
```

**Why Arrays Are Problematic:**
When multiple offline peers make concurrent updates to the same array index, Ditto cannot reliably merge changes. This can lead to:
- Lost updates
- Duplicate entries
- Inconsistent array state across peers

**✅ DO:**
- Use MAP (object) structures instead of arrays for mutable data
- Use separate documents (INSERT) for event logs and audit trails
- Embed simple read-only arrays that never change after creation

```dart
// ✅ GOOD: Use keyed MAP structure for concurrent updates
{
  "_id": "order_123",
  "items": {
    "item1": {"quantity": 2, "productId": "p1"},  // Each key independently mergeable
    "item2": {"quantity": 1, "productId": "p2"}   // Avoids last-write-wins conflicts
  }
}

// ⚠️ CAUTION: Arrays are REGISTERS (Last-Write-Wins)
// Arrays use LWW - entire array atomically replaced on concurrent updates

// ✅ ACCEPTABLE: Static read-only array (never modified after creation)
{
  "_id": "product_456",
  "tags": ["electronics", "gadget", "bestseller"]
}
```

**Why MAP is Better:**
MAP (object) CRDT types use "add-wins" strategy, automatically merging concurrent updates to different keys without conflicts.

### Document Structure Best Practices

**Document Identity:**
- Every document must have a unique `_id` field (primary key)
- Ditto auto-generates `_id` if omitted
- `_id` cannot be changed after creation
- Supports composite keys (objects as `_id` values) for complex hierarchies

```dart
// ✅ GOOD: Composite key for multi-dimensional organization
{
  "_id": {
    "storeId": "store_001",
    "orderId": "order_123"
  },
  "total": 45.50
}
```

**Field Naming:**
- Only strings allowed for field names
- Use consistent naming conventions

**CRDT Type Behaviors:**
- **REGISTER**: Last-write-wins for scalar values
- **MAP**: Add-wins for object properties (concurrent updates merge)
- **PN_COUNTER** (Legacy): Distributed counter CRDT using positive-negative semantics. Accessed via `PN_INCREMENT BY` operator in UPDATE statements. Remains supported for backward compatibility.
- **COUNTER** (Ditto 4.14.0+): Native counter CRDT type with explicit type declaration. Provides `INCREMENT BY`, `RESTART WITH`, and `RESTART` operations. Recommended for new implementations.
- **Attachments**: Must be explicitly fetched (not auto-synced)

**CRDT Conflict Resolution:**
- **REGISTER (scalars, arrays)**: Last-write-wins (LWW) based on Hybrid Logical Clock (HLC). Arrays use LWW, causing data loss on concurrent updates—use MAP instead.
- **MAP (objects)**: Add-wins strategy. Concurrent field updates merge automatically.
- **COUNTER/PN_COUNTER (INCREMENT)**: Commutative addition. All increments summed across peers.
- **COUNTER (RESTART WITH)**: Last-write-wins for RESTART operations.

---

### Exclude Unnecessary Fields from Documents

**⚠️ CRITICAL**: Every field in a document syncs across the mesh. Including unnecessary fields degrades performance for all peers.

#### Fields That Should NOT Be in Documents

**Don't sync**:
- **UI state**: isExpanded, selected, isHovered
- **Calculated values**: lineTotal (price × quantity), subtotal, total, tax, averages, sums
- **Temporary state**: uploadProgress, isProcessing, isSaving
- **Device-specific data**: local file paths, device IDs (unless needed for business logic)

**Why**: Unnecessary fields multiply bandwidth × devices × sync frequency. Example: 470 bytes of bloat in 1000 docs across 10 devices = 4.7 MB wasted per sync.

**⚠️ CRITICAL: DO NOT STORE CALCULATED FIELDS**

Fields that can be calculated from existing data should **never** be stored in documents:

❌ **DON'T**: Store calculated totals
```dart
// ❌ BAD: Storing calculated values
{
  "_id": "order_123",
  "items": {
    "item_1": {
      "price": 12.99,
      "quantity": 2,
      "lineTotal": 25.98  // ❌ Calculated: price × quantity
    }
  },
  "subtotal": 25.98,  // ❌ Calculated: sum of lineTotals
  "tax": 2.60,        // ❌ Calculated: subtotal × taxRate
  "total": 28.58      // ❌ Calculated: subtotal + tax
}
// Problems: Wastes bandwidth, increases sync traffic, adds document size
```

✅ **DO**: Calculate in application layer
```dart
// ✅ GOOD: Store only source data
{
  "_id": "order_123",
  "items": {
    "item_1": {
      "price": 12.99,
      "quantity": 2
    }
  }
}

// Calculate on-demand in app
double calculateLineTotal(Map<String, dynamic> item) {
  return item['price'] * item['quantity'];
}

double calculateSubtotal(Map<String, dynamic> items) {
  return items.values.fold(0.0, (sum, item) =>
    sum + (item['price'] * item['quantity']));
}

double calculateTotal(double subtotal, double taxRate) {
  final tax = subtotal * taxRate;
  return subtotal + tax;
}
```

**Why Calculate Instead of Store?**
- ✅ Reduces document size (faster sync, lower bandwidth)
- ✅ Eliminates stale data risk (calculations always current)
- ✅ Avoids synchronization overhead (no deltas for derived values)
- ✅ Simplifies updates (update source data only, calculations automatically reflect changes)

**Examples of Calculated Fields to Avoid**:
- `lineTotal = price × quantity`
- `subtotal = sum(lineTotals)`
- `total = subtotal + tax`
- `averageRating = sum(ratings) / count(ratings)`
- `remainingStock = initialStock - sum(orderQuantities)` (see [Counter Anti-Patterns](#counter-anti-patterns-and-alternatives))
- `age = currentDate - birthdate`
- `daysUntilExpiry = expiryDate - currentDate`

---

### DQL Strict Mode (v4.11+)

**What is Strict Mode:**
DQL Strict Mode enforces structure and CRDT type safety in collections. It determines how nested objects are treated during synchronization.

**Default Behavior (Strict Mode = true):**
- All fields are treated as REGISTER by default
- Nested objects default to REGISTER (whole-object replacement on update)
- Requires explicit collection definitions for MAP CRDT types
- Provides predictable behavior and type safety

**Configuration:**
```dart
// Disable strict mode (must be done BEFORE startSync)
await ditto.store.execute('ALTER SYSTEM SET DQL_STRICT_MODE = false');
await ditto.startSync();
```

**⚠️ CRITICAL: Always await ALTER SYSTEM SET**
`store.execute()` is async, and proceeding without awaiting can cause unexpected behavior:
- System settings may not be applied before subsequent operations
- Starting sync before settings are applied can lead to inconsistent behavior
- **Always use `await`** before calling `startSync()` or other store operations

```dart
// ✅ CORRECT: await ensures settings are applied before sync starts
await ditto.store.execute('ALTER SYSTEM SET DQL_STRICT_MODE = false');
await ditto.startSync();

// ❌ WRONG: Settings might not be applied when startSync runs
ditto.store.execute('ALTER SYSTEM SET DQL_STRICT_MODE = false'); // Missing await!
await ditto.startSync(); // May start with wrong settings
```

**⚠️ CRITICAL: Cross-Peer Consistency**
**All peers must use the same DQL_STRICT_MODE setting.** When peers have different settings:
- Data will sync between peers successfully
- However, behavior changes unpredictably
- Nested field updates may appear missing if strict mode peers lack explicit MAP definitions

**Strict Mode Disabled (false):**
- Automatic CRDT type inference based on document shape
- Objects automatically treated as MAPs (field-level merging)
- Useful for dynamic key-value data without predefined schemas

**Recommendation**: Keep enabled (default) for production. All peers must use same setting.

---

#### When to Enable/Disable Strict Mode

**✅ Keep ENABLED (true - default)**: Production apps, new projects (SDK 4.11+), teams, type safety needed

**⚠️ Disable (false) only for**: Migrating from SDK <4.11 (legacy), fully dynamic schemas, rapid prototyping

---

#### Practical Implications

**Strict Mode = true (Default):**

```dart
// ❌ BAD: Nested field update fails without explicit MAP definition
await ditto.store.execute(
  'UPDATE orders SET metadata.updatedAt = :date WHERE _id = :id',
  arguments: {'date': DateTime.now().toIso8601String(), 'id': orderId},
);
// ERROR: Cannot update nested field - 'metadata' is REGISTER (whole-object replacement)

// ✅ GOOD: Define collection with explicit MAP type
await ditto.store.execute(
  '''CREATE COLLECTION IF NOT EXISTS orders (
       metadata MAP
     )'''
);

// Now nested field updates work
await ditto.store.execute(
  'UPDATE orders SET metadata.updatedAt = :date WHERE _id = :id',
  arguments: {'date': DateTime.now().toIso8601String(), 'id': orderId},
);
```

**Strict Mode = false:**

```dart
// ✅ Nested field updates work automatically (objects inferred as MAP)
await ditto.store.execute(
  'UPDATE orders SET metadata.updatedAt = :date WHERE _id = :id',
  arguments: {'date': DateTime.now().toIso8601String(), 'id': orderId},
);
// Works without explicit collection definition - 'metadata' automatically treated as MAP
```

---

#### Common Pitfalls

**Pitfall 1: Forgetting Collection Definitions**

```dart
// Strict mode enabled, missing collection definition
await ditto.store.execute(
  'UPDATE products SET metadata.updatedBy = :userId WHERE _id = :id',
  arguments: {'userId': 'user_456', 'id': 'prod_123'},
);
// ERROR: 'metadata' is REGISTER - cannot update nested field
```

**Solution**: Define collection with MAP type first.

**Pitfall 2: Mixed Strict Mode Across Peers**

```dart
// Device A (strict=true) vs Device B (strict=false)
// Result: Inconsistent CRDT behavior after sync
```

**Solution**: Ensure all peers use the same strict mode setting.

---

#### Performance Considerations

**Strict Mode Performance Impact:**

| Aspect | Strict Mode = true | Strict Mode = false |
|--------|-------------------|---------------------|
| **Query Performance** | Same | Same |
| **Sync Performance** | Same | Same |
| **Type Checking** | Explicit (faster) | Inferred (minimal overhead) |
| **Memory Usage** | Same | Same |
| **Developer Overhead** | Higher (explicit definitions) | Lower (automatic inference) |

**Key Insight**: Strict mode setting has minimal runtime performance impact. The primary difference is development workflow (explicit vs. automatic type inference).

---

#### Migration Strategy

**Migrating from SDK <4.11** (strict mode was false):

**Option 1**: Keep disabled - `ALTER SYSTEM SET DQL_STRICT_MODE = false`

**Option 2** (Recommended): Enable strict mode
1. Audit nested field updates
2. Add explicit MAP collection definitions
3. Enable on all peers simultaneously

---

## ID Generation Strategies for Distributed Systems

### ⚠️ CRITICAL: Avoid Sequential IDs in Distributed Databases

Sequential IDs cause collisions when multiple devices write independently in offline-first, P2P mesh architectures.

**Problem Scenario:**
```dart
// ❌ BAD: Sequential ID generation
final orderId = 'order_${DateTime.now().toString()}_001';

// Collision scenario:
// - Device A offline at 2025-01-15: generates "order_20250115_001"
// - Device B offline at 2025-01-15: generates "order_20250115_001"
// - Both devices sync → COLLISION → data loss or undefined behavior
```

**Why Sequential IDs Fail:**
- Assumes single writer (centralized system assumption)
- Multiple devices independently generate IDs offline
- No coordination mechanism to prevent duplicates
- Last-write-wins (LWW) may overwrite valid data

---

### Recommended Patterns

#### Pattern 1: UUID v4 (Primary Recommendation)

**✅ DO: Use UUID v4 for distributed-safe ID generation**

```dart
import 'package:uuid/uuid.dart';

final uuid = Uuid();
final orderId = uuid.v4(); // "7c0c20ed-b285-48a6-80cd-6dcf06d52bcc"

await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {
    'order': {
      '_id': orderId,
      'orderNumber': '#42',
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    }
  },
);
```

**Why UUID v4?**
- **Collision-free**: ~1 in 2^61 collision probability for 1 billion IDs
- **No coordination required**: Devices generate IDs independently
- **Aligns with Ditto**: Native auto-generated IDs are 128-bit UUIDs
- **Platform-agnostic**: UUID libraries available on all platforms
- **Industry standard**: Widely adopted for distributed systems

---

#### Pattern 2: Auto-Generated (Simplest)

**✅ DO: Omit `_id` to let Ditto auto-generate UUIDs**

```dart
// Simplest approach - omit _id, Ditto auto-generates 128-bit UUID
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {
    'order': {
      // No _id field - Ditto generates UUID automatically
      'orderNumber': '#42',
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    }
  },
);
```

**When to use:**
- Internal documents where ID format doesn't matter
- Simplest implementation (no external library needed)
- Prefer explicit UUID v4 when ID control is desired

---

#### Pattern 3: Composite Keys (Advanced)

**✅ DO: Use composite keys for permission scoping or query optimization**

```dart
final uuid = Uuid();
final locationId = 'LondonLiverpoolStreet';
final orderId = uuid.v4();

await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {
    'order': {
      '_id': {
        'locationId': locationId,
        'orderId': orderId,
      },
      // Duplicate for POJO/DTO pattern (query-friendly)
      'locationId': locationId,
      'orderId': orderId,
      'status': 'pending',
    }
  },
);
```

**When to use:**
- Multi-tenant systems with permission scoping
- Query optimization (indexed composite fields)
- Hierarchical data organization

**Trade-offs:**
- Higher complexity (object-based IDs)
- Requires field duplication for efficient queries
- Better for advanced use cases

---

#### Pattern 4: ULID (Time-Ordered)

**✅ DO: Use ULID when chronological ordering is required**

```dart
import 'package:ulid/ulid.dart';

final ulid = Ulid().toString(); // "01ARZ3NDEKTSV4RRFFQ69G5FAV"

await ditto.store.execute(
  'INSERT INTO events DOCUMENTS (:event)',
  arguments: {
    'event': {
      '_id': ulid,
      'type': 'user_action',
      'timestamp': DateTime.now().toIso8601String(),
    }
  },
);
```

**When to use:**
- Time-based queries requiring chronological ordering
- Lexicographically sortable IDs (first 48 bits = millisecond timestamp)
- Event logs, audit trails, time-series data

**Trade-offs:**
- Requires external library (ulid package)
- Less familiar to developers than UUID
- Still collision-free with randomness component

---

### Decision Tree

Use this decision tree to choose the right ID generation pattern:

```
Need to generate document _id?
  ↓
Human-readable required for debugging?
  ↓ YES → Add display field alongside UUID
  |         (_id: UUID, displayId: "ORD-2025-042")
  ↓ NO
  ↓
Chronological sorting required?
  ↓ YES → Use ULID (time-ordered)
  ↓ NO
  ↓
Permission scoping needed?
  ↓ YES → Use Composite Keys
  ↓ NO
  ↓
Want simplest approach?
  ↓ YES → Omit _id (auto-generated)
  ↓ NO
  ↓
→ Use UUID v4 (general-purpose, recommended)
```

---

### Platform Implementations

#### Dart/Flutter

```dart
import 'package:uuid/uuid.dart';

final uuid = Uuid();
final id = uuid.v4(); // "7c0c20ed-b285-48a6-80cd-6dcf06d52bcc"
```

**Add to `pubspec.yaml`:**
```yaml
dependencies:
  uuid: ^4.2.0
```

#### JavaScript/TypeScript

```javascript
import { v4 as uuidv4 } from 'uuid';

const id = uuidv4(); // "7c0c20ed-b285-48a6-80cd-6dcf06d52bcc"
```

**Install via npm:**
```bash
npm install uuid
```

#### Swift

```swift
import Foundation

let id = UUID().uuidString.lowercased() // "7c0c20ed-b285-48a6-80cd-6dcf06d52bcc"
```

**Native Foundation framework** (no external dependency)

#### Kotlin

```kotlin
import java.util.UUID

val id = UUID.randomUUID().toString() // "7c0c20ed-b285-48a6-80cd-6dcf06d52bcc"
```

**Native Java UUID** (no external dependency)

---

### Human-Readable Display IDs

**✅ DO: Combine UUID (primary key) with human-readable display fields**

```dart
import 'dart:math';
import 'package:uuid/uuid.dart';

final uuid = Uuid();
final orderId = uuid.v4();

// Generate human-readable display ID with random suffix
final date = DateTime.now();
final dateStr = '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
final randomSuffix = Random().nextInt(0xFFFF).toRadixString(16).toUpperCase().padLeft(4, '0');
final displayId = 'ORD-$dateStr-$randomSuffix';  // e.g., "ORD-20251219-A7F3"

await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {
    'order': {
      '_id': orderId,                    // UUID (primary key, collision-free)
      'displayId': displayId,            // Human-readable display (date + random)
      'status': 'pending',
    }
  },
);
```

**⚠️ NOTE: displayId does not need to be globally unique (it's not the document ID)**

**Why random suffix?**
- Reduces likelihood of confusion when displaying multiple orders to users
- Maintains human-readable format with better user experience
- Random component helps avoid duplicate display IDs on same day
- Not required for system correctness (document uniqueness is ensured by _id)

**Benefits:**
- UUID ensures collision-free primary key (document uniqueness)
- Display fields improve debugging and UI user experience
- Best of both worlds: safety + readability

**❌ DON'T: Sequential displayId without random component (poor UX)**
```dart
// ❌ BAD: Sequential displayId (poor user experience)
final displayId = 'ORD-${dateStr}-001';  // Multiple devices can generate same display ID
```

---

### Migration from Sequential IDs

**Dual-Write Pattern** (Recommended for existing apps):

```dart
import 'package:uuid/uuid.dart';

final uuid = Uuid();

// Step 1: Generate new UUID
final newOrderId = uuid.v4();

// Step 2: Keep legacy ID for backward compatibility
final legacyOrderId = 'order_20250115_001';

// Step 3: Write with both IDs
await ditto.store.execute(
  '''
  INSERT INTO orders DOCUMENTS (:order)
  ''',
  arguments: {
    'order': {
      '_id': newOrderId,         // New UUID (primary)
      'legacyOrderId': legacyOrderId, // Keep for reference
      'orderNumber': '#42',
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    }
  },
);

// Step 4: Query by new UUID (primary)
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE _id = :orderId',
  arguments: {'orderId': newOrderId},
);

// Step 5: Query by legacy ID (if needed during migration)
final legacyResult = await ditto.store.execute(
  'SELECT * FROM orders WHERE legacyOrderId = :legacyId',
  arguments: {'legacyId': legacyOrderId},
);
```

**Migration Steps:**

1. **Add UUID library** to project dependencies
2. **Update ID generation code** to use UUID v4
3. **Keep legacy ID** in separate field during transition period
4. **Update queries** to use new UUID field as primary
5. **Monitor for issues** during transition (logs, analytics)
6. **Eventually remove legacy ID field** after full migration

**Timeline:**
- **Week 1-2**: Deploy dual-write pattern (both IDs)
- **Week 3-4**: Verify all clients using new UUID queries
- **Week 5+**: Remove legacy ID field from schema

---

### Anti-Patterns

#### ❌ DON'T: Sequential IDs

```dart
// ❌ BAD: Date-based sequential IDs
final orderId = 'order_${DateTime.now().toString()}_001';

// ❌ BAD: Counter-based IDs
final productId = 'product_$counter';

// ❌ BAD: Timestamp-based IDs
final eventId = 'event_${DateTime.now().millisecondsSinceEpoch}_001';
```

**Why These Fail:**
- Multiple devices offline can generate identical IDs
- Assumes centralized ID generation (not P2P safe)
- Collision probability increases with device count
- Last-write-wins overwrites valid data

#### ❌ DON'T: Timestamp-Only IDs

```dart
// ❌ BAD: Timestamp-only (no randomness)
final id = DateTime.now().millisecondsSinceEpoch.toString();

// Problem: Multiple writes within same millisecond → collision
```

**Why This Fails:**
- No randomness component
- Collisions within same millisecond window
- Especially problematic in high-throughput scenarios

---

### Best Practices Summary

**✅ DO:**
- Use UUID v4 for general-purpose distributed-safe IDs
- Omit `_id` for simplest approach (auto-generated UUIDs)
- Use composite keys for permission scoping
- Use ULID for time-ordered requirements
- Add human-readable display fields alongside UUIDs
- Migrate from sequential IDs using dual-write pattern

**❌ DON'T:**
- Use sequential IDs in distributed systems
- Generate IDs based on timestamps alone
- Assume centralized ID coordination
- Ignore collision risks in offline-first scenarios

**Key Insight**: In distributed, offline-first systems, collision-free ID generation is critical. UUID v4 provides the best balance of simplicity, safety, and platform support.

---

### Document Size and Performance Guidelines

**Size Limits:**
- **Hard limit**: Documents exceeding 5 MB will not sync with peers
- **Warning threshold**: Documents over 250 KB trigger console warnings
- **Performance impact**: On Bluetooth LE, replication maxes at ~20 KB/second
  - A 250 KB document takes 10+ seconds for initial sync
  - Larger documents cause significant delays on mobile/IoT devices

**✅ DO:**
- Keep documents under 250 KB for optimal performance
- **Balance embed vs flat based on access patterns** (see Relationship Modeling section)
- Embed related data when retrieved together (avoids sequential queries due to no JOIN support)
- Use flat models for data that grows unbounded or is accessed independently
- Store large binary files (>250 KB) using ATTACHMENT data type

```dart
// ✅ GOOD: Embedded when data is retrieved together
{
  "_id": "order_123",
  "customerId": "cust_456",
  "items": [  // Embed items - avoids sequential queries
    {"productId": "prod_1", "quantity": 2, "price": 10.00},
    {"productId": "prod_2", "quantity": 1, "price": 25.00}
  ],
  "total": 45.00
}

// ✅ GOOD: Flat when data is accessed independently
// people collection
{
  "_id": "person_123",
  "name": "Alice",
  "email": "alice@example.com"
}

// cars collection (accessed independently from people)
{
  "_id": "car_456",
  "ownerId": "person_123",  // Foreign key reference
  "make": "Toyota",
  "model": "Camry"
}
```

**❌ DON'T:**
- Embed data that grows unbounded (exceeds size limits)
- Use deeply nested maps (3+ levels) without good reason
- Store large binary data directly in documents (use ATTACHMENT type)

```dart
// ❌ BAD: Unbounded growth in embedded structure
{
  "_id": "person_123",
  "name": "Alice",
  "cars": [
    {
      "make": "Toyota",
      "model": "Camry",
      "maintenance": [  // Can grow to hundreds of entries!
        {"date": "2025-01-15", "type": "oil_change", "cost": 45.00},
        {"date": "2025-02-20", "type": "tire_rotation", "cost": 35.00},
        // ... hundreds more entries - document becomes too large!
      ],
      "photos": ["base64_encoded_large_image..."]  // Large binary data!
    }
  ]
}
// Problems: Too large, slow to sync, difficult to update concurrently
// Solution: Use separate maintenance_logs collection with foreign key
```

**Key Considerations:**
- **Embed benefits**: Single-query access (important with no JOIN support), simpler code
- **Flat benefits**: Independent sync, concurrent edits without conflicts, parallel sync efficiency
- **Choose based on**: Access patterns, growth potential, document size limits, concurrent edit likelihood

### Relationship Modeling: Embedded vs Flat

**⚠️ CRITICAL: No JOIN Support**
Ditto does not currently support JOIN operations. This has major implications for data modeling:
- **Foreign key references require sequential queries** (fetch order → fetch items), causing significant performance overhead
- **Embedded data enables single-query access**, which is much faster when data needs to be retrieved together
- Choose your model based on access patterns and whether data needs to be retrieved together

**When to Embed (nested objects):**
- **Data retrieved/updated together as a unit** (MOST IMPORTANT: avoids sequential queries)
- Related data that logically belongs together (order items, shipping address, etc.)
- Relatively stable relationship that doesn't grow unbounded
- Small to medium size (under 250 KB combined)
- Low likelihood of concurrent edits while offline

```dart
// ✅ GOOD: Embedded data retrieved together (single query)
{
  "_id": "order_123",
  "customerId": "cust_456",
  "shippingAddress": {  // Retrieved with order, no extra query
    "street": "123 Main St",
    "city": "Springfield",
    "zip": "12345"
  },
  "items": [  // Order items retrieved with order
    {"productId": "prod_1", "quantity": 2, "price": 10.00},
    {"productId": "prod_2", "quantity": 1, "price": 25.00}
  ],
  "total": 45.00
}
```

**When to Use Flat Models (foreign keys):**
- **Data accessed independently** (items rarely need parent data)
- Data that grows unbounded over time (can exceed document size limits)
- Frequent concurrent modifications from multiple peers
- **Independent data sets that sync separately** (parallel sync efficiency)

```dart
// ✅ GOOD: Flat model when data is accessed independently
// products collection (accessed independently from orders)
{
  "_id": "prod_789",
  "name": "Widget",
  "price": 19.99,
  "inventory": 100
}

// orders collection (only references product ID)
{
  "_id": "order_123",
  "customerId": "cust_456",
  "items": [
    {"productId": "prod_789", "quantity": 2}  // Foreign key reference (⚠️ array: see [Array Limitations](#array-limitations))
  ],
  "total": 39.98
}

// ⚠️ WARNING: Sequential queries required (no JOIN support):
// 1. Query order → 2. Extract productId → 3. Query product by productId
```

**Performance Trade-offs:**
- **Embedded**:
  - ✅ **Much faster when data is retrieved together** (single query vs sequential queries)
  - ✅ Simpler data access (no manual joining)
  - ❌ Potential size limits if data grows unbounded
  - ❌ Concurrent edit conflicts if multiple peers modify same document
- **Flat (foreign keys)**:
  - ✅ Better for accessing isolated portions independently
  - ✅ Parallel sync efficiency for independent data sets
  - ✅ Concurrent updates without conflicts
  - ❌ **Significant performance overhead** when data needs to be retrieved together (sequential queries)
  - ❌ Manual joining required in application code

**Decision Guide:**
1. **Will this data always be retrieved together?** → Embed (avoids sequential query overhead)
2. **Will this data grow unbounded?** → Use flat (avoids document size limits)
3. **Are they truly independent data sets?** → Use flat (parallel sync benefits)
4. **High concurrent edits on same document?** → Use flat (reduces conflicts)

---

## Data Deletion Strategies

### The Deletion Challenge

**⚠️ CRITICAL: Deletion in distributed systems is complex**

In distributed databases like Ditto:
- Deletion is not instantaneous across all devices (no centralized enforcement at the moment of deletion)
- Devices may be offline when deletion occurs
- Deleted data may reappear from previously disconnected devices (zombie data problem)

### DELETE and Tombstones

**What are Tombstones:**
Tombstones are compressed deletion records containing only the document ID and deletion timestamp. They ensure all peers learn about deleted documents.

**How it works:**
- `DELETE` DQL statement marks documents as deleted and creates tombstones
- Tombstones propagate to other peers so they know the document was deleted
- Tombstones have TTL (Time To Live) - default 30 days on Cloud, configurable on Edge SDK
- Documents are eventually evicted after TTL expires
- **CRITICAL LIMITATION**: Tombstones are only shared with devices that have seen the document before deletion

**⚠️ CRITICAL: Tombstone Sharing Limitation**
If a device encounters a document for the first time AFTER its tombstone has been removed, that device will reintroduce the document to the system as if it's new data.

**TTL Configuration:**
- **Cloud**: Deleted documents persist for 30 days before permanent removal (fixed, not configurable)
- **Edge SDK** (configurable):
  - `TOMBSTONE_TTL_ENABLED`: Enable automatic tombstone cleanup (default: false)
  - `TOMBSTONE_TTL_HOURS`: Expiration threshold in hours (default: 168 hours = 7 days)
  - `DAYS_BETWEEN_REAPING`: Reaping frequency (default: 1 day)
- **Critical**: Never set Edge SDK TTL larger than Cloud Server TTL (30 days), or Edge devices may hold tombstones longer than Cloud expects

**Batch Deletion Performance:**
- For batch deletions of 50,000+ documents, use `LIMIT 30000` to avoid performance impact

**✅ DO:**
- Understand tombstone TTL implications
- Document your TTL strategy
- Ensure all devices connect within the TTL window
- Use `LIMIT` for large batch deletions (50,000+ documents)
- Consider data lifecycle in your design

```dart
// ✅ GOOD: Physical deletion with awareness of TTL
final expiryDate = DateTime.now()
    .subtract(const Duration(days: 30))
    .toIso8601String();
await ditto.store.execute(
  'DELETE FROM temporary_data WHERE createdAt < :expiryDate',
  arguments: {'expiryDate': expiryDate},
);

// ✅ GOOD: Batch deletion with LIMIT for performance
await ditto.store.execute(
  'DELETE FROM logs WHERE createdAt < :cutoffDate LIMIT 30000',
  arguments: {'cutoffDate': cutoffDate},
);

// Note: Tombstone TTL must exceed maximum expected offline duration
// Otherwise, data from offline devices may reappear as new documents
```

**❌ DON'T:**
- Use DELETE without understanding tombstone TTL implications
- Delete data that may sync from long-offline devices
- Delete 50,000+ documents at once without LIMIT
- Set Edge SDK TTL larger than Cloud TTL

**Risk**: If a device reconnects after tombstone TTL expires, its data will be treated as new inserts, causing "zombie data" to reappear.

### Logical Deletion

**How it works:**
- Add a deletion flag field to documents (commonly named `isDeleted`, `isArchived`, `deletedFlag`, etc.)
- Filter out deleted documents in queries using the flag
- Periodically evict old deleted documents locally with EVICT

**✅ DO:**
- Implement logical deletion for critical data
- Filter deleted documents consistently in queries and observers
- Periodically clean up with EVICT
- Choose a clear, consistent field name for your deletion flag (e.g., `isDeleted`, `isArchived`)

```dart
// ✅ GOOD: Logical deletion implementation
// Note: Using 'isDeleted' as an example - you can use any field name

// 1. Mark as deleted (not actual deletion)
final deletedAt = DateTime.now().toIso8601String();
await ditto.store.execute(
  'UPDATE orders SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :orderId',
  arguments: {'orderId': orderId, 'deletedAt': deletedAt},
);

// Alternative naming examples:
// 'UPDATE orders SET isArchived = true, archivedAt = :archivedAt ...'
// 'UPDATE orders SET deletedFlag = true, deletedTimestamp = :timestamp ...'

// 2. Filter in queries and observers (use your chosen field name consistently)
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE isDeleted != true AND status = :status',
  arguments: {'status': 'active'},
);
final activeOrders = result.items.map((item) => item.value).toList();

// 3. Subscribe to ALL documents (CRITICAL for multi-hop relay)
// ❌ WRONG PATTERN - DO NOT filter deletion flags in subscriptions:
// final subscription = ditto.sync.registerSubscription(
//   'SELECT * FROM orders WHERE isDeleted != true',  // DON'T filter in subscription!
// );
// Problem: Prevents relay of deleted documents to indirectly connected peers

// ✅ CORRECT: Subscribe without deletion flag filter
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders',  // No isDeleted filter - allows proper relay
);

// 4. Observer filters deleted items for UI display
// (but subscription above has no filter for proper relay)
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders WHERE isDeleted != true ORDER BY createdAt DESC',
  onChange: (result, signalNext) {
    updateUI(result.items);
    signalNext();
  },
);
```

**⚠️ CRITICAL**: Subscriptions must NOT filter deletion flags. Filtering breaks multi-hop relay—Device A (relay) won't store deleted docs, so Device B (destination) never receives deletions. Subscribe broadly, filter in observers only.

Periodically EVICT old deleted docs locally: `EVICT FROM orders WHERE isDeleted = true AND deletedAt < :oldDate`

**Trade-offs:**

| Aspect | Logical Deletion | DELETE (with Tombstones) |
|--------|-----------------|--------------------------|
| Safety | ✅ Safer (no zombie data) | ⚠️ Risky (tombstone TTL) |
| Code Complexity | ⚠️ Higher (filter everywhere) | ✅ Lower (automatic) |
| Performance | ⚠️ Slightly slower (larger dataset) | ✅ Faster (smaller dataset) |
| Readability | ⚠️ Requires discipline | ✅ More intuitive |

**Decision Matrix:**

| Criteria | Recommendation |
|----------|----------------|
| **Use Logical Deletion when:** | |
| - Data may sync from long-offline devices (>TTL window) | ✅ Logical Deletion |
| - Audit trail or data recovery is required | ✅ Logical Deletion |
| - Soft-delete/restore UX is needed | ✅ Logical Deletion |
| - Regulatory compliance requires deletion tracking | ✅ Logical Deletion |
| - Maximum device offline duration > tombstone TTL | ✅ Logical Deletion |
| **Use DELETE when:** | |
| - All devices sync regularly within tombstone TTL window (30 days Cloud, configurable Edge) | ✅ DELETE |
| - Permanent removal is guaranteed and intentional | ✅ DELETE |
| - Storage efficiency is critical (minimize dataset size) | ✅ DELETE |
| - Temporary/ephemeral data with short lifecycle | ✅ DELETE |
| - No data recovery or audit requirements | ✅ DELETE |

**Why**: Logical deletion prevents "zombie data" from reappearing but requires consistent filtering across all queries and observers. DELETE with tombstones is simpler but has TTL risks.

**See Also**:
- [Multi-Hop Relay Propagation](#multi-hop-relay-propagation) - Why subscription filtering breaks relay
- [Subscribe Broadly, Filter Narrowly](#subscribe-broadly-filter-narrowly) - Detailed subscription strategy for logical deletion

---

### The Husked Document Problem

**⚠️ CRITICAL: Concurrent DELETE and UPDATE Conflicts**

When DELETE and UPDATE operations occur concurrently on the same document, Ditto's CRDT merge behavior combines them field-by-field, resulting in "husked documents" - partially deleted documents with some fields set to null and others containing updated values.

**How it Happens:**
1. Device A executes DELETE (sets all fields to null)
2. Device B executes UPDATE concurrently (updates specific fields)
3. When devices reconnect, Ditto merges field-by-field
4. Result: Document with mix of null and updated fields

**Example Scenario:**

```dart
// Device A: DELETE car
await ditto.store.execute(
  'DELETE FROM cars WHERE _id = :id',
  arguments: {'id': 'abc123'},
);
// Internally: {_id: "abc123", color: null, make: null, model: null, year: null}

// Device B (offline): UPDATE car color
await ditto.store.execute(
  'UPDATE cars SET color = :color WHERE _id = :id',
  arguments: {'color': 'blue', 'id': 'abc123'},
);
// Result: {_id: "abc123", color: "blue"}

// After sync - Husked document:
// {_id: "abc123", color: "blue", make: null, model: null, year: null}
```

**Why This Happens:**
Ditto's CRDT performs field-level merging: DELETE sets each field to null, while UPDATE sets specific fields to new values. When merging, Ditto keeps the most recent operation for each individual field.

**Mitigation Strategies:**

**✅ DO:**
- Use logical deletion (soft-delete with `isDeleted` flag) to avoid husked documents
- Reserve DELETE for permanent system-wide removal via Cloud API
- Use EVICT for Edge SDK local data management (doesn't create tombstones)
- Coordinate operations to prevent simultaneous deletes/updates
- Filter husked documents in queries by checking for null required fields

```dart
// ✅ GOOD: Logical deletion prevents husked documents
await ditto.store.execute(
  'UPDATE cars SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id',
  arguments: {'deletedAt': DateTime.now().toIso8601String(), 'id': 'abc123'},
);

// ✅ GOOD: Filter out husked documents in queries
final result = await ditto.store.execute(
  'SELECT * FROM cars WHERE make IS NOT NULL AND model IS NOT NULL AND isDeleted != true',
);
```

**❌ DON'T:**
- Use DELETE for documents that may be updated concurrently
- Assume DELETE operations prevent all future updates
- Ignore null fields in query results without validation

**Why**: Husked documents can cause application errors when code expects complete document structures. Logical deletion avoids this problem entirely by preserving document integrity.

**Official Reference**: [Ditto Delete Documentation](https://docs.ditto.live/sdk/latest/crud/delete)

**See Also**:
- [CRDT Type Behaviors](#crdt-type-behaviors) - Understanding REGISTER conflict resolution
- [Array Limitations](#array-limitations) - Why arrays use last-write-wins
- [DQL Strict Mode](#dql-strict-mode-v411) - How strict mode affects MAP vs REGISTER behavior

---

## Collection Design Patterns

### Denormalization for Performance

**Context: No JOIN Support Makes Denormalization Critical**
Without JOIN operations, fetching related data from multiple collections requires sequential queries with manual joining in application code. This creates significant performance overhead. Denormalization (embedding and duplicating data) avoids this problem.

**✅ DO:**
- **Embed related data that needs to be queried together** (MOST IMPORTANT: avoids sequential queries)
- Duplicate frequently accessed data when it simplifies queries and avoids cross-collection lookups
- Design for read-heavy workloads (optimize for query performance)
- Separate truly independent data into different collections for parallel sync efficiency

```javascript
// ✅ GOOD: Denormalized order with embedded items
{
  "_id": "order_123",
  "customerId": "customer_456",
  "customerName": "Alice Johnson", // Duplicated for quick access
  "items": [
    {
      "productId": "prod_1",
      "productName": "Widget", // Duplicated
      "quantity": 2,
      "price": 10.00
    }
  ],
  "total": 20.00,
  "status": "pending",
  "createdAt": "2025-01-15T10:00:00Z"
}
// Single query returns complete order with customer name and item details
```

**Why Denormalization Is Critical:**
- **Avoids sequential query overhead**: Without JOIN, fetching order + customer + products would require 3+ sequential queries
- **Simpler application code**: No manual joining logic needed
- **Better user experience**: Faster data access, especially on mobile/offline devices
- **Trade-off**: Data duplication vs query performance (in distributed systems, denormalization is often the right choice)

**When to Separate Collections:**
Independent data sets that sync separately benefit from separate collections (parallel sync efficiency). For example:
- Products catalog (updated independently)
- User profiles (rarely accessed with orders)
- System configuration (separate lifecycle)

---

### Field-Level Updates

**⚠️ CRITICAL PERFORMANCE IMPACT**: Unnecessary UPDATE operations create sync deltas even when values haven't changed. Always check if values differ before executing UPDATE statements to avoid wasted network traffic across all peers.

**✅ DO:**
- Update specific fields rather than replacing documents
- **Check if values have actually changed before issuing UPDATE statements** (critical for performance)
- Preserve CRDT merge behavior
- Use UPDATE statements for targeted field changes

```dart
// ✅ GOOD: Field-level update
final completedAt = DateTime.now().toIso8601String();
await ditto.store.execute(
  'UPDATE orders SET status = :status, completedAt = :completedAt WHERE _id = :orderId',
  arguments: {'orderId': orderId, 'status': 'completed', 'completedAt': completedAt},
);
```

**❌ DON'T:**
- Replace entire documents unnecessarily using INSERT with conflict policy
- Update fields with the same value (Ditto treats this as a change and syncs it as a delta)

```dart
// ❌ BAD: Full document replacement
final orderResult = await ditto.store.execute(
  'SELECT * FROM orders WHERE _id = :orderId',
  arguments: {'orderId': orderId},
);
final order = orderResult.items.first.value;

await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE',
  arguments: {
    'order': {
      ...order,
      'status': 'completed',
      'completedAt': DateTime.now().toIso8601String(),
    },
  },
);
// Ditto treats ALL fields as updated (CRDT counter increments),
// causing unnecessary sync traffic even for unchanged field values
```

```dart
// ❌ BAD: Updating with the same value creates unnecessary delta
final currentStatus = 'pending';
await ditto.store.execute(
  'UPDATE orders SET status = :status WHERE _id = :orderId',
  arguments: {'orderId': orderId, 'status': 'pending'}, // Same value!
);
// Even though the value hasn't changed, Ditto treats this as an update
// and syncs it as a delta to other peers (unnecessary network traffic)

// ✅ GOOD: Check before updating to avoid unnecessary deltas
final orderResult = await ditto.store.execute(
  'SELECT status FROM orders WHERE _id = :orderId',
  arguments: {'orderId': orderId},
);
final currentStatus = orderResult.items.first.value['status'];
final newStatus = 'completed';

if (currentStatus != newStatus) {
  await ditto.store.execute(
    'UPDATE orders SET status = :status WHERE _id = :orderId',
    arguments: {'orderId': orderId, 'status': newStatus},
  );
} // Only update if value actually changed
```

**Why**: Field-level UPDATE statements only sync changed fields. Full document replacement treats ALL fields as updated (even unchanged ones) due to CRDT counter increments, causing unnecessary network traffic and sync overhead across devices. **⚠️ CRITICAL**: Even updating a field with the same value is treated as a delta and synced to other peers—always check if values have changed before issuing UPDATE statements to avoid unnecessary sync traffic.

---

### DO UPDATE_LOCAL_DIFF for Efficient Upserts (SDK 4.12+)

**⚠️ RECOMMENDED**: Use `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` instead of `DO UPDATE` to automatically avoid syncing unchanged field values.

**What it does:**
- Compares the incoming document with the existing document
- Only updates fields whose values actually differ
- Prevents unnecessary replication of unchanged values
- More efficient than `DO UPDATE` when you want to avoid unnecessary deltas

**✅ DO:**
- Use `DO UPDATE_LOCAL_DIFF` for upsert operations where some fields may not have changed
- Prefer this over manual value checking when upserting entire documents

```dart
// ✅ GOOD: DO UPDATE_LOCAL_DIFF only syncs changed fields (SDK 4.12+)
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
  arguments: {
    'order': {
      '_id': 'order_123',
      'status': 'completed',        // Changed
      'customerId': 'customer_456', // Unchanged - won't sync
      'items': [...],               // Unchanged - won't sync
      'completedAt': DateTime.now().toIso8601String(), // Changed
    },
  },
);
// Only 'status' and 'completedAt' fields sync as deltas
// 'customerId' and 'items' are not synced (no unnecessary deltas)
```

**❌ DON'T:**
- Use `DO UPDATE` when you have many unchanged fields

```dart
// ❌ BAD: DO UPDATE syncs ALL fields, even unchanged ones
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE',
  arguments: {
    'order': {
      '_id': 'order_123',
      'status': 'completed',        // Changed
      'customerId': 'customer_456', // Unchanged - but still synced!
      'items': [...],               // Unchanged - but still synced!
      'completedAt': DateTime.now().toIso8601String(), // Changed
    },
  },
);
// ALL fields treated as updated and synced (unnecessary network traffic)
```

**Conflict Resolution Options:**

| Option | Behavior |
|--------|----------|
| `DO UPDATE` | Updates all fields, syncs all fields as deltas |
| `DO UPDATE_LOCAL_DIFF` (SDK 4.12+) | Only updates and syncs fields that differ from existing document |
| `DO NOTHING` | Ignores conflict, keeps existing document |
| `FAIL` | Throws error on conflict (default) |

**Why**: `DO UPDATE_LOCAL_DIFF` automatically handles the "same value update" problem by comparing values before creating deltas. This is more efficient than manually checking each field and prevents unnecessary sync traffic.

---

### INITIAL Documents for Default Data

**⚠️ CRITICAL: Use INITIAL for Device-Local Templates and Seed Data**

The `INITIAL DOCUMENTS` keyword in INSERT statements creates documents that are treated as "default data from the beginning of time" across all peers, preventing unnecessary synchronization of device-local templates.

**When to Use INITIAL:**
- Device-local templates (e.g., form templates, category lists, default settings)
- Seed data that every peer should initialize independently
- Data that should exist from the start but never sync between devices

**How It Works:**
- Documents inserted with INITIAL do nothing if the `_id` already exists locally
- All peers view INITIAL documents as the same INSERT operation
- Prevents sync conflicts and unnecessary network traffic for local defaults
- Cannot be overridden by ON ID CONFLICT policy

**✅ DO:**
- Use INITIAL for device-local templates that don't need synchronization

```dart
// ✅ GOOD: Insert default templates as INITIAL (won't sync unnecessarily)
final defaultCategories = [
  {'_id': 'cat_food', 'name': 'Food', 'icon': 'food'},
  {'_id': 'cat_drink', 'name': 'Drinks', 'icon': 'drink'},
  {'_id': 'cat_dessert', 'name': 'Desserts', 'icon': 'dessert'},
];

await ditto.store.execute(
  'INSERT INTO categories INITIAL DOCUMENTS (:categories)',
  arguments: {'categories': defaultCategories},
);

// Each device initializes these categories independently
// If a device already has 'cat_food', the INITIAL insert does nothing
// No sync traffic generated for these default templates
```

**❌ DON'T:**
- Use regular INSERT for device-local templates (causes unnecessary sync)

```dart
// ❌ BAD: Regular INSERT for templates (causes sync traffic)
await ditto.store.execute(
  'INSERT INTO categories DOCUMENTS (:categories)',
  arguments: {'categories': defaultCategories},
);
// Each device's INSERT operation syncs to other peers
// Generates unnecessary network traffic for local templates
```

**Use Cases:**

1. **Form Templates**: Device-local form structures that don't need synchronization
2. **Default Settings**: Initial configuration that every device should have
3. **Category Lists**: Predefined categories for local organization
4. **UI Presets**: Default UI configurations per device

**Why**: INITIAL documents prevent unnecessary synchronization of device-local data, reducing network traffic and avoiding sync conflicts for data that should exist independently on each device.

**Official Reference**: [DQL INSERT Documentation](https://docs.ditto.live/dql/insert)

---

### Counter Patterns (PN_INCREMENT and COUNTER Type)

**SDK Version Awareness:**
- **Ditto <4.14.0**: Use `PN_INCREMENT BY` operator (legacy PN_COUNTER CRDT)
- **Ditto 4.14.0+**: Use `COUNTER` type (recommended for new implementations)
- Migration between CRDT types requires careful planning (contact support)

**✅ DO:**
- Use counter increment operations for distributed counters
- Design for merge-friendly updates with PN_INCREMENT (all versions) or COUNTER type (4.14.0+)

```dart
// ✅ GOOD: Increment counter using PN_INCREMENT operator (all versions)
await ditto.store.execute(
  'UPDATE products APPLY viewCount PN_INCREMENT BY 1.0 WHERE _id = :productId',
  arguments: {'productId': productId},
);

// ✅ GOOD: COUNTER type with explicit declaration (Ditto 4.14.0+)
// Increment operation
await ditto.store.execute(
  '''UPDATE COLLECTION products (viewCount COUNTER)
     APPLY viewCount INCREMENT BY 1
     WHERE _id = :productId''',
  arguments: {'productId': productId},
);

// Set counter to specific value
await ditto.store.execute(
  '''UPDATE COLLECTION products (viewCount COUNTER)
     APPLY viewCount RESTART WITH 100
     WHERE _id = :productId''',
  arguments: {'productId': productId},
);

// Reset counter to zero
await ditto.store.execute(
  '''UPDATE COLLECTION products (viewCount COUNTER)
     APPLY viewCount RESTART
     WHERE _id = :productId''',
  arguments: {'productId': productId},
);
```

**Migration from PN_INCREMENT to COUNTER:**
- `PN_INCREMENT BY` → `INCREMENT BY` (semantically identical)
- COUNTER adds `RESTART WITH` and `RESTART` operations for explicit value setting
- PN_COUNTER remains valid for backward compatibility
- For existing apps using PN_INCREMENT, contact support before migrating CRDT types

**❌ DON'T:**
- Use SET operations for counters that may be updated concurrently

```dart
// ❌ BAD: Set counter (conflicts on concurrent updates)
// This anti-pattern applies to both PN_INCREMENT and COUNTER approaches
final productResult = await ditto.store.execute(
  'SELECT * FROM products WHERE _id = :productId',
  arguments: {'productId': productId},
);
final product = productResult.items.first.value;

await ditto.store.execute(
  'UPDATE products SET viewCount = :newCount WHERE _id = :productId',
  arguments: {
    'productId': productId,
    'newCount': (product['viewCount'] ?? 0) + 1, // Lost updates from other devices!
  },
);
```

**Why**: Counter increment operations (PN_INCREMENT and COUNTER type INCREMENT BY) merge correctly across concurrent updates; SET operations can cause lost updates when devices are disconnected. Use RESTART WITH (COUNTER type only) for controlled value setting with last-write-wins semantics.

---

### COUNTER Type Use Cases (Ditto 4.14.0+)

The new COUNTER type is ideal for scenarios requiring both distributed counting and periodic resets:

**1. Inventory Management with Recalibration:**

```dart
// Adjust inventory count as sales occur
await ditto.store.execute(
  '''UPDATE COLLECTION products (stock_count COUNTER)
     APPLY stock_count INCREMENT BY -1
     WHERE _id = :productId''',
  arguments: {'productId': productId},
);

// Recalibrate inventory after physical count
await ditto.store.execute(
  '''UPDATE COLLECTION products (stock_count COUNTER)
     APPLY stock_count RESTART WITH :physicalCount
     WHERE _id = :productId''',
  arguments: {'productId': productId, 'physicalCount': 47},
);
```

**Why Use COUNTER**: Physical inventory counts require setting exact values (RESTART WITH), while daily sales use distributed increments (INCREMENT BY). COUNTER type supports both operations.

**2. Like/Vote Counts with Administrative Reset:**

```dart
// Increment likes
await ditto.store.execute(
  '''UPDATE COLLECTION posts (likes COUNTER)
     APPLY likes INCREMENT BY 1
     WHERE _id = :postId''',
  arguments: {'postId': postId},
);

// Admin resets likes due to policy violation
await ditto.store.execute(
  '''UPDATE COLLECTION posts (likes COUNTER)
     APPLY likes RESTART
     WHERE _id = :postId''',
  arguments: {'postId': postId},
);
```

**Why Use COUNTER**: User-generated like counts need distributed increments, but administrative actions (policy enforcement, abuse mitigation) require controlled resets (RESTART).

**3. Session Metrics with Initialization:**

```dart
// Initialize session counter to baseline
await ditto.store.execute(
  '''UPDATE COLLECTION sessions (request_count COUNTER)
     APPLY request_count RESTART WITH 0
     WHERE _id = :sessionId''',
  arguments: {'sessionId': sessionId},
);

// Track requests
await ditto.store.execute(
  '''UPDATE COLLECTION sessions (request_count COUNTER)
     APPLY request_count INCREMENT BY 1
     WHERE _id = :sessionId''',
  arguments: {'sessionId': sessionId},
);
```

**Why Use COUNTER**: Session initialization requires explicit zero value (RESTART WITH 0), followed by distributed request counting (INCREMENT BY).

**Why Use COUNTER Over PN_INCREMENT:**
- Explicit `RESTART WITH` provides controlled reset capability
- Type declaration (`COUNTER`) clarifies intent in collection schema
- Last-write-wins semantics for `RESTART` operations (not increment conflicts)
- Better semantic match for counters that need periodic resets

---

### Event History and Audit Logs

**✅ DO:**
- Use separate documents (INSERT) for event history and audit logs
- Avoid arrays for append-only logs in concurrent environments

```dart
// ✅ GOOD: Insert event as separate document (recommended for audit logs)
await ditto.store.execute(
  'INSERT INTO order_history DOCUMENTS (:historyDoc)',
  arguments: {
    'historyDoc': {
      '_id': '${orderId}_${DateTime.now().millisecondsSinceEpoch}',
      'orderId': orderId,
      'status': 'shipped',
      'timestamp': DateTime.now().toIso8601String(),
      'userId': currentUserId,
    },
  },
);

// Query history for an order
final historyResult = await ditto.store.execute(
  'SELECT * FROM order_history WHERE orderId = :orderId ORDER BY timestamp ASC',
  arguments: {'orderId': orderId},
);
```

**❌ DON'T:**
- Use arrays for append-only logs that may be updated concurrently

```dart
// ❌ BAD: Arrays are REGISTERS (last-write-wins) - see [Array Limitations](#array-limitations)
await ditto.store.execute(
  'UPDATE orders SET statusHistory = statusHistory || [:entry] WHERE _id = :orderId',
  arguments: {'orderId': orderId, 'entry': historyEntry},
);
// If two devices append concurrently, one append will be lost
```

**Why**: Arrays use last-write-wins semantics. Separate INSERT documents ensure all events are preserved.

---

### Two-Collection Pattern for Real-Time + Historical Data

When you need both **real-time current state** (low latency) and **historical event data** (complete audit trail), use two separate collections with different purposes.

**Use Case**: Location tracking, sensor readings, order status updates, any scenario where you need both "latest value" and "full history"

**Why Separate Collections**: These are **independent data sets** that don't need to be queried together. Separate collections allow parallel synchronization—devices can sync current state and historical events simultaneously, improving overall sync efficiency. This is in contrast to splitting related data (like orders and order items), which would require serial queries and hurt performance.

#### Pattern: Dual Write

Write each event to two collections simultaneously:

1. **Events collection**: Append-only, grows over time, complete history
2. **Current state collection**: One document per entity, CRDT-managed, bounded size

```dart
// ✅ GOOD: Dual write pattern for location tracking
Future<void> onPositionUpdate(String aircraftId, Position position) async {
  final timestamp = DateTime.now().toIso8601String();
  final eventId = '${aircraftId}_${DateTime.now().millisecondsSinceEpoch}';

  // Write 1: Historical event (append-only)
  await ditto.store.execute(
    'INSERT INTO position_events DOCUMENTS (:event)',
    arguments: {
      'event': {
        '_id': eventId,
        'aircraft_id': aircraftId,
        'timestamp': timestamp,
        'position': {'lat': position.lat, 'lon': position.lon},
        'sensor_id': 'satellite_03',
      },
    },
  );

  // Write 2: Current position (CRDT last-write-wins)
  await ditto.store.execute(
    'INSERT INTO aircraft DOCUMENTS (:aircraft) ON ID CONFLICT DO UPDATE',
    arguments: {
      'aircraft': {
        '_id': aircraftId,
        'position': {'lat': position.lat, 'lon': position.lon},
        'last_seen': timestamp,
        'last_sensor_id': 'satellite_03',
      },
    },
  );
}
```

#### Atomic Dual Writes with Transactions

Use transactions to ensure both writes sync together atomically:

```dart
// ✅ GOOD: Atomic dual write with transaction
await ditto.store.transaction((tx) async {
  // Both operations commit together
  await tx.execute(
    'INSERT INTO position_events DOCUMENTS (:event)',
    arguments: {'event': eventData},
  );

  await tx.execute(
    'INSERT INTO aircraft DOCUMENTS (:aircraft) ON ID CONFLICT DO UPDATE',
    arguments: {'aircraft': currentStateData},
  );

  return; // Automatic commit
});
```

**⚠️ CRITICAL Trade-off**: Transactions vs. Differentiated Subscriptions

| Approach                         | Consistency                    | Bandwidth Optimization              |
|----------------------------------|--------------------------------|-------------------------------------|
| **With transactions**            | Atomic updates, no partial state | All devices must subscribe to both collections |
| **Without transactions**         | Updates may arrive separately  | Devices can subscribe to only what they need |

**Choose based on your priorities:**
- **Atomic consistency**: Use transactions, subscribe to both collections on all devices
- **Bandwidth optimization**: Skip transactions, allow differentiated subscriptions

#### Consumer Patterns

**Real-time display** (observe current state):

```dart
// ✅ GOOD: Observe bounded current state collection
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM aircraft',
  onChange: (result, signalNext) {
    // Result set size bounded by number of aircraft (not update count)
    updateMapDisplay(result.items);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      signalNext();
    });
  },
);
```

**Historical analysis** (query events):

```dart
// ✅ GOOD: One-time query for trajectory
final result = await ditto.store.execute(
  'SELECT * FROM position_events WHERE aircraft_id = :id AND timestamp >= :start ORDER BY timestamp ASC',
  arguments: {'id': aircraftId, 'start': startTime},
);

final trajectory = result.items.map((item) => item.value).toList();
renderFlightPath(trajectory);
```

#### Differentiated Sync Subscriptions

Different devices can subscribe to different data based on their needs:

```dart
// Real-time dashboard (small, fast)
await ditto.sync.registerSubscription(
  'SELECT * FROM aircraft',
);

// Historical analysis tool (specific aircraft only)
await ditto.sync.registerSubscription(
  'SELECT * FROM position_events WHERE aircraft_id IN (:tracked)',
  arguments: {'tracked': ['N12345', 'N67890']},
);
```

**⚠️ Important**: If using transactions for atomic writes, both collections must be subscribed together—devices subscribing only to `aircraft` won't receive updates until they also subscribe to `position_events`.

#### Benefits

| Benefit                          | Explanation                                                             |
|----------------------------------|-------------------------------------------------------------------------|
| **Predictable resource usage**   | Current state collection has bounded size (one doc per entity)          |
| **Automatic conflict resolution**| CRDT handles concurrent updates to current state (no app logic needed)  |
| **Efficient real-time queries**  | No `ORDER BY` or `LIMIT` needed for current state                       |
| **Complete audit trail**         | Events collection preserves all historical data                         |
| **Differentiated sync**          | Devices sync only what they need (if not using transactions)            |

#### Trade-offs vs. Single Collection

| Single Collection (Events Only)  | Two Collections (Dual Write)                                           |
|----------------------------------|-------------------------------------------------------------------------|
| Simpler schema                   | Slightly more complex (two collections)                                 |
| Storage efficient (no duplication)| Duplicates "current state" in both collections                         |
| Queries need `ORDER BY LIMIT 1`  | Current state directly queryable                                        |
| Working set grows over time      | Current state collection has fixed size                                 |
| App handles conflict resolution  | CRDT handles conflicts automatically                                    |

**When to use this pattern:**
- Real-time "current value" is a primary use case
- Multiple sources may update the same entity concurrently
- You need predictable, bounded resource usage
- Different consumers have different latency requirements

**Two-Collection Pattern Architecture:**

**Architecture**: Dual write to events collection (append-only history) and current state collection (CRDT-managed, bounded). Real-time consumers observe current state only. Historical analysis queries events only. Separate collections enable parallel sync and differentiated subscriptions.

**Official Reference**: [Real-Time Location Tracking](https://docs.ditto.live/guides/real-time-location-tracking)

---

## Subscription Patterns

### How Ditto Syncs Data

**Event-Driven Synchronization:**
Ditto uses an event-driven model (not polling). Devices express data needs through subscription queries, and Ditto automatically syncs matching documents across the mesh network.

**Subscription Lifecycle:**
1. Device creates subscription with DQL query
2. Ditto broadcasts subscription query to all connected peers
3. Peers with matching data sync it to the subscribing device
4. Continuous updates: When data changes on any peer, incremental changes sync automatically

**Delta Sync Optimization:**
Ditto transmits only field-level changes (not entire documents), minimizing bandwidth usage. **⚠️ Important**: Even updating a field with the same value is treated as a change and synced as a delta—avoid unnecessary updates to minimize sync traffic. This optimization is especially important for:
- Battery-constrained mobile devices
- Low-bandwidth connections (Bluetooth LE)
- Frequent small updates

**Version Vectors:**
Each document has a version vector tracking its state across peers. When a change occurs, the document version increments. Peers use version vectors to determine if incoming changes are new or already seen.

### Understanding Subscriptions and Queries

**How Subscriptions Work:**
Subscriptions are replication queries that tell Ditto which data to request and sync from connected peers. When you query without an active subscription, `execute()` returns only locally cached data—it won't fetch data from other peers.

**Key Principle: Appropriate Subscription Lifecycle**
Subscriptions should be maintained for as long as you need the data. **Avoid frequent, unnecessary start/stop cycles**—this creates mesh network overhead. Think of subscriptions as declaring "I need this data" rather than "fetch this data once."

**When to Cancel Subscriptions:**
- **When the feature is disposed**: Cancel when a screen/service is permanently closed to notify other peers they don't need to send data anymore
- **Before EVICT operations**: Prevent resync loops where evicted data gets re-synced
- **When subscription scope changes**: Cancel and recreate with updated query parameters
- **App termination**: Ensure proper cleanup to notify peers

**When NOT to Cancel:**
- **Between individual queries**: Don't cancel/recreate for each data access
- **Temporary UI state changes**: Keep subscriptions alive across navigation or minor UI updates
- **Short time periods**: Avoid rapid on/off toggling

**Recommended Pattern: Long-Lived Subscription + Local Store Observer**

```dart
// ✅ GOOD: Long-lived subscription with observer
class OrdersService {
  late final Subscription _subscription;
  late final StoreObserver _observer;

  void initialize() {
    // Start subscription - keep it alive for the lifetime of the feature
    _subscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'active'},
    );

    // Observer receives initial local data + updates as remote data syncs
    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status',
      onChange: (result, signalNext) {
        final orders = result.items.map((item) => item.value).toList();
        updateOrdersUI(orders);  // Update UI with initial + synced data

        WidgetsBinding.instance.addPostFrameCallback((_) {
          signalNext();
        });
      },
      arguments: {'status': 'active'},
    );
  }

  void dispose() {
    // Cancel only when the feature is completely done (e.g., screen disposed)
    _observer.cancel();
    _subscription.cancel();
  }
}
```

**Alternative: One-Time Query (Local Data Only)**

If you only need a snapshot of local data without remote sync:

```dart
// ✅ GOOD: One-time query for local data only
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);
final orders = result.items.map((item) => item.value).toList();
// Returns only local data - no remote sync
```

**❌ ANTI-PATTERNS:**

```dart
// ❌ ANTI-PATTERN: Frequent start/stop of subscriptions
// This creates unnecessary mesh network overhead
void loadOrders() {
  final subscription = ditto.sync.registerSubscription('SELECT * FROM orders');
  final result = await ditto.store.execute('SELECT * FROM orders');
  subscription.cancel();  // DON'T DO THIS on every request!
}

// ❌ ANTI-PATTERN: Request/response thinking (treating Ditto like HTTP)
Future<List<Order>> fetchOrders() async {
  final sub = ditto.sync.registerSubscription('SELECT * FROM orders');
  await Future.delayed(Duration(seconds: 2));  // Waiting is inefficient!
  final result = await ditto.store.execute('SELECT * FROM orders');
  sub.cancel();  // Canceling immediately defeats mesh sync benefits
  return result.items.map((item) => item.value).toList();
}

// ❌ BAD: Subscription leak (never cancelled)
final subscription = ditto.sync.registerSubscription('SELECT * FROM orders');
// Never cancelled when feature is disposed - memory leak!
```

**Key Points:**
- **Maintain subscriptions appropriately**: Start when a feature needs data, cancel when permanently done or before EVICT
- **Use observers for real-time updates**: Observers receive initial local data and notifications as remote data syncs in
- **Avoid unnecessary start/stop cycles**: Frequent toggling creates mesh network overhead—cancel only when needed
- **One-time queries return local data only**: Without a subscription, you only see cached local data
- **Don't think request/response**: Ditto is peer-to-peer mesh, not a client-server API
- **Proper cleanup matters**: Canceling subscriptions notifies other peers they can stop sending data

**Subscription Lifecycle State Diagram:**

**Subscription Lifecycle**: Inactive → Active (registerSubscription broadcasts query) → SyncingInitial (peers respond) → SyncingContinuous (incremental deltas) → Paused (connection lost, auto-resumes) → Cancelled (subscription.cancel(), resources released). Subscriptions are long-lived. Observers fire on local store updates. Always cancel when disposed.

---

### Observe for Real-Time Updates

**What is an Observer?**
An observer monitors database changes matching a query over time, delivering updates as data changes locally or syncs from other peers.

**When to Use Observers vs One-Time Reads:**

| Scenario | Recommended Approach | Method | Notes |
|----------|---------------------|--------|-------|
| **One-time local data read** (check if data exists locally, read cached config) | ✅ One-time read | `store.execute("SELECT ...")` | Returns local data only—no remote sync |
| **Real-time UI updates** (display live order status, sync data across devices, show live inventory) | ✅ Observer + Subscription | `registerObserverWithSignalNext` | Observer gets initial local data + synced updates |
| **High-frequency updates** (sensor data, real-time tracking, streaming data) | ✅ Observer with backpressure + Subscription | `registerObserverWithSignalNext` | Use `signalNext()` for flow control |
| **Infrequent manual updates** (user profile changes, settings updates) | ✅ Observer + Subscription | `registerObserverWithSignalNext` | Observer notified on changes |

```dart
// ✅ GOOD: One-time read for LOCAL data only (no remote sync)
final result = await ditto.store.execute(
  'SELECT * FROM products WHERE category = :category',
  arguments: {'category': 'electronics'},
);
final products = result.items.map((item) => item.value).toList();
displayProducts(products);
// Note: Without an active subscription, this returns only locally cached data

// ✅ GOOD: Observer + Subscription for real-time UI updates with remote sync
// Start subscription first (or alongside observer)
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);

// Observer receives initial local data + updates as remote data syncs
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders WHERE status = :status',
  onChange: (result, signalNext) {
    final orders = result.items.map((item) => item.value).toList();
    updateOrdersUI(orders);  // UI reflects changes in real-time

    WidgetsBinding.instance.addPostFrameCallback((_) {
      signalNext();  // Ready for next update
    });
  },
  arguments: {'status': 'active'},
);

// Cancel both when feature is disposed
// observer.cancel();
// subscription.cancel();
```

**Understanding Backpressure:**
Callbacks fire every time matching data changes in the local store. In high-frequency scenarios—such as IoT sensors or real-time tracking that generate multiple updates per second—callbacks can accumulate faster than your application processes them. This leads to memory exhaustion and potential crashes.

### Observer Methods

**Legacy observeLocal migration**: See [Replacing observeLocal](#replacing-legacy-observelocal-with-store-observers-sdk-412) (applicable to non-Flutter SDKs)

#### registerObserverWithSignalNext (RECOMMENDED - Not Available in Flutter SDK v4.x)

**⚠️ Flutter SDK Limitation:**
This method is NOT available in Flutter SDK v4.14.0 and earlier. Flutter developers must use `registerObserver` (without `signalNext`) until Flutter SDK v5.0. See Flutter-specific pattern below.

**Prefer `registerObserverWithSignalNext`** as the recommended pattern for observer scenarios on non-Flutter SDKs - it provides better performance through predictable backpressure control and prevents memory issues regardless of update frequency.

**Use for:**
- All real-time UI updates (recommended for most use cases)
- High-frequency sensor data (multiple updates per second)
- UI render-cycle synchronization
- Async processing operations
- User profile changes and configuration updates
- Any scenario where performance and memory safety matter

**Why it's better:**
- **Better performance**: Explicit control prevents callback queue buildup
- **Memory safety**: Prevents crashes from uncontrolled callback accumulation
- **Predictable behavior**: You control when the next update arrives

**✅ DO:**
- Extract data from QueryResultItems immediately (lightweight operation)
- Keep callback processing lightweight to avoid blocking
- Offload heavy processing (complex computations, network calls, file I/O) to async operations outside the callback
- Use `signalNext()` to control backpressure explicitly
- Call `signalNext()` after your render cycle completes
- Use for most observer scenarios (default choice)

```dart
// ✅ GOOD: Observer with backpressure control
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM sensor_data WHERE deviceId = :deviceId',
  onChange: (result, signalNext) {
    final data = result.items.map((item) => item.value).toList();
    updateUI(data);

    // Call signalNext after render cycle completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      signalNext();
    });
  },
  arguments: {'deviceId': 'sensor_123'},
);

// Later: stop observing
observer.cancel();
```

**Flutter SDK v4.x Alternative** (No signalNext support):

```dart
// ⚠️ Flutter SDK v4.14.0: No signalNext parameter
final observer = ditto.store.registerObserver(
  'SELECT * FROM sensor_data WHERE deviceId = :deviceId',
  onChange: (result) {
    final data = result.items.map((item) => item.value).toList();
    updateUI(data);  // Keep callbacks lightweight
  },
  arguments: {'deviceId': 'sensor_123'},
);
// Note: Flutter SDK v5.0 will add signalNext support
```

**⚠️ Flutter SDK v4.x**: No backpressure control. Callbacks fire for every change. Keep processing lightweight.

**Flutter SDK Stream-Based Pattern** (Recommended for Flutter):

The Flutter SDK provides a **Stream-based API** via `StoreObserver.changes`, which is more idiomatic for Dart/Flutter applications:

```dart
// ✅ GOOD: Stream-based observer (Flutter SDK convenience API)
final observer = ditto.store.registerObserver(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);

// Listen to changes using Stream API
final subscription = observer.changes.listen((result) {
  final orders = result.items.map((item) => item.value).toList();
  updateUI(orders);
});

// Cleanup
subscription.cancel();
observer.cancel(); // Also closes the stream
```

**Why Use Stream-Based Pattern:**
- ✅ Dart-idiomatic: Works seamlessly with async/await and StreamBuilder
- ✅ Composable: Can use Stream operators (map, where, debounce, etc.)
- ✅ Integrates with Flutter: Works directly with StreamBuilder widget
- ✅ Cleaner lifecycle: Stream closes automatically when observer is cancelled

**Example with StreamBuilder** (Flutter UI Integration):

```dart
class OrderListWidget extends StatefulWidget {
  @override
  State<OrderListWidget> createState() => _OrderListWidgetState();
}

class _OrderListWidgetState extends State<OrderListWidget> {
  late final Ditto ditto;
  late final StoreObserver observer;

  @override
  void initState() {
    super.initState();
    ditto = context.read<Ditto>(); // Or get from your DI solution
    observer = ditto.store.registerObserver(
      'SELECT * FROM orders ORDER BY createdAt DESC',
      arguments: {},
    );
  }

  @override
  void dispose() {
    observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QueryResult>(
      stream: observer.changes,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const CircularProgressIndicator();
        }

        final orders = snapshot.data!.items
            .map((item) => item.value)
            .toList();

        return ListView.builder(
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index];
            return ListTile(
              title: Text(order['customerName'] as String),
              subtitle: Text('Total: \$${order['total']}'),
            );
          },
        );
      },
    );
  }
}
```

**Callback-Based Pattern** (Alternative):

For simple scenarios, the callback-based API remains valid:

```dart
final observer = ditto.store.registerObserver(
  'SELECT * FROM orders WHERE status = :status',
  onChange: (result) {
    final orders = result.items.map((item) => item.value).toList();
    updateUI(orders);
  },
  arguments: {'status': 'active'},
);
```

**❌ DON'T: Heavy processing inside callback**
```dart
onChange: (result, signalNext) {
  for (final order in orders) {
    performExpensiveAnalysis(order); // BLOCKS!
  }
  signalNext();
}
```

**✅ DO: Offload heavy processing**
```dart
onChange: (result, signalNext) {
  final data = result.items.map((item) => item.value).toList();
  updateUI(data);
  _processDataAsync(data); // Non-blocking
  WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
}
```

#### registerObserver (Simple Data Processing Only)

**Use only for:**
- Very simple, synchronous data processing
- Scenarios where backpressure control is explicitly not needed

**⚠️ Limitations:**
- **Lower performance**: No backpressure control can lead to callback queue buildup
- **Memory risk**: Callbacks can accumulate faster than processing in many scenarios
- **Less predictable**: No control over update timing

```dart
// ⚠️ OK for very simple cases only
final observer = ditto.store.registerObserver(
  'SELECT * FROM simple_config',
  onChange: (result) {
    // Only use for trivial, synchronous processing
    final config = result.items.first.value;
    updateSimpleValue(config);
  },
);
```

**When in doubt**:
- **Non-Flutter SDKs**: Use `registerObserverWithSignalNext` (recommended)
- **Flutter SDK v4.x**: Use `registerObserver` (only option until v5.0)

### Observer Lifecycle Management

**✅ DO:**
- **Non-Flutter SDKs**: Prefer `registerObserverWithSignalNext` for all observers (better performance, recommended pattern)
- **Flutter SDK v4.x**: Use `registerObserver` (only option until v5.0)
- Maintain observers for the lifetime of the feature that needs real-time updates
- Cancel observers when the feature is disposed (e.g., screen closed, service stopped)
- Pair observers with subscriptions for remote data sync
- Access registered observers via `ditto.store.observers`
- **Non-Flutter SDKs**: Call `signalNext()` to control backpressure explicitly

**❌ DON'T:**
- **Non-Flutter SDKs**: Use `registerObserver` for most use cases (worse performance, use only for very simple data processing)
- Cancel and recreate observers frequently (avoid unnecessary churn)
- Perform heavy processing (complex computations, network calls, file I/O) inside observer callbacks
- Block the callback thread with synchronous heavy operations
- Leave observers running after feature disposal (causes memory leaks)

**When to Cancel Observers:**
- **Feature disposal**: When a screen/service is permanently closed
- **Component unmounting**: When a widget is disposed in Flutter
- **App termination**: During cleanup before app shutdown
- **Scope changes**: When the query needs to change (cancel old, create new)

**When NOT to Cancel:**
- **Temporary navigation**: Keep alive if returning to the same screen
- **Background state**: Don't cancel just because the app goes to background
- **Short intervals**: Avoid rapid start/stop cycles

**Why**: Observers enable real-time UI updates as data changes locally or syncs from other devices. Using `registerObserverWithSignalNext` provides better performance and memory safety. Heavy processing in callbacks blocks the observer thread, degrading performance—offload such work to async operations. Proper lifecycle management (similar to subscriptions) prevents memory leaks while maintaining efficient real-time updates.

---

### Replacing Legacy observeLocal with Store Observers (SDK 4.12+)

**⚠️ Non-Flutter SDKs Only** — Flutter SDK never had legacy observeLocal API

Legacy observeLocal provided automatic event diffs (insertions, deletions, updates, moves). DQL observers require manual diffing with DittoDiffer.

**Migration Pattern**:

```javascript
// ❌ Legacy API (DEPRECATED)
const liveQuery = ditto.store
  .collection('orders')
  .find("status == 'active'")
  .observeLocal((docs, event) => {
    if (event.isInitial) {
      console.log('Initial load');
    }
    console.log('Inserted:', event.insertions);
    console.log('Deleted:', event.deletions);
    console.log('Updated:', event.updates);
  });

// ✅ Current DQL API: Subscription + Observer + Differ
const subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE status = :status',
  { arguments: { status: 'active' } }
);

const differ = new DittoDiffer();
let previousItems = null;

const observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders WHERE status = :status',
  { arguments: { status: 'active' } },
  (result, signalNext) => {
    // Detect initial event
    const isInitial = (previousItems === null);
    if (isInitial) {
      console.log('Initial load');
    }

    // Compute changes using Differ
    const changes = differ.computeChanges(previousItems || [], result.items);
    console.log('Inserted:', changes.insertions);
    console.log('Deleted:', changes.deletions);
    console.log('Updated:', changes.updates);

    // Extract data for next callback
    previousItems = result.items.map(item => item.value);

    signalNext();
  }
);
```

**Key Migration Points**:

1. **Two-step pattern**: Use `registerSubscription()` for remote sync + `registerObserverWithSignalNext()` for local changes
2. **DittoDiffer**: Create differ instance and call `computeChanges(previousItems, currentItems)` to get insertions/deletions/updates
3. **Memory management**: Extract data immediately via `item.value` — don't retain QueryResultItems between callbacks

```javascript
// ❌ DON'T: Retain QueryResultItems (memory bloat)
let storedItems = null;
const observer = ditto.store.registerObserverWithSignalNext(query, (result, signalNext) => {
  storedItems = result.items; // BAD: holds references indefinitely
  signalNext();
});

// ✅ DO: Extract data immediately
let storedData = null;
const observer = ditto.store.registerObserverWithSignalNext(query, (result, signalNext) => {
  storedData = result.items.map(item => item.value); // GOOD: plain data
  signalNext();
});
```

4. **Initial event**: Check `previousItems === null` to detect first callback (no built-in `event.isInitial`)
5. **Backpressure**: Always call `signalNext()` after processing to receive next update

**Performance**: Differs have negligible overhead for <100 docs. For >1000 docs, consider debouncing or batch processing.

**See Also**:
- [Query Result Handling](#query-result-handling) for memory management details
- [Diffing Query Results](#diffing-query-results) for Differ usage patterns
- [Understanding Subscriptions and Queries](#understanding-subscriptions-and-queries) for subscription lifecycle

---

### Partial UI Updates (Avoid Full Screen Refreshes)

**The Problem:**
Observer callbacks trigger when data changes, but poorly designed UI updates can cause the entire screen or widget tree to rebuild unnecessarily. This leads to:
- **Performance degradation**: Rendering components that didn't change
- **Unnecessary CPU/GPU usage**: Battery drain on mobile devices
- **Visual glitches**: Flickering, scrolling resets, lost input focus
- **Poor user experience**: Sluggish UI, especially with frequent updates

**Common Anti-Pattern:**

```dart
// ❌ BAD: Full screen refresh on every data change
class OrderListScreen extends StatefulWidget {
  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  List<Map<String, dynamic>> orders = [];
  late DittoStoreObserver observer;

  @override
  void initState() {
    super.initState();
    observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) {
        setState(() {
          orders = result.items.map((item) => item.value).toList();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Entire screen rebuilds when ANY order changes!
    return Scaffold(
      appBar: AppBar(title: Text('Orders (${orders.length})')),
      body: ListView.builder(
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          return OrderCard(order: order);  // All cards rebuild!
        },
      ),
    );
  }
}
```

**Problem**: When a single order's status changes (e.g., "pending" → "shipped"), `setState()` causes:
1. Entire `OrderListScreen` widget rebuilds
2. `AppBar` rebuilds (even though title didn't change)
3. `ListView` rebuilds
4. **All** `OrderCard` widgets rebuild (even for unchanged orders)

---

#### Solution 1: State Management with Granular Observation (Recommended)

Use Riverpod providers to separate data management from UI, allowing selective widget rebuilds.

**✅ GOOD: Riverpod with granular observation**

```dart
// 1. Provider for Ditto store
final dittoProvider = Provider<Ditto>((ref) => throw UnimplementedError());

// 2. Provider for orders data with observer (Flutter SDK v4.x)
final ordersProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final ditto = ref.watch(dittoProvider);

  final observer = ditto.store.registerObserver(
    'SELECT * FROM orders ORDER BY createdAt DESC',
    arguments: {},
  );

  ref.onDispose(() {
    observer.cancel();
  });

  return observer.changes.map((result) {
    return result.items.map((item) => item.value).toList();
  });
});

// 3. Provider for single order (granular selection)
final orderProvider = Provider.family<Map<String, dynamic>?, String>((ref, orderId) {
  final ordersAsync = ref.watch(ordersProvider);
  return ordersAsync.when(
    data: (orders) => orders.firstWhereOrNull((o) => o['_id'] == orderId),
    loading: () => null,
    error: (_, __) => null,
  );
});

// 4. Screen widget (minimal rebuilds)
class OrderListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersProvider);

    return Scaffold(
      appBar: AppBar(
        title: ordersAsync.when(
          data: (orders) => Text('Orders (${orders.length})'),
          loading: () => Text('Orders'),
          error: (_, __) => Text('Orders (Error)'),
        ),
      ),
      body: ordersAsync.when(
        data: (orders) => ListView.builder(
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final orderId = orders[index]['_id'] as String;
            // Each card only rebuilds if ITS data changes
            return OrderCard(orderId: orderId);
          },
        ),
        loading: () => Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
    );
  }
}

// 5. Individual card widget (rebuilds only when its order changes)
class OrderCard extends ConsumerWidget {
  final String orderId;

  const OrderCard({required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only watches THIS order's data
    final order = ref.watch(orderProvider(orderId));

    if (order == null) return SizedBox.shrink();

    return Card(
      child: ListTile(
        title: Text('Order #${order['orderNumber']}'),
        subtitle: Text('Status: ${order['status']}'),
        trailing: Text('\$${order['total']}'),
      ),
    );
  }
}
```

**How This Works:**
1. `ordersProvider` manages observer lifecycle and provides data stream
2. `orderProvider.family` creates granular selectors for each order ID
3. When order `order_123` changes:
   - Only `OrderCard(orderId: 'order_123')` rebuilds
   - Other cards remain untouched
   - AppBar only rebuilds if order count changes

**Benefits:**
- **Minimal rebuilds**: Only affected widgets update
- **Automatic optimization**: Riverpod handles change detection
- **Clean separation**: Data management separate from UI
- **Testable**: Providers can be mocked in tests

---

#### Solution 2: ValueListenableBuilder for Simple Cases

For simpler scenarios without full state management, use `ValueNotifier` with `ValueListenableBuilder`.

**✅ GOOD: ValueNotifier for targeted updates**

```dart
class OrderListScreen extends StatefulWidget {
  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  final ordersNotifier = ValueNotifier<List<Map<String, dynamic>>>([]);
  late DittoStoreObserver observer;

  @override
  void initState() {
    super.initState();
    observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) {
        ordersNotifier.value = result.items.map((item) => item.value).toList();
        WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
      },
    );
  }

  @override
  void dispose() {
    observer.cancel();
    ordersNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: ordersNotifier,
          builder: (context, orders, child) {
            // Only AppBar title rebuilds when order count changes
            return Text('Orders (${orders.length})');
          },
        ),
      ),
      body: ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: ordersNotifier,
        builder: (context, orders, child) {
          // Only ListView rebuilds (not entire Scaffold)
          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return OrderCard(order: order);
            },
          );
        },
      ),
    );
  }
}
```

**Benefits:**
- **Simpler than full state management**: No external dependencies
- **Scoped rebuilds**: Only `ValueListenableBuilder` subtrees rebuild
- **Built-in to Flutter**: No additional packages required

**Limitations:**
- Still rebuilds entire list when any order changes
- Doesn't provide granular per-item optimization
- Less suitable for complex apps with many data dependencies

---

#### Solution 3: Using Ditto's DittoDiffer (Advanced)

For maximum optimization, use `DittoDiffer` to detect exactly which documents changed and update only those UI elements.

**✅ GOOD: DittoDiffer for surgical updates**

```dart
class _OrderListScreenState extends State<OrderListScreen> {
  List<Map<String, dynamic>> orders = [];
  final differ = DittoDiffer();
  late DittoStoreObserver observer;

  @override
  void initState() {
    super.initState();
    observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) {
        // Calculate which documents changed
        final changeSummary = differ.computeChanges(result.items);

        if (changeSummary.hasChanges) {
          setState(() {
            orders = result.items.map((item) => item.value).toList();
          });

          // Optional: Log which orders changed for debugging
          print('Inserted: ${changeSummary.insertions.length}');
          print('Updated: ${changeSummary.updates.length}');
          print('Deleted: ${changeSummary.deletions.length}');
        }

        WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          // Use unique key for efficient list updates
          return OrderCard(
            key: ValueKey(order['_id']),
            order: order,
          );
        },
      ),
    );
  }
}
```

**How This Works:**
1. `DittoDiffer` tracks document versions between callbacks
2. `computeChanges()` identifies insertions, updates, deletions
3. Flutter's reconciliation uses `ValueKey` to update only changed items
4. Unchanged list items reuse existing widget instances

**Benefits:**
- **Efficient list updates**: Flutter knows exactly which items changed
- **Minimal rebuilds**: Only new/updated/deleted items rebuild
- **Built into Ditto**: No external dependencies

**When to Use:**
- Large lists (hundreds or thousands of items)
- High-frequency updates
- Performance-critical applications

---

#### Performance Comparison

**Test Scenario**: 1000 orders displayed, single order's status changes

| Approach                          | Widgets Rebuilt | Performance Impact |
|-----------------------------------|-----------------|--------------------|
| ❌ `setState()` on entire screen  | ~1003           | High (full refresh)|
| ✅ `ValueListenableBuilder`       | ~1001           | Medium (scoped)    |
| ✅ Riverpod granular providers    | 1               | Minimal (optimal)  |
| ✅ `DittoDiffer` with keys        | 1               | Minimal (optimal)  |

---

#### Best Practices Summary

**✅ DO:**
- Use state management (Riverpod) for complex apps with multiple data dependencies
- Use `ValueListenableBuilder` for simpler apps or isolated components
- Use `DittoDiffer` with `ValueKey` for large lists with frequent updates
- Profile your app with Flutter DevTools to identify rebuild bottlenecks
- Scope rebuilds to the smallest widget subtree possible

**❌ DON'T:**
- Call `setState()` on the entire screen in observer callbacks
- Rebuild widgets that don't depend on changed data
- Ignore performance implications of full screen refreshes
- Assume Flutter automatically optimizes all rebuilds

**Why This Matters:**
- **Better UX**: Smooth, responsive UI without glitches
- **Battery efficiency**: Less CPU/GPU usage extends battery life
- **Scalability**: App remains performant as data and complexity grow
- **Professional quality**: Users expect fluid experiences, especially in real-time sync scenarios

**Official References:**
- Flutter Performance Best Practices: https://docs.flutter.dev/perf/best-practices
- Riverpod Documentation: https://riverpod.dev/docs/concepts/reading
- Flutter DevTools: https://docs.flutter.dev/tools/devtools/performance

---

## Testing Strategies

### Test Business Logic Under Concurrent Scenarios

**✅ DO:**
- Test **application-specific business logic** with realistic concurrent scenarios
- Focus on **your data model**, not SDK behavior
- Verify **business rules** hold after conflict resolution

```dart
// ✅ GOOD: Test business logic (inventory management)
test('concurrent product sales do not oversell inventory', () async {
  final store1 = createTestDitto('store1');
  final store2 = createTestDitto('store2');

  // Initialize product inventory
  final productId = 'product_123';
  await store1.repository.createProduct(productId, initialStock: 10);
  await syncStores(store1, store2);

  // Simulate concurrent sales at two locations
  await store1.repository.sellProduct(productId, quantity: 7);
  await store2.repository.sellProduct(productId, quantity: 5);

  await syncStores(store1, store2);

  // Verify: Either sale fails OR business rule enforced
  final product1 = await store1.repository.getProduct(productId);
  final product2 = await store2.repository.getProduct(productId);

  // Both stores should see consistent state
  expect(product1.stock, product2.stock);

  // Business rule: stock should never go negative
  expect(product1.stock, greaterThanOrEqualTo(0));

  // If using PN_INCREMENT: stock = 10 - 7 - 5 = -2 (WRONG!)
  // If using validation logic: one sale should be rejected
});

// ✅ GOOD: Test business logic (order numbering)
test('concurrent order creation generates unique order numbers', () async {
  final pos1 = createTestDitto('pos1');
  final pos2 = createTestDitto('pos2');

  await syncStores(pos1, pos2);

  // Create orders concurrently at two POS terminals
  final order1 = await pos1.repository.createOrder(items: [/*...*/]);
  final order2 = await pos2.repository.createOrder(items: [/*...*/]);

  await syncStores(pos1, pos2);

  // Verify: Order numbers must be unique
  expect(order1.orderNumber, isNot(equals(order2.orderNumber)));

  // Verify: Both orders exist in both stores
  final allOrders1 = await pos1.repository.getAllOrders();
  final allOrders2 = await pos2.repository.getAllOrders();
  expect(allOrders1.length, 2);
  expect(allOrders2.length, 2);
});
```

**❌ DON'T:**
- Test only SDK API calls without your app's data model and business logic
- Use generic/fake data models (counters, todos) instead of your actual domain models
- Test scenarios irrelevant to your app's business logic

**Why**: Tests that only verify SDK API behavior (without your app's data model and logic) provide no value—the SDK itself is already tested. What matters is testing how **your specific data model and business logic** behave under concurrent scenarios. Focus on **your application's invariants** (e.g., "inventory never negative", "order numbers unique") using your actual domain models.

---

### Test Deletion Scenarios

**✅ DO:**
- Test tombstone TTL behavior
- Verify logical deletion filtering
- Test "zombie data" scenarios

```dart
// ✅ GOOD: Test logical deletion
test('deleted items do not appear in queries', () async {
  // Create and mark as deleted
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:doc)',
    arguments: {
      'doc': {
        '_id': 'order_1',
        'status': 'active',
        'isDeleted': false,
      },
    },
  );

  await ditto.store.execute(
    'UPDATE orders SET isDeleted = true WHERE _id = :id',
    arguments: {'id': 'order_1'},
  );

  // Query should exclude deleted
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE isDeleted != true',
  );

  final orderIds = result.items.map((i) => i.value['_id']).toList();
  expect(orderIds, isNot(contains('order_1')));
});
```

**Why**: Deletion behavior is complex in distributed systems and must be thoroughly tested.

---

## Performance Best Practices

### Optimize Query Scope

**✅ DO:**
- Use specific queries with WHERE clauses
- Limit subscription scope to needed data
- Use parameterized queries

```dart
// ✅ GOOD: Specific query with parameters
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE customerId = :customerId AND status = :status',
  arguments: {'customerId': customerId, 'status': 'active'},
);
```

**❌ DON'T:**
- Subscribe to entire collections without filtering

```dart
// ❌ BAD: Overly broad subscription
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders',  // All documents!
);
```

**Why**: Broad subscriptions sync and store unnecessary data, impacting performance and storage.

---

### Subscription Scope Balancing: Too Broad vs Too Narrow

**⚠️ CRITICAL**: Finding the right subscription scope requires balancing two competing risks:

| Risk                          | Cause                          | Impact                                                          |
|-------------------------------|--------------------------------|-----------------------------------------------------------------|
| **Performance degradation**   | Overly broad subscriptions     | Sync unnecessary data, consume storage/bandwidth/memory         |
| **Missing data in multi-hop** | Overly narrow subscriptions    | Intermediate peers don't relay documents they don't store       |

#### The Multi-Hop Relay Problem

**Key Principle**: Intermediate devices can only relay documents in their local store. Narrow subscriptions break relay chains.

**Problem**: Device B (relay) filters with `WHERE priority='high'`, Device C (destination) subscribes to all orders → Device C never receives `priority='low'` orders even though Device A (source) has them.

**Why**: Device B's subscription excludes low-priority documents, so it doesn't store them and cannot relay to Device C.

#### Best Practices for Scope Balancing

**1. Subscribe Broadly, Filter Narrowly in Observers**

```dart
// ✅ GOOD: Broad subscription, narrow observer filter
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE customerId = :customerId',  // All customer orders
  arguments: {'customerId': customerId},
);

final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders WHERE customerId = :customerId AND status = :status',  // Only active
  onChange: (result, signalNext) { updateUI(result.items); signalNext(); },
  arguments: {'customerId': customerId, 'status': 'active'},
);
```

**2. Include State Transitions**: If documents can transition states (pending→active→completed), subscribe to all states.

**3. Logical Deletion**: Subscribe without deletion flag filter. See [Logical Deletion](#logical-deletion) for detailed patterns.

**Decision Framework**:

| Question                                          | If YES → Subscribe Broadly  | If NO → Can Filter Narrowly |
|---------------------------------------------------|-----------------------------|------------------------------|
| Can this document's fields change over time?      | ✓                           |                              |
| Do I need to see updates after initial creation?  | ✓                           |                              |
| Can documents transition between states?          | ✓                           |                              |
| Do I use logical deletion?                        | ✓                           |                              |
| Is this data truly immutable after creation?      |                             | ✓                            |

**Why**: Missing data due to broken multi-hop relay is extremely hard to debug (non-obvious topology dependencies). Performance issues are much easier to identify and fix. When in doubt, subscribe broadly and filter in observers.

**Multi-Hop Relay Problem**: Device B (relay) with narrow subscription `WHERE priority='high'` filters out low-priority documents from Device A (source). Device C (destination) subscribing to all orders never receives low-priority documents since Device B doesn't store them.

**Solution**: Device B subscribes broadly `SELECT * FROM orders`, stores all documents, enables relay to Device C. Filter in observers for UI only.

#### Special Case: Logical Deletion (Soft-Delete)

Logical deletion MUST use broad subscriptions to ensure deletion flags propagate through the mesh:

| Component | Pattern | Reason |
|-----------|---------|--------|
| **Subscription** | `SELECT * FROM orders` (no deletion filter) | Ensures deleted documents propagate through multi-hop relay |
| **Observer** | `SELECT * FROM orders WHERE isDeleted != true` | Filters deleted items for UI display |
| **execute()** | `SELECT * FROM orders WHERE isDeleted != true` | Filters deleted items for app logic |

**Common Mistake**: Filtering `isDeleted` in subscription "to reduce bandwidth"

**Result**: Soft-deleted documents don't propagate to indirectly connected peers

**Fix**: Always subscribe broadly, filter only in observers and queries

**Example:**
```dart
// ✅ CORRECT: Subscription includes all documents (even deleted)
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE customerId = :customerId',
  arguments: {'customerId': customerId},
);

// ✅ CORRECT: Observer filters deleted for UI
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders WHERE customerId = :customerId AND isDeleted != true',
  onChange: (result, signalNext) {
    updateUI(result.items);
    signalNext();
  },
  arguments: {'customerId': customerId},
);

// ✅ CORRECT: execute() filters deleted for app logic
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE customerId = :customerId AND isDeleted != true AND status = :status',
  arguments: {'customerId': customerId, 'status': 'active'},
);
```

---

### Handle Attachments Explicitly

**⚠️ CRITICAL: Attachments are not auto-synced**

Attachments use the ATTACHMENT data type to store binary data separately from documents. Unlike documents which are always readily accessible, attachments require explicit fetching.

### Attachment Architecture

**Two Components:**
1. **Metadata**: Stored with the document (filename, size, type, description)
2. **Blob Data**: Stored externally and fetched on demand

**Storage Locations:**
- **Small Peers (Edge devices)**: RAM (browser/server), filesystem (mobile devices)
- **Ditto Server**: AWS S3 cloud object storage

**Blob Sync Protocol:**
Attachment sync operates asynchronously via a separate protocol from document sync. Peers may hold attachment tokens without the corresponding blob data.

### Best Practices

**✅ DO:**
- **Lazy-Load Pattern**: Fetch attachments only when needed to reduce resource usage
- **Add Metadata**: Include descriptive metadata (filename, type, description) to facilitate efficient fetching
- **Handle Errors**: Wrap fetches in try-catch blocks to handle network failures gracefully
- **Keep Fetchers Active**: Attachment fetchers must remain active until completion
- **Consider Deleting Source Files**: After creating attachments with `newAttachment()`, you can delete the original files to avoid storage duplication (unless your app needs quick local access or maintains backups)

```dart
// ✅ GOOD: Lazy-load with metadata
final doc = await ditto.store.execute(
  'SELECT * FROM products WHERE _id = :id',
  arguments: {'id': productId},
);

if (doc.items.isNotEmpty) {
  final docValue = doc.items.first.value;
  final attachmentToken = docValue['imageAttachment'];
  final metadata = docValue['imageMetadata']; // filename, size, type

  if (attachmentToken != null) {
    try {
      // Fetch only when user needs to view the image
      final attachment = await ditto.store.fetchAttachment(attachmentToken);
      displayImage(attachment, metadata);
    } catch (e) {
      // Handle fetch failure (network error, missing blob, etc.)
      showError('Failed to load image: $e');
    }
  }
}
```

**✅ GOOD: Store attachment with metadata**

```dart
// Create attachment and store with metadata
final attachmentToken = await ditto.store.newAttachment(
  imageBytes,
  metadata: {'filename': 'image.jpg', 'mime_type': 'image/jpeg'},
);

await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)',
  arguments: {
    'product': {
      '_id': productId,
      'imageAttachment': attachmentToken,
      'imageMetadata': {'size': imageBytes.length, 'description': 'Product photo'},
    },
  },
);

// ✅ OPTIONAL: Delete source file to avoid storage duplication
await imageFile.delete();
// Consider keeping if: app needs quick access, maintaining backups, or file used elsewhere
```

**❌ DON'T:**
- Store large binary data inline with documents
- Assume attachments sync automatically with subscriptions
- Modify existing attachments (they're immutable - replace the token instead)
- Cancel fetchers before completion

```dart
// ❌ BAD: Inline binary data
await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)',
  arguments: {
    'product': {
      '_id': productId,
      'imageData': base64EncodedLargeImage, // Bloats document size!
    },
  },
);
```

### Attachment Immutability and Updates

**⚠️ Important**: Attachments become immutable once created.

**To Update:**
1. Create new attachment
2. Replace the token in the document using UPDATE

```dart
// ✅ GOOD: Replace attachment
final newImageBytes = await File('new_image.jpg').readAsBytes();
final newToken = await ditto.store.newAttachment(newImageBytes);

await ditto.store.execute(
  'UPDATE products SET imageAttachment = :token, imageMetadata = :metadata WHERE _id = :id',
  arguments: {
    'token': newToken,
    'metadata': {
      'filename': 'new_image.jpg',
      'size': newImageBytes.length,
      'type': 'image/jpeg',
    },
    'id': productId,
  },
);
```

### Garbage Collection

**Automatic Cleanup:**
- Small Peers run garbage collection on a 10-minute cadence
- Unreferenced attachments are automatically removed

**Why Explicit Fetching:**
- **Bandwidth efficiency**: Prevents automatic transfer of large files
- **Resource control**: Apps fetch only when needed
- **Battery conservation**: Reduces unnecessary data transfer on mobile devices
- **Storage management**: Lazy-loading reduces local storage pressure

---

### The Thumbnail Pattern for Photos and Large Files

When sharing photos or large files in bandwidth-constrained mesh networks, use the **thumbnail-first** pattern: automatically sync a small preview while making the full resolution available on-demand.

**Problem**: A 5MB photo takes ~6 minutes over Bluetooth LE at 100 Kbps, starving other critical data.

**Solution**: Store two attachments per photo:
1. **Thumbnail** (~50KB): Auto-fetched, provides immediate preview
2. **Full resolution** (~5MB): On-demand fetch when user requests

```dart
// ✅ GOOD: Thumbnail + full resolution pattern
Future<void> sharePhoto(Uint8List imageData, String caption) async {
  // 1. Generate thumbnail (resize to 200x200, quality 70%)
  final thumbnailData = await generateThumbnail(imageData);

  // 2. Create both attachments
  final thumbnailToken = await ditto.store.newAttachment(
    thumbnailData,
    metadata: {'name': 'photo_thumb.jpg', 'mime_type': 'image/jpeg'},
  );

  final fullResToken = await ditto.store.newAttachment(
    imageData,
    metadata: {'name': 'photo_full.jpg', 'mime_type': 'image/jpeg'},
  );

  // 3. Insert document with BOTH attachment tokens
  // ⚠️ CRITICAL: Declare ATTACHMENT types in COLLECTION clause
  await ditto.store.execute(
    'INSERT INTO COLLECTION photos (thumbnail ATTACHMENT, full_resolution ATTACHMENT) DOCUMENTS (:photo)',
    arguments: {
      'photo': {
        '_id': photoId,
        'caption': caption,
        'thumbnail': thumbnailToken,
        'full_resolution': fullResToken,
        'created_at': DateTime.now().toIso8601String(),
      },
    },
  );
}
```

**Size-Based Auto-Download Strategy**:

Use the `len` field from attachment tokens to decide whether to auto-fetch:

```dart
// ✅ GOOD: Auto-fetch thumbnails, manual fetch for full resolution
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM photos ORDER BY created_at DESC',
  onChange: (result, signalNext) {
    for (final item in result.items) {
      final photo = item.value;
      final thumbnailToken = photo['thumbnail'];
      final thumbnailSize = thumbnailToken['len'];

      // Auto-fetch thumbnails if small enough (e.g., < 100KB)
      if (thumbnailSize < 100 * 1024 && !_alreadyFetched(thumbnailToken)) {
        ditto.store.fetchAttachment(thumbnailToken, (event) {
          if (event is AttachmentFetchEventCompleted) {
            updateThumbnailInUI(photo['_id'], event.attachment);
          }
        });
      }
    }

    signalNext();
  },
);

// User-initiated full resolution download
Future<void> downloadFullResolution(String photoId) async {
  final result = await ditto.store.execute(
    'SELECT * FROM photos WHERE _id = :id',
    arguments: {'id': photoId},
  );

  final fullResToken = result.items.first.value['full_resolution'];

  ditto.store.fetchAttachment(fullResToken, (event) {
    if (event is AttachmentFetchEventProgress) {
      updateDownloadProgress(event.downloadedBytes, event.totalBytes);
    } else if (event is AttachmentFetchEventCompleted) {
      displayFullResolutionImage(event.attachment);
    }
  });
}
```

**Benefits**:

| Metric                | Full Resolution Only | Thumbnail + On-Demand |
|-----------------------|----------------------|-----------------------|
| Initial sync          | 5 MB                 | 50 KB                 |
| Time over BLE         | ~6 minutes           | ~4 seconds            |
| User feedback         | Delayed              | Immediate             |
| Mesh impact           | High                 | Minimal               |

**Official Reference**: [Photo Sharing Guide](https://docs.ditto.live/guides/photo-sharing)

---

### Attachment Availability Constraints

**⚠️ CRITICAL**: Attachments can only be fetched from **immediate peers** (directly connected devices) that have already fetched the attachment themselves.

**Scenario**:
```
Device A (has full res) ← connected → Device B (has thumbnail only) ← connected → Device C (wants full res)
```

In this mesh:
- Device C **cannot** fetch the full resolution from Device A (not directly connected)
- Device C can only see the document and thumbnail
- Device B must first download the full resolution before C can access it

**Mitigation Strategies**:
- Use thumbnails to reduce the impact of this limitation
- Consider having relay/hub devices that always fetch attachments
- Design UI to show availability status ("Available from 2 peers")
- Implement retry logic when attachments become available

```dart
// ✅ GOOD: Show attachment availability in UI
Future<void> checkAttachmentAvailability(String photoId) async {
  final result = await ditto.store.execute(
    'SELECT * FROM photos WHERE _id = :id',
    arguments: {'id': photoId},
  );

  final fullResToken = result.items.first.value['full_resolution'];
  final peerCount = ditto.store.getAttachmentPeerCount(fullResToken);

  if (peerCount == 0) {
    showUI('Full resolution not available yet');
  } else {
    showUI('Available from $peerCount peer(s) - Download now?');
  }
}
```

---

### Attachment Fetch Timeout Handling

Attachment fetches can be interrupted by connectivity changes. Ditto handles this gracefully:
- **Progress is preserved**: If interrupted, it resumes from where it left off
- **Multiple sources**: If a peer disconnects, another peer can continue
- **No error on stall**: If all sources disconnect, the fetch simply stalls—no error is raised

**Implement timeout wrapper to detect stalled fetches**:

```dart
// ✅ GOOD: Timeout wrapper for attachment fetch
Future<Attachment> fetchAttachmentWithTimeout(
  AttachmentToken token,
  Duration timeout,
) async {
  final completer = Completer<Attachment>();
  DateTime lastProgress = DateTime.now();
  Timer? timer;

  timer = Timer.periodic(Duration(seconds: 5), (t) {
    if (DateTime.now().difference(lastProgress) > timeout) {
      t.cancel();
      fetcher?.cancel();
      completer.completeError('Fetch stalled: no progress for ${timeout.inSeconds}s');
    }
  });

  final fetcher = ditto.store.fetchAttachment(token, (event) {
    lastProgress = DateTime.now();
    if (event is AttachmentFetchEventCompleted) {
      timer?.cancel();
      completer.complete(event.attachment);
    } else if (event is AttachmentFetchEventDeleted) {
      timer?.cancel();
      completer.completeError('Attachment deleted during fetch');
    }
  });

  return completer.future;
}

// Usage
try {
  final attachment = await fetchAttachmentWithTimeout(token, Duration(minutes: 5));
  displayImage(attachment);
} catch (e) {
  showError('Download failed: $e');
}
```

**Why**: Stalled fetches tie up resources indefinitely. Timeout detection allows you to retry, notify users, or abandon the fetch gracefully.

---

### Transactions

**⚠️ CRITICAL: Understanding Ditto Transactions**

Transactions group multiple DQL operations into a single atomic database commit with serializable isolation level, providing the strongest consistency guarantees.

**⚠️ Flutter SDK Transaction Limitation (v4.11+):**
The Flutter SDK supports the `ditto.store.transaction()` API starting from SDK v4.11, but **all Flutter SDK versions (v4.11+)** have one critical limitation:
- **Does not wait for pending transactions to complete when closing Ditto instance**
- **You must manually await all transaction completions before calling `ditto.close()`**
- Failure to do so may result in incomplete transactions
- This limitation applies to all current Flutter SDK versions (v4.11, v4.12, v4.14.0, etc.)

All other transaction features work identically to other platforms:
- Atomic multi-step operations
- Serializable isolation level
- Read-write and read-only transactions
- Nested transaction deadlock prevention
- Transaction hints and info

**For All Platforms:**

**What Transactions Provide:**
- **Atomicity**: All operations complete or none execute
- **Consistency**: All statements see identical data snapshots within the transaction
- **Serializable isolation**: Strongest consistency level
- **Implicit rollback**: Errors automatically rollback the entire transaction

**Critical Limitations:**
- **Single read-write transaction at a time**: Only one read-write transaction executes concurrently; others must wait
- **NEVER nest read-write transactions**: Creates deadlock where inner waits for outer, outer waits for inner
- **Complete quickly**: Long-running transactions block all other read-write transactions
- **Warning thresholds**: Ditto logs warnings after 10 seconds, escalating every 5 seconds

**✅ DO (All Platforms):**
- Use transactions for multi-step operations requiring atomicity
- Set descriptive `hint` parameters for debugging
- Keep transaction blocks minimal and fast
- Use read-only mode when mutation isn't needed
- Return values directly (automatic commit) or explicitly return `.commit`
- Handle specific errors within the block if transaction should continue
- **(Flutter-specific)**: Track pending transactions and await all before calling `ditto.close()`

```dart
// ✅ GOOD: Read-write transaction with atomicity
await ditto.store.transaction(hint: 'process-order', (tx) async {
  // All statements see the same data snapshot
  final orderResult = await tx.execute(
    'SELECT * FROM orders WHERE _id = :orderId',
    arguments: {'orderId': orderId},
  );

  if (orderResult.items.isEmpty) {
    throw Exception('Order not found');
  }

  final order = orderResult.items.first.value;

  // Update order status
  await tx.execute(
    'UPDATE orders SET status = :status WHERE _id = :orderId',
    arguments: {'orderId': orderId, 'status': 'shipped'},
  );

  // Decrement inventory
  await tx.execute(
    'UPDATE inventory APPLY quantity PN_INCREMENT BY -1.0 WHERE _id = :itemId',
    arguments: {'itemId': order['itemId']},
  );

  return; // Automatic commit
});

// ✅ GOOD: Read-only transaction (concurrent execution allowed)
await ditto.store.transaction(
  hint: 'read-order-summary',
  isReadOnly: true,
  (tx) async {
    final orders = await tx.execute('SELECT * FROM orders');
    final items = await tx.execute('SELECT * FROM order_items');

    return calculateSummary(orders, items); // Automatic commit with return value
  },
);
```

**❌ DON'T (All Platforms):**
- Nest read-write transactions (causes permanent deadlock)
- Execute operations outside transaction object within block
- Use transactions for long-running operations
- **(Flutter-specific)**: Close Ditto without awaiting pending transactions

```dart
// ❌ BAD: Nested read-write transaction (DEADLOCK!)
await ditto.store.transaction((outerTx) async {
  await outerTx.execute('UPDATE orders SET status = :status WHERE _id = :id',
    arguments: {'status': 'processing', 'id': orderId});

  // DEADLOCK: Inner transaction waits for outer, outer waits for inner
  await ditto.store.transaction((innerTx) async {
    await innerTx.execute('UPDATE inventory SET quantity = :qty WHERE _id = :id',
      arguments: {'qty': 0, 'id': itemId});
  });
});
```

**Flutter-Specific: Managing Transaction Completion**

Since Flutter SDK doesn't wait for pending transactions when closing Ditto, you must track and await all transactions manually:

```dart
// ✅ GOOD: Track pending transactions in Flutter
class DittoManager {
  final Ditto ditto;
  final Set<Future<void>> _pendingTransactions = {};

  Future<void> executeTransaction(
    Future<void> Function(DittoTransaction) block, {
    String? hint,
    bool isReadOnly = false,
  }) async {
    final transactionFuture = ditto.store.transaction(
      hint: hint,
      isReadOnly: isReadOnly,
      block,
    );

    _pendingTransactions.add(transactionFuture);

    try {
      await transactionFuture;
    } finally {
      _pendingTransactions.remove(transactionFuture);
    }
  }

  Future<void> close() async {
    // ✅ CRITICAL: Wait for all transactions before closing
    await Future.wait(_pendingTransactions);
    await ditto.close();
  }
}

// Usage example
final dittoManager = DittoManager(ditto);

await dittoManager.executeTransaction(
  (tx) async {
    final orderResult = await tx.execute(
      'SELECT * FROM orders WHERE _id = :orderId',
      arguments: {'orderId': orderId},
    );

    if (orderResult.items.isEmpty) {
      throw Exception('Order not found');
    }

    final order = orderResult.items.first.value;

    await tx.execute(
      'UPDATE orders SET status = :status WHERE _id = :orderId',
      arguments: {'orderId': orderId, 'status': 'shipped'},
    );

    await tx.execute(
      'UPDATE inventory APPLY quantity PN_INCREMENT BY -1.0 WHERE _id = :itemId',
      arguments: {'itemId': order['itemId']},
    );
  },
  hint: 'process-order',
);

// ❌ BAD: Close without awaiting transactions
Future<void> cleanup() async {
  // Start a transaction
  unawaited(ditto.store.transaction((tx) async {
    await tx.execute('UPDATE ...');
  }));

  // Close immediately - transaction may be incomplete!
  await ditto.close(); // WRONG!
}
```

**Why Transactions Matter (Where Supported):**
- Ensures multi-step operations complete atomically (all or nothing)
- Provides consistent view of data across multiple queries
- Prevents partial updates that could corrupt data
- But: Only one read-write transaction runs at a time, so keep them fast

**Read-Only Transactions (Where Supported):**
Multiple read-only transactions can execute concurrently, even alongside read-write transactions. Use `isReadOnly: true` for operations that only query data.

**Performance Guidelines (Where Supported):**
- Complete transactions in milliseconds, not seconds
- Move heavy computation outside transaction blocks
- Use read-only transactions when possible
- Monitor transaction duration warnings in logs

**Official Reference**: [Ditto Transactions Documentation](https://docs.ditto.live/sdk/latest/crud/transactions)

---

## Device Storage Management

**⚠️ CRITICAL: Why Storage Management Matters**

Data storage management is essential for preventing unnecessary resource usage, which affects not only performance but also battery life and overall end-user experience. In Ditto's distributed system, deletion uses a soft-delete pattern - documents flagged as deleted remain in storage until explicitly evicted to ensure network synchronization across devices.

### Understanding EVICT vs DELETE

**DELETE (Soft Delete):**
- Flags document as deleted
- Creates tombstone for synchronization
- Document remains in local storage
- Tombstone propagates to other peers
- Subject to tombstone TTL

**EVICT (Hard Delete):**
- Actually removes data from local disk
- Local-only operation (does not sync to other peers)
- No tombstone created
- Immediately frees disk space
- Cannot be undone

**Key Principle**: Use DELETE for mesh-wide deletion that needs to propagate. Use EVICT for local storage cleanup.

### EVICT Best Practices

**✅ DO:**
- Run EVICT automatically on a regular schedule
- Execute during periods of minimal disruption (e.g., after hours, at night)
- Limit frequency to once per day maximum (recommended)
- Cancel affected subscriptions before eviction
- Recreate subscriptions after eviction completes
- Use with logical deletion pattern for safe cleanup

```dart
// ✅ GOOD: Scheduled eviction with subscription management
Future<void> performDailyEviction() async {
  // Step 1: Cancel subscriptions that might be affected
  orderSubscription?.cancel();

  // Step 2: Evict old deleted documents (local cleanup)
  final cutoffDate = DateTime.now()
      .subtract(const Duration(days: 90))
      .toIso8601String();

  await ditto.store.execute(
    'EVICT FROM orders WHERE isDeleted = true AND deletedAt < :cutoffDate',
    arguments: {'cutoffDate': cutoffDate},
  );

  // Step 3: Recreate subscription with updated query
  orderSubscription = ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE isDeleted != true AND createdAt > :cutoffDate',
    arguments: {'cutoffDate': cutoffDate},
  );
}

// Schedule once per day during low-usage period
Timer.periodic(Duration(days: 1), (_) {
  // Run at 3 AM local time or during detected low-usage period
  if (isLowUsagePeriod()) {
    performDailyEviction();
  }
});
```

**❌ DON'T:**
- Run EVICT more than once per day
- Evict during peak usage hours
- Forget to cancel subscriptions before evicting
- Use same query for eviction and subscription (causes resync loop)

```dart
// ❌ BAD: Frequent eviction causing excessive network traffic
Timer.periodic(Duration(hours: 1), (_) {
  // Too frequent! Causes network overhead
  ditto.store.execute('EVICT FROM orders WHERE isDeleted = true');
});

// ❌ BAD: Eviction without subscription management
await ditto.store.execute('EVICT FROM orders WHERE isDeleted = true');
// Active subscription will immediately resync evicted data!
```

**Why Limit Frequency**: Eviction can trigger resyncs with connected peers if subscriptions overlap with evicted data, potentially creating network traffic and processing overhead. Running EVICT conservatively (once per day during low-usage periods) prevents performance degradation.

### Time-to-Live (TTL) Eviction Strategy

**Two Primary Approaches:**

#### 1. Big Peer (Cloud) Management (RECOMMENDED)

Centralized TTL management where Ditto Server sets eviction flags via HTTP API, and Small Peers evict locally based on those flags.

**Advantages:** Centralized control, prevents data loss (documents sync before eviction), consistent policy across peers.

**Implementation:** Big Peer uses HTTP API to set `evictionFlag = true` on old documents, Small Peers then execute `EVICT FROM orders WHERE evictionFlag = true`.

#### 2. Small Peer Local Management

Each device manages its own TTL-based evictions:

**When to Use:**
- Not using Ditto Server (Big Peer)
- Confident devices won't remain offline longer than eviction cycle
- Need device-specific eviction policies

**Implementation:**
```dart
// ✅ GOOD: Time-based eviction with proper subscription handling
Future<void> evictOldDocuments({required int ttlDays}) async {
  final cutoffDate = DateTime.now()
      .subtract(Duration(days: ttlDays))
      .toIso8601String();

  // Cancel affected subscription
  oldOrdersSubscription?.cancel();

  // Evict old documents
  await ditto.store.execute(
    'EVICT FROM orders WHERE createdAt <= :cutoffDate',
    arguments: {'cutoffDate': cutoffDate},
  );

  // Create new subscription excluding evicted timeframe
  oldOrdersSubscription = ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE createdAt > :cutoffDate',
    arguments: {'cutoffDate': cutoffDate},
  );
}

// Example: 72-hour TTL for flight ordering system
await evictOldDocuments(ttlDays: 3);
```

### Flag-Based Eviction Pattern

**Use Case**: Centralized eviction control with fine-grained document targeting.

**Step 1**: Declare eviction flag via HTTP API (Big Peer sets flag)
**Step 2**: Query for eviction on Small Peers
**Step 3**: Execute local eviction

```dart
// ✅ GOOD: Flag-based eviction with distinct queries
// Subscription query (opposite of eviction query)
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE evictionFlag != true',
);

// Eviction query (targets flagged documents)
await ditto.store.execute(
  'EVICT FROM orders WHERE evictionFlag = true',
);
```

**Critical**: The query used for eviction must be the opposite of the query used for subscription. Using overlapping queries creates a resync loop where Ditto continuously evicts documents and then automatically re-syncs them.

### Storage Management Patterns

**Industry-Specific TTL Examples:**
- Airlines: 72-hour TTL for flight data
- Retail: 7-day TTL for transaction data
- Quick-service restaurants: 24-hour TTL for order data

### Subscription Lifecycle Management

**⚠️ CRITICAL: Top-Level Subscription Declaration**

Declare subscription objects from the top-most scope of your app to ensure access throughout the app lifecycle:

```dart
// ✅ GOOD: Top-level subscription management
class OrderService {
  Subscription? _activeOrdersSubscription;

  Future<void> initialize() async {
    _activeOrdersSubscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE isDeleted != true',
    );
  }

  Future<void> performEviction() async {
    _activeOrdersSubscription?.cancel();
    await ditto.store.execute(
      'EVICT FROM orders WHERE isDeleted = true AND deletedAt < :date',
      arguments: {'date': getOldDate()},
    );
    _activeOrdersSubscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE isDeleted != true',
    );
  }

  void dispose() => _activeOrdersSubscription?.cancel();
}
```

**Why**: Top-level declaration enables subscription access throughout the app lifecycle, essential for canceling before EVICT to prevent resync loops.

### Performance Impact

**Benefits of Proper Storage Management:**
- Faster load times
- Improved battery life
- More responsive UI
- Reduced network usage
- Lower memory footprint

**Risks of Poor Management:**
- Excessive disk usage
- Slower queries
- Battery drain
- Unnecessary network traffic from resync loops
- Performance degradation over time

**Official Reference**: [Ditto Device Storage Management](https://docs.ditto.live/sdk/latest/sync/device-storage-management)

---

## Timestamp Best Practices

### The Timestamp Challenge in Distributed Systems

In Ditto's mesh architecture, **each device operates on its own independent time**, creating significant synchronization challenges. Documents created simultaneously on different devices will have different timestamps, and clock drift can cause seemingly impossible scenarios.

### Clock Drift Reality

**Device Time Accuracy:**
- **iOS devices**: Typically deviate within **100 milliseconds**
- **Android devices**: Can drift by **several seconds** in either direction
- System clock synchronization doesn't guarantee precision
- Even with clock sync enabled, precise accuracy is not guaranteed

**⚠️ CRITICAL**: Never assume device timestamps are reliable in applications requiring precision.

### Recommended Approaches

#### 1. Store Timestamps as ISO-8601 Strings (Recommended)

**Recommended approach**: Use **ISO-8601 formatted date strings** for consistency across platforms and proper querying.

```dart
// ✅ GOOD: Store timestamp as ISO-8601 string
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {
    'order': {
      '_id': orderId,
      'createdAt': DateTime.now().toIso8601String(),  // "2025-01-15T10:30:45.123Z"
      'updatedAt': DateTime.now().toIso8601String(),
      'status': 'pending',
    },
  },
);

// ✅ GOOD: Query by timestamp range
final result = await ditto.store.execute(
  "SELECT * FROM orders WHERE createdAt >= '2025-01-01T00:00:00Z' AND createdAt < '2025-02-01T00:00:00Z'",
);
```

**Benefits of ISO-8601:**
- International standard format
- Lexicographically sortable (alphabetical sort = chronological sort)
- Platform-independent (no integer overflow concerns across different platforms)
- Human-readable and debugging-friendly
- DQL query-friendly with string comparison

**Alternative: UNIX Timestamps (Epoch Seconds)**
UNIX timestamps (seconds since epoch) are also valid and avoid ISO-8601's platform parsing differences:

```dart
// ✅ ALSO GOOD: UNIX timestamp (seconds since epoch)
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {
    'order': {
      '_id': orderId,
      'createdAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,  // 1705314645
      'updatedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'status': 'pending',
    },
  },
);

// Query by UNIX timestamp range
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE createdAt >= :start AND createdAt < :end',
  arguments: {
    'start': DateTime(2025, 1, 1).millisecondsSinceEpoch ~/ 1000,
    'end': DateTime(2025, 2, 1).millisecondsSinceEpoch ~/ 1000,
  },
);
```

**UNIX Timestamp Benefits:**
- No platform parsing differences
- Straightforward numerical sorting and comparison
- Compact storage (integer vs string)
- No timezone ambiguity (always UTC)

**Choose Based On:**
- **ISO-8601**: Prefer for human readability, debugging, and when working with date strings
- **UNIX Timestamp**: Prefer for numerical operations, sorting reliability, and compact storage

#### 2. Anticipate and Handle Time Discrepancies

Build error tolerance into your logic to handle clock drift scenarios.

```dart
// ✅ GOOD: Handle time discrepancies gracefully
class OrderValidator {
  bool isValidOrder(Map<String, dynamic> order) {
    final createdAt = DateTime.parse(order['createdAt']);
    final updatedAt = DateTime.parse(order['updatedAt']);
    final now = DateTime.now();

    // Allow for reasonable clock drift (e.g., 5 minutes)
    const maxClockDrift = Duration(minutes: 5);

    // Check if timestamps are "impossible" (future timestamps)
    if (createdAt.isAfter(now.add(maxClockDrift))) {
      // Device clock is ahead - log warning but accept document
      logger.warning('Order created in future due to clock drift: $orderId');
      return true; // Accept with tolerance
    }

    // Check if updatedAt is before createdAt
    if (updatedAt.isBefore(createdAt.subtract(maxClockDrift))) {
      // Significant clock drift detected
      logger.warning('UpdatedAt before createdAt due to clock drift: $orderId');
      return true; // Accept with tolerance
    }

    return true;
  }
}
```

#### 3. Use Network Time Protocol (NTP) for Critical Applications

For applications demanding high accuracy, synchronize device clocks with authoritative time servers.

```dart
// ✅ GOOD: Use NTP for accurate time
class AccurateTimeService {
  DateTime? _offset;

  Future<void> syncWithNTP() async {
    try {
      final ntpTime = await NTP.now();
      _offset = ntpTime.difference(DateTime.now());
    } catch (e) {
      _offset = null; // Fall back to device time
    }
  }

  DateTime getNow() => _offset != null
    ? DateTime.now().add(_offset!)
    : DateTime.now();

  // Use corrected time in documents
  String getTimestamp() => getNow().toIso8601String();
}
```

#### 4. Alternative Approaches

**Logical Timestamps**: Use sequence numbers instead of wall-clock time for ordering events.
```dart
'sequenceNumber': getNextSequence(), // Monotonic counter
'timestamp': DateTime.now().toIso8601String(), // Reference only
```

**Relative Time**: Calculate durations from known reference points.
```dart
'startTime': startTime.toIso8601String(),
'durationSeconds': DateTime.now().difference(startTime).inSeconds,
```

**Server-Side Timestamping**: Let Ditto Cloud/Big Peer assign authoritative timestamps.
```dart
'clientTimestamp': DateTime.now().toIso8601String(),
// Server adds 'serverTimestamp' during sync
```

### Best Practices

**✅ DO:**
- **Recommended**: Use ISO-8601 formatted timestamps (`DateTime.now().toIso8601String()`) for human readability
- **Alternative**: Use UNIX timestamps (seconds since epoch) for numerical reliability and compact storage
- Anticipate time discrepancies and build error tolerance
- Use NTP synchronization for time-critical applications
- Document your timing assumptions and tolerance ranges
- Choose timestamp format based on your use case (readability vs numerical operations)
- Consider logical ordering (sequence numbers) for event streams
- Store both client and server timestamps for audit trails

**❌ DON'T:**
- Assume device clocks are synchronized across the mesh
- Reject documents solely based on timestamp validation
- Use platform-specific timestamp formats (Unix epoch, platform Date objects)
- Rely on timestamp precision for conflict resolution (use Ditto's CRDT semantics instead)
- Store timestamps as numbers (use ISO-8601 strings)

**Platform-Specific Implementations:**

```dart
// Dart/Flutter
final timestamp = DateTime.now().toIso8601String();

// Swift (iOS)
// let timestamp = ISO8601DateFormatter().string(from: Date())

// Kotlin (Android)
// val timestamp = Instant.now().toString()

// JavaScript/TypeScript
// const timestamp = new Date().toISOString()
```

**Why**: In distributed systems, devices have independent clocks with varying degrees of accuracy. Building time-awareness into your application logic prevents data inconsistencies and handles clock drift gracefully. ISO-8601 ensures cross-platform compatibility and proper query behavior.

**⚠️ SDK 4.11+ Note**: Native date operators (date_cast, date_add, date_sub, clock, etc.) provide powerful temporal query capabilities. See [DQL Operator Expressions - Date and Time Operators](#date-and-time-operators-sdk-411) for migration patterns from ISO-8601 string comparisons to date functions.

**Official Reference**: [Ditto Timestamp Best Practices](https://docs.ditto.live/best-practices/timestamps)

---

## Security Best Practices

### Validate All Inputs

**✅ DO:**
- Validate data before inserting into Ditto
- Sanitize user inputs
- Check data types and ranges

```dart
// ✅ GOOD: Input validation
Future<void> createOrder(String? customerId, List<dynamic>? items) async {
  if (customerId == null || customerId.isEmpty) {
    throw ArgumentError('Invalid customerId');
  }
  if (items == null || items.isEmpty) {
    throw ArgumentError('Invalid items');
  }

  final order = {
    '_id': generateId(),
    'customerId': customerId,
    'items': items.map((item) => {
      'productId': item['productId'].toString(),
      'quantity': max(1, (item['quantity'] as num).floor()),
    }).toList(),
    'createdAt': DateTime.now().toIso8601String(),
  };

  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {'order': order},
  );
}
```

**Why**: Ditto is schema-less, so application-level validation is critical.

---

### Authentication and Authorization

Ditto provides three authentication mechanisms for different deployment scenarios. Choosing the correct authentication mode is critical for security and proper data access control.

#### Authentication Modes

**1. Online Playground (Development Only)**

**Purpose**: Development, testing, demos, hackathons

**How it works**:
- Devices connect via Ditto Server using shared app ID and Playground token
- Functions like a static API key shared by all clients
- No per-user identity or differentiation

**Security level**: ⚠️ **NOT SECURE** - Unsuitable for production or sensitive data

```dart
// ✅ GOOD: Online Playground for development only
final ditto = await Ditto.open(
  identity: OnlinePlaygroundIdentity(
    appId: 'your-app-id',
    token: 'your-playground-token',
  ),
);
```

**⚠️ Limitations**:
- All clients have identical access
- No user-level permissions
- Shared static token (anyone with token has full access)
- Should NEVER be used with sensitive data

---

**2. Online with Authentication (Recommended for Production)**

**Purpose**: Production deployments requiring user identity verification and granular permissions

**How it works**:
1. Client authenticates with your identity system (e.g., your backend API)
2. Client retrieves a secret token (often JWT format)
3. Token passed to Ditto's `authenticator` callback
4. Authentication webhook validates and decodes token
5. Server returns user identity and permission information

**Security level**: ✅ **Enterprise-grade** with fine-grained access control

```dart
// ✅ GOOD: Online with Authentication for production
final ditto = await Ditto.open(
  identity: OnlineWithAuthenticationIdentity(
    authenticationDelegate: MyAuthenticationDelegate(),
    appId: 'your-app-id',
  ),
);

class MyAuthenticationDelegate extends DittoAuthenticationDelegate {
  @override
  Future<String?> authenticationRequired(DittoAuthenticator authenticator) async {
    // 1. Authenticate with your backend
    final token = await myBackend.login(username, password);

    // 2. Pass token to Ditto
    await authenticator.loginWithToken(token);

    return null;
  }

  @override
  Future<void> authenticationExpiringSoon(
    DittoAuthenticator authenticator,
    int secondsRemaining,
  ) async {
    // Refresh token before expiration
    final newToken = await myBackend.refreshToken();
    await authenticator.loginWithToken(newToken);
  }
}
```

**Permission Structure**:

Permissions are expressed as collection-level DQL queries with read/write capabilities:

```json
{
  "authenticated": true,
  "userID": "user_123",
  "expirationSeconds": 28800,
  "permissions": {
    "read": {
      "queriesByCollection": {
        "orders": ["_id.userId == 'user_123'"],
        "products": ["true"]
      }
    },
    "write": {
      "queriesByCollection": {
        "orders": ["_id.userId == 'user_123'"]
      }
    }
  }
}
```

**⚠️ CRITICAL Permission Constraint**: Permissions can **only** be specified on the immutable `_id` field

**Key Benefits**:
- Each user/device has distinct identity
- Fine-grained authorization rules per user
- Role-based access control (viewer, editor, admin)
- Token expiration and refresh mechanism
- Server-side permission enforcement

---

**3. Offline Shared Key (Air-Gapped Environments)**

**Purpose**: Closed, controlled environments without cloud connectivity

**How it works**:
- All peers share a single secret cryptographic key
- Self-signed TLS certificates using supplied private key
- Trust model: Any peer with the shared key is trusted

**Security level**: ⚠️ **Requires controlled key distribution** (recommend MDM)

```dart
// ✅ GOOD: Offline Shared Key for air-gapped deployments
final ditto = await Ditto.open(
  identity: SharedKeyIdentity(
    appId: 'your-app-id',
    sharedKey: 'your-shared-key',
  ),
);
```

**Ideal for**:
- Air-gapped deployments
- Managed device fleets (MDM distribution)
- Offline-first operations
- Closed, controlled networks

**⚠️ Limitations**:
- No peer-level revocation capability
- Single leaked key compromises entire system
- **Key leakage risk**: Keys hardcoded in applications can be extracted via reverse engineering (decompiling APK/IPA files)
- No granular security controls
- Requires offline-only license token (contact: [email protected])

---

#### Best Practices

**✅ DO:**
- **Use Online with Authentication for production** with real users and sensitive data
- Model data so access-controlled fields exist in `_id` (e.g., `_id.userId`, `_id.organizationId`)
- Implement webhook validation in your authentication service
- Use token expiration and refresh mechanisms
- Validate permissions at application level as additional security layer
- Use MDM for Shared Key distribution in managed environments

**❌ DON'T:**
- Use Online Playground in production or with sensitive data
- Use Shared Key without controlled distribution mechanism
- **Hardcode Shared Keys in application code** (vulnerable to reverse engineering attacks)
- Rely solely on client-side permission checks
- Store sensitive data without proper authentication mode
- Specify permissions on mutable fields (only `_id` is allowed)

**Security Notes**:
- **Transport encryption**: All authentication modes use TLS 1.3 (mTLS) by default to encrypt data in transit between peers
- **Storage encryption**: Data in the local Ditto store is **not encrypted at rest in current versions** by default. For sensitive data, consider implementing application-level encryption before storing in Ditto, or use platform-specific storage encryption (e.g., iOS Data Protection, Android Full Disk Encryption)
- **Shared Key security risk**: Hardcoded keys in mobile apps are vulnerable to reverse engineering. Attackers can decompile APK/IPA files to extract keys. Use MDM or secure key provisioning for controlled distribution
- Permissions enforced by both Ditto Server and participating devices
- Unauthorized documents won't synchronize across mesh
- Generate shared keys using `ditto-authtool` utility or OpenSSL

**Why**: Proper authentication ensures authorized access to synced data. Online Playground provides no security and is only suitable for development/testing. Production apps require Online with Authentication for user identity and fine-grained permissions.

---

## Query Optimization & Indexing

### DQL Indexes (SDK 4.12.0+)

Ditto SDK 4.12.0+ supports **simple indexes on single fields** to dramatically improve query performance for large datasets.

**Availability:**
- ✅ SDK `execute` API (SDK 4.12+)
- ✅ SDK `registerObserver` API (SDK 4.12+)
- ❌ SDK `registerSubscription` API (not supported in current versions)
- ❌ Ditto Server HTTP API (not supported in current versions)
- ❌ In-memory storage SDKs (not supported in current versions)

### Creating and Managing Indexes

**Basic Syntax:**

```dart
// ✅ GOOD: Create index with IF NOT EXISTS for idempotent operations
await ditto.store.execute('CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status)');

// Create index on nested field (dot notation)
await ditto.store.execute('CREATE INDEX IF NOT EXISTS idx_user_location ON users (address.city)');

// Drop index safely
await ditto.store.execute('DROP INDEX IF EXISTS idx_orders_status');

// View all indexes
final result = await ditto.store.execute('SELECT * FROM system:indexes');
```

**✅ DO:**
- Create indexes during application initialization (batch creation at startup)
- Use `IF NOT EXISTS` clause to prevent errors in initialization scripts
- Index frequently queried fields in WHERE clauses
- Index fields used in ORDER BY clauses
- Monitor indexes using `system:indexes` collection
- Remove unused indexes to improve write performance

**❌ DON'T:**
- Create indexes on-demand during runtime (performance impact from full collection scans)
- Create duplicate indexes with same name (query `system:indexes` first to check)
- Index fields that are rarely queried
- Create indexes without measuring actual performance benefits

### Performance Impact and Query Selectivity

Index effectiveness is **inversely related to query selectivity** (percentage of documents returned):

**Highly Selective Queries** (return <10% of documents):
- ~90% faster with appropriate indexes
- Index allows skipping 90% of documents entirely
- Best use case for indexing

**Less Selective Queries** (return >50% of documents):
- Minimal performance benefit
- Most documents still require examination
- Index overhead may not be justified

**Example:**

```dart
// ✅ GOOD: Highly selective query benefits from index
// If only 5% of orders have status 'pending':
await ditto.store.execute(
  'CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status)',
);
final result = await ditto.store.execute(
  "SELECT * FROM orders WHERE status = 'pending'",
); // ~90% faster with index

// ⚠️ CAUTION: Less selective query - limited benefit
// If 60% of users have isActive = true:
await ditto.store.execute(
  'CREATE INDEX IF NOT EXISTS idx_users_active ON users (isActive)',
);
final result = await ditto.store.execute(
  "SELECT * FROM users WHERE isActive = true",
); // Minimal performance gain
```

### Advanced Index Usage (SDK 4.13.0+)

**Union and Intersect Scans** enable multiple indexes to be used simultaneously:

**Union Scans** (OR, IN operators):

```dart
// Create indexes for both fields
await ditto.store.execute('CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status)');
await ditto.store.execute('CREATE INDEX IF NOT EXISTS idx_orders_priority ON orders (priority)');

// Query uses BOTH indexes via union scan
final result = await ditto.store.execute(
  "SELECT * FROM orders WHERE status = 'active' OR priority = 'high'",
); // Combines results from both index scans - much faster than full collection scan
```

**Intersect Scans** (AND operators):

```dart
// Create indexes for both fields
await ditto.store.execute('CREATE INDEX IF NOT EXISTS idx_tasks_category ON tasks (category)');
await ditto.store.execute('CREATE INDEX IF NOT EXISTS idx_tasks_assignee ON tasks (assignee)');

// Query uses BOTH indexes via intersect scan
final result = await ditto.store.execute(
  "SELECT * FROM tasks WHERE category = 'urgent' AND assignee = 'user123'",
); // Intersects results from both indexes - efficiently narrows matches
```

### Query Plan Analysis with EXPLAIN

Use `EXPLAIN` to verify index usage:

```dart
// ✅ GOOD: Use EXPLAIN to verify query plan
final result = await ditto.store.execute(
  "EXPLAIN SELECT * FROM orders WHERE status = 'pending'",
);
// Check for "indexScan", "unionScan", or "intersectScan" operators in plan
```

### Index Limitations and Considerations

**Current Limitations:**

| Limitation | Description |
|------------|-------------|
| **Single field only** | Composite indexes on multiple fields not supported in current versions |
| **No partial indexes** | Cannot create indexes with WHERE conditions in current versions |
| **No functional indexes** | Cannot index computed values or expressions in current versions |
| **OR queries unsupported (4.12)** | SDK 4.12 cannot use indexes with OR; requires 4.13+ for union scans |
| **NOT operations** | Queries with NOT operators cannot use indexes in current versions |
| **Non-deterministic functions** | Cannot index results of functions like `CURRENT_TIMESTAMP()` in current versions |

**Supported Index Types:**
- ✅ Simple fields: `orders (status)`
- ✅ Nested fields: `users (address.city)`
- ✅ LIKE prefix patterns: `products (name LIKE 'Apple%')` (effective)
- ❌ LIKE suffix patterns: `products (name LIKE '%Phone')` (ineffective)

**Not Yet Supported** (potential future features):
- Composite indexes (multiple fields)
- Partial indexes with WHERE conditions
- Functional indexes
- Tombstone indexing
- Array and object field indexing

### Index Usage Best Practices

**✅ DO:**
- Create indexes on fields used in WHERE clauses for highly selective queries (<10% of documents)
- Create indexes on fields used in ORDER BY clauses
- Use `IF NOT EXISTS` during initialization for idempotent operations
- Batch index creation during application startup
- Monitor query performance with `EXPLAIN` before and after indexing
- Remove unused indexes to optimize write performance and storage

**❌ DON'T:**
- Create indexes without measuring performance impact
- Over-index collections (each index adds write overhead and storage cost)
- Create indexes on fields that return >50% of documents (minimal benefit)
- Assume indexes automatically improve all queries (measure with `EXPLAIN`)
- Create indexes in response to individual slow queries (analyze query patterns first)

**Why**: Indexes dramatically improve read performance for selective queries but add write overhead and storage cost. Strategic indexing based on actual query patterns and selectivity provides optimal balance.

**See Also**: [Operator Performance Considerations](#operator-performance-considerations) - Index support varies by operator (IN, LIKE prefix, starts_with can use indexes; ends_with, SIMILAR TO, object introspection cannot)

**Official Reference**: [Ditto DQL Indexing Documentation](https://docs.ditto.live/dql/indexing)

---

## Logging & Observability

### Log Levels

Ditto SDK provides four log levels for controlling console output and disk logging:

| Level | Use Case | Console | Disk (File Logging) |
|-------|----------|---------|---------------------|
| **DEBUG** | Development, troubleshooting | Configurable | Always enabled (default) |
| **INFO** | Normal operation, health monitoring | Configurable | Always enabled |
| **WARN** | Potential issues, recoverable errors | Configurable (default) | Always enabled |
| **ERROR** | Critical errors requiring attention | Configurable | Always enabled |

**Key Principle**: Console log level is configurable, but disk logging **always logs at DEBUG level** regardless of console settings, ensuring comprehensive diagnostics for remote troubleshooting.

### Configuring Log Levels

**✅ DO:**
- Set log level **before** initializing Ditto to capture startup issues (authentication, file system access)
- Use WARN level for production console output (default)
- Use DEBUG level temporarily for troubleshooting specific issues
- Enable DEBUG console logging during development for immediate feedback

```dart
// ✅ GOOD: Set log level before Ditto initialization (Flutter/Dart)
import 'package:ditto_flutter/ditto_flutter.dart';

void main() async {
  // Set log level BEFORE opening Ditto
  DittoLogger.minimumLogLevel = DittoLogLevel.debug;

  final ditto = await Ditto.open(
    identity: OnlinePlayground(appId: appId, token: token),
  );

  await ditto.startSync();
}
```

**❌ DON'T:**
- Set log level after Ditto initialization (may miss critical startup errors)
- Leave DEBUG console logging enabled in production (performance impact, log noise)
- Ignore log output during development

### Rotating File Logs

Ditto SDK includes **automatic log file rotation and compression** for disk-based logging:

**Configuration Parameters:**

| Parameter | Default | Range | Purpose |
|-----------|---------|-------|---------|
| `rotating_log_file_max_size_mb` | 1MB | 1MB-1GB | Triggers rotation when file reaches size limit |
| `rotating_log_file_max_age_h` | 24 hours | 1+ hours | Triggers rotation based on file age |
| `rotating_log_file_max_files_on_disk` | 15 files | 3-64 files | Maximum number of compressed log files retained |

**Features:**
- **Automatic compression**: Rotated files compress from `.log` to `.log.gz` (reduces disk usage by ~90%)
- **Background processing**: Compression occurs on separate thread without blocking operations
- **Crash recovery**: Uncompressed files from crashes are automatically compressed on next startup
- **Consistent DEBUG logging**: Disk logs always at DEBUG level, independent of console settings
- **File naming**: `ditto-logs-YYYY-MM-DD-HH-MM-SS.microseconds.log`

**Default Configuration Impact:**
- Disk usage: ~15MB (15 files × 1MB compressed)
- Retention: 24-hour rolling window per file

### Logging Best Practices

**Development:**

```dart
// ✅ GOOD: DEBUG console logging for development
DittoLogger.minimumLogLevel = DittoLogLevel.debug;
```

**Production:**

```dart
// ✅ GOOD: WARN/ERROR console logging for production
DittoLogger.minimumLogLevel = DittoLogLevel.warning;
// Note: Disk logging remains at DEBUG for diagnostics
```

**✅ DO:**
- Monitor INFO-level logs in production to understand SDK health and state
- Collect and analyze disk logs from devices for remote troubleshooting
- Use centralized log aggregation for production deployments
- Temporarily increase console log level to DEBUG when investigating specific issues
- Review connection lifecycle logs (transport started/ended, physical connections)

**❌ DON'T:**
- Run production with DEBUG console logging (performance overhead, excessive output)
- Ignore rotating log configuration in long-running applications
- Disable logging entirely (removes critical diagnostic capability)
- Log sensitive data (credentials, PII) in application code

**Why**: Ditto's logging system is designed for **remote observability and device diagnostics**. Disk logs at DEBUG level enable comprehensive troubleshooting of deployed devices, while configurable console logging reduces noise during normal operation.

### System Information Query

Ditto SDK 4.13.0+ provides a read-only `system:system_info` collection for runtime diagnostics:

```dart
// ✅ GOOD: Query current logging configuration
final result = await ditto.store.execute(
  "SELECT * FROM system:system_info WHERE namespace = 'logs'",
);

// Returns:
// - enabled: Whether logging is enabled
// - minimum_level: Current console log level (DEBUG, INFO, WARN, ERROR)
```

**⚠️ Note**: Observers on `system:system_info` execute every 500ms regardless of data changes. Consider performance implications on resource-constrained devices.

**Official Reference**: [Ditto SDK Logging Documentation](https://docs.ditto.live/sdk/latest/deployment/logging)

---

## Anti-Pattern Detection Checklist

### Immediate Rejection (CRITICAL)

- [ ] **Using mutable arrays for concurrent updates** (use MAP/object structures instead)
- [ ] Modifying individual array elements after creation (arrays should be append-only or read-only)
- [ ] Using DELETE without tombstone TTL strategy
- [ ] **Filtering deletion flags in subscriptions** (breaks multi-hop relay for soft-delete - subscriptions must include ALL documents, filter only in observers/queries)
- [ ] Forgetting to filter `isDeleted` in observers and execute() queries (if using logical deletion)
- [ ] Querying without active subscription (subscription = replication query)
- [ ] Full document replacement instead of field updates
- [ ] Using DO UPDATE instead of DO UPDATE_LOCAL_DIFF for upserts (SDK 4.12+) - causes unnecessary sync of unchanged fields
- [ ] Subscriptions/observers without cancel/cleanup (causes memory leaks)
- [ ] Using Online Playground identity in production environments
- [ ] Assuming attachments auto-sync (they require explicit fetch)
- [ ] **Using `registerObserver` for most use cases** (prefer `registerObserverWithSignalNext` for better performance - use `registerObserver` only for very simple data processing)
- [ ] Not calling `signalNext()` in `registerObserverWithSignalNext` callbacks
- [ ] Using legacy observeLocal without Differ migration (non-Flutter SDKs) - see [Replacing observeLocal](#replacing-legacy-observelocal-with-store-observers-sdk-412)
- [ ] Migrating DQL subscriptions before all peers on SDK v4.5+ (sync failures)
- [ ] Storing large binary data inline with documents (use ATTACHMENT type)
- [ ] Modifying existing attachments (they're immutable - replace token instead)
- [ ] **Retaining QueryResultItems in state/storage** (treat as database cursors, extract data immediately)
- [ ] **Nesting read-write transactions** (causes permanent deadlock - non-Flutter platforms only)
- [ ] Using `ditto.store` instead of transaction object within transaction blocks (non-Flutter platforms)
- [ ] **Running EVICT without canceling affected subscriptions** (causes resync loop)

### High-Priority Issues

- [ ] Over-normalized data structures requiring foreign key lookups (no JOIN support = sequential query overhead)
- [ ] Counter updates using set instead of increment
- [ ] Broad subscriptions without WHERE clauses
- [ ] No conflict testing in test suite
- [ ] Missing input validation before upsert
- [ ] Zombie data scenarios not considered
- [ ] Not handling attachment fetch errors gracefully
- [ ] Missing metadata when storing attachments
- [ ] Canceling attachment fetchers before completion
- [ ] Using DELETE for documents that may be updated concurrently (causes husked documents)
- [ ] Deleting 50,000+ documents at once without LIMIT (performance impact)
- [ ] Setting Edge SDK TTL larger than Cloud TTL (30 days)
- [ ] Not filtering out husked documents (null required fields) in queries
- [ ] Long-running operations inside transaction blocks (blocks other transactions)
- [ ] **Closing Ditto in Flutter without awaiting pending transactions** (must await all transactions before calling `ditto.close()`)
- [ ] Running EVICT more than once per day (causes excessive network traffic)
- [ ] Using same query for eviction and subscription (causes resync loop)
- [ ] Declaring subscriptions in local scope instead of top-level (cannot manage lifecycle)

### Medium-Priority Issues

- [ ] Updating fields with the same value (creates unnecessary deltas and sync traffic)
- [ ] Not using batch operations for related updates
- [ ] Inefficient query patterns
- [ ] Missing error handling for sync failures
- [ ] No strategy for large document handling
- [ ] Insufficient logging for sync events
- [ ] No storage management strategy (EVICT) for long-running apps
- [ ] Running EVICT during peak usage hours

---

## Quick Reference

**When implementing Ditto features:**

### API Usage (CRITICAL)
- ✅ **Use DQL string queries**: `ditto.store.execute(query, args)`
- ✅ **Avoid legacy builder API** (deprecated SDK 4.12+, removed in v5): `.collection()`, `.find()`, `.findById()`, `.update()`, `.upsert()`, `.remove()`, `.exec()` — **Note: Flutter SDK never had this legacy API**
- ✅ Use `ditto.sync.registerSubscription(query, args)` for subscriptions
- ✅ Prefer `ditto.store.registerObserverWithSignalNext(query, callback, args)` for observers (better performance, recommended for most use cases)
- ✅ **Legacy API migration**: See [Legacy API to DQL Quick Reference](#legacy-api-to-dql-quick-reference) for non-Flutter SDK migration
- ✅ **DQL subscriptions require SDK v4.5+ on all peers** - see [Forward-Compatibility](#dql-subscription-forward-compatibility-sdk-45)
- ✅ Reference official Ditto documentation before writing code

### Core Principles
- ✅ Design data models for distributed merge (CRDT-friendly)
- ✅ Understand offline-first: devices work independently and sync later
- ✅ Always consider how concurrent edits will merge

### Data Operations
- ✅ Use field-level UPDATE statements, not INSERT with DO UPDATE
- ✅ **CRITICAL: Check if values changed before UPDATE** - updating with the same value creates unnecessary deltas and sync traffic
- ✅ **RECOMMENDED: Use DO UPDATE_LOCAL_DIFF (SDK 4.12+)** for upserts - only syncs fields that differ from existing document
- ✅ **Use INITIAL DOCUMENTS for device-local templates and seed data** - prevents unnecessary sync traffic
- ✅ **CRITICAL: Use logical deletion for critical data** (avoid husked documents from concurrent DELETE/UPDATE)
- ✅ Understand tombstone TTL risks: ensure all devices connect within TTL window (Cloud: 30 days)
- ✅ **Warning: Tombstones only shared with devices that have seen the document before deletion**
- ✅ Use `LIMIT 30000` for batch deletions of 50,000+ documents (performance)
- ✅ Use counter operations (PN_INCREMENT or COUNTER type) for distributed counters, not SET operations
  - **Ditto <4.14.0**: Use PN_INCREMENT BY operator
  - **Ditto 4.14.0+**: Use COUNTER type (recommended for new implementations)
- ✅ **CRITICAL: Use separate documents (INSERT) for event logs and audit trails** - arrays are REGISTERS (last-write-wins)
- ✅ **Embed related data retrieved together** (no JOIN support = sequential query overhead); use flat models only for data accessed independently or growing unbounded
- ✅ **CRITICAL: Avoid mutable arrays** - use MAP (object) structures instead for concurrent updates
- ✅ Only embed read-only arrays that never change after creation
- ✅ Fetch attachments explicitly (they don't auto-sync with subscriptions)
- ✅ Keep documents under 250 KB (hard limit: 5 MB)
- ✅ Store large binary files (>250 KB) as ATTACHMENT type
- ✅ Balance embed vs flat based on access patterns: embed for data retrieved together, flat for independent access or unbounded growth
- ✅ Filter out husked documents by checking null required fields in queries

### Queries & Subscriptions
- ✅ Understand that queries without subscriptions return only local data (subscriptions tell peers what data to sync)
- ✅ Maintain subscriptions appropriately: avoid frequent start/stop cycles, but cancel when feature is disposed or before EVICT
- ✅ Use Local Store Observers for real-time updates (observers receive initial local data + synced updates)
- ✅ **CRITICAL: Logical Deletion Pattern** - Subscribe broadly (no deletion filter), filter only in observers/queries:
  - Subscriptions: `SELECT * FROM orders` (no `isDeleted` filter - enables multi-hop relay)
  - Observers: `SELECT * FROM orders WHERE isDeleted != true` (filters for UI display)
  - execute() queries: `SELECT * FROM orders WHERE isDeleted != true` (filters for app logic)
- ✅ Use specific WHERE clauses with parameterized arguments
- ✅ Cancel subscriptions and observers when feature is disposed to prevent memory leaks and notify peers

### Query Optimization & Indexing (SDK 4.12+)
- ✅ **Create indexes for highly selective queries** (<10% of documents) - ~90% faster performance
- ✅ Index fields used in WHERE and ORDER BY clauses
- ✅ Use `IF NOT EXISTS` when creating indexes during initialization (idempotent)
- ✅ Batch index creation during application startup, not on-demand at runtime
- ✅ Monitor indexes with `SELECT * FROM system:indexes`
- ✅ Use `EXPLAIN` to verify query plans and index usage
- ✅ Remove unused indexes (each index adds write overhead and storage cost)
- ✅ **SDK 4.13+**: Leverage union scans (OR, IN) and intersect scans (AND) with multiple indexes
- ✅ **CRITICAL: Treat QueryResults as database cursors** - extract data immediately, don't retain QueryResultItems
- ✅ Use `value` property for default format, `cborData()` for binary, `jsonString()` for JSON serialization
- ✅ Understand lazy-loading: items materialize only when accessed (memory efficiency)
- ✅ Use `DittoDiffer` to track changes (insertions, deletions, updates, moves) between query results
- ✅ **CRITICAL: Prefer `registerObserverWithSignalNext` for all observers** (better performance, recommended for most use cases)
- ✅ **CRITICAL: Keep observer callbacks lightweight** - extract data and update UI only; offload heavy processing to async operations
- ✅ Call `signalNext()` after render cycle completes to control backpressure
- ✅ Use `registerObserver()` only for very simple, synchronous data processing (worse performance)
- ✅ Understand delta sync: only field-level changes are transmitted

### Testing
- ✅ Test with multiple Ditto stores to simulate conflicts
- ✅ Test deletion scenarios (tombstones, logical deletion, zombie data, husked documents)
- ✅ Verify concurrent edits merge correctly
- ✅ Test array merge scenarios if using arrays

### Performance & Transactions
- ✅ **Transactions**: Use `ditto.store.transaction()` for atomic multi-step operations (Flutter: must await all transactions before closing Ditto instance)
- ✅ **CRITICAL**: Never nest read-write transactions (causes deadlock), keep transaction blocks fast (milliseconds, not seconds)
- ✅ **CRITICAL (Flutter)**: Always await all pending transactions before calling `ditto.close()` (SDK doesn't wait automatically)
- ✅ Optimize subscription scope with WHERE clauses
- ✅ Leverage delta sync for bandwidth efficiency

### Storage Management
- ✅ **CRITICAL: Cancel subscriptions before EVICT** - prevents resync loop where evicted data immediately resyncs
- ✅ Run EVICT once per day maximum (recommended) during low-usage periods (e.g., after hours)
- ✅ Use opposite queries for eviction and subscription (prevents conflicts)
- ✅ Declare subscriptions at top-level scope (enables lifecycle management)
- ✅ Use Big Peer (Cloud) TTL management when possible (centralized, prevents data loss)
- ✅ Implement time-based eviction for time-sensitive data (airlines: 72hr, retail: 7 days, QSR: 24hr)

### Attachments
- ✅ **CRITICAL: Fetch attachments explicitly** (they don't auto-sync with subscriptions)
- ✅ Use lazy-load pattern: fetch only when needed
- ✅ Store metadata with attachments (filename, size, type, description)
- ✅ Keep attachment fetchers active until completion
- ✅ Replace immutable attachments by creating new token and updating document

### Security
- ✅ Validate all inputs (Ditto is schema-less)
- ✅ Use proper identity configuration (Online with Authentication for production, not Online Playground)
- ✅ Define granular permissions using DQL-based permission queries
- ✅ Validate permissions at application level as additional security layer

### Logging & Observability
- ✅ **CRITICAL: Set log level BEFORE Ditto initialization** - captures authentication and file system startup issues
- ✅ Use WARN/ERROR console logging in production (default), DEBUG for development/troubleshooting
- ✅ Disk logging always runs at DEBUG level (independent of console settings) for remote diagnostics
- ✅ Monitor INFO-level logs in production to understand SDK health and connection state
- ✅ Collect and centralize disk logs from deployed devices for troubleshooting
- ✅ Review rotating log configuration for long-running applications (~15MB default)
- ✅ **CRITICAL: Balance subscription query scope** - too broad wastes resources, too narrow breaks multi-hop relay (intermediate peers can't relay documents they don't store)
- ✅ **CRITICAL: Exclude unnecessary fields from documents** - UI state, computed values, temp state shouldn't sync
- ✅ **CRITICAL: Design partial UI updates** - Observer callbacks should update only affected UI components, not entire screen

---

## Glossary

This glossary defines key Ditto-specific terms and concepts. For comprehensive definitions, see the [official Ditto glossary](https://docs.ditto.live/home/glossary).

### Core Concepts

**Application**: A logical namespace containing all data associated with your app. In Ditto, this is the top-level container for your documents and collections.

**Collection**: A grouping of documents under a name. Loosely equivalent to a table in SQL terms.

**Document**: A schema-flexible unit of data contained in a collection; analogous to a row in a table.

**Peer**: An instance of Ditto SDK running within an application. Each peer has a unique identity and participates in the mesh network independently.

**Device**: A physical hardware unit (smartphone, tablet, IoT device, etc.). A single device can host multiple peers when running multiple Ditto-enabled applications or multiple Ditto instances within one application.

**Small Peer**: A peer running on edge devices (mobile devices, IoT devices, embedded systems), as opposed to cloud infrastructure.

**Ditto Server**: Cloud cluster augmenting SDK capabilities with cloud sync, identity management, and monitoring features. Formerly called "Big Peer."

### CRDTs and Conflict Resolution

**CRDT (Conflict-Free Replicated Data Type)**: Data structure enabling concurrent updates across distributed peers without consensus requirements. CRDTs automatically merge conflicting changes based on mathematical properties.

**CRDT Types in Ditto:**
- **REGISTER**: Stores scalar values (strings, numbers, booleans) using last-write-wins strategy
- **MAP**: Stores object properties using add-wins strategy for automatic concurrent merge
- **Array**: Limited CRDT support - avoid for mutable data due to merge conflicts

**Actor**: An identifier used by CRDTs to track the source of data mutations, composed of a SiteID and the site's current epoch.

**Hybrid Logical Clock (HLC)**: Used to track when mutations occurred to a CRDT, combining a physical clock portion with a logical portion for ordering events.

**Version Vector**: Tracking mechanism for document state across peers. Each change increments the document version, enabling peers to determine if incoming changes are new.

**SiteID**: Unique peer identifier for CRDT document mutations, being phased out in favor of Peer Key.

**Peer Key**: A P-256 private key generated and persisted for each Ditto peer instance, serving as the primary unique identifier for that peer.

**Epoch**: A version identifier for peer CRDT knowledge, changing when peers perform data eviction.

### Sync and Networking

**Subscription**: Query expressing which data a peer requests from others for synchronization. Subscriptions tell Ditto what to sync.

**Local Store Observer**: Object monitoring database changes in the local store matching a given query over time, enabling real-time UI updates.

**Replication Query**: Query running on connected peers transmitting relevant changes back to the initiating peer.

**Delta Sync**: Bandwidth optimization technique where only field-level changes (not entire documents) are transmitted. ⚠️ Important: Even updating a field with the same value is treated as a change and synced as a delta. Minimizes network usage, especially important for battery-constrained devices and low-bandwidth connections.

**Transports**: Physical transport mechanisms (Bluetooth, WebSockets, AWDL, LAN) establishing secured peer connections.

**Mesh**: A network topology where peers connect directly to each other (peer-to-peer) without requiring a central server.

**Link**: Encrypted connection between non-directly-connected peers routed through intermediaries for multihop sync and Ditto Bus.

**Multiplexer**: Synchronous machine performing packet fragmentation and reassembly across multiple Physical Connections.

### Data Lifecycle

**Eviction**: Process for peers to deliberately forget data rather than permanently deleting it. Eviction is local-only and does not sync.

**Tombstone**: A deletion marker created when documents are deleted with `DELETE` DQL statements. Tombstones have TTL (Time To Live) and eventually expire.

**Logical Deletion**: Soft delete pattern where documents are marked as deleted (e.g., `isDeleted: true`) but not physically removed, avoiding zombie data problems.

**Zombie Data**: Deleted data that reappears from previously disconnected devices after tombstone TTL has expired.

### Identity and Security

**Identity**: Complex startup parameter defining authentication, peer verification, and Application identity confirmation modes.

**Certificate Authority (CA)**: The cryptographic root of trust for all identities and certificates within a Ditto Application.

**Identity Service**: Part of Ditto Server handling login requests and generating cryptographic authentication material.

**Online Playground**: Identity type where peers require no unique credentials and everyone has universal read-write access. Only for development/testing.

**Permission**: Specification of readable or writable documents for a peer, presented as collection names with DQL query lists.

**Authentication WebHook**: An HTTP service receiving credentials and responding with user metadata and permission information for dynamic certificate generation.

### Storage and Attachments

**Backend**: The underlying key-value store providing database-like persistence for Ditto.

**Attachment**: Component handling large binary file storage associated with documents, requiring explicit download separate from regular replication.

**Blob Store**: Internal component offering general blob storage for Ditto's persistent file needs.

### Advanced Features

**Bus**: Public service enabling raw byte streams between peers via the Ditto mesh for applications beyond document replication.

**Channel**: Bidirectional message-oriented data flow over Virtual Connections offering reliable or lossy delivery characteristics.

**Service**: Handles Channels providing specific functionality, with Replication Service performing document sync.

**Change Data Capture (CDC)**: System tracking data modifications for integration purposes.

**Presence Viewer**: Component building a picture of surrounding mesh peers including SDK versions and active transports.

### Deployment Models

**BYOC (Bring Your Own Cloud)**: Deployment model where customers share responsibility over their cloud account with Ditto.

**Portal**: Self-service website at https://portal.ditto.live for creating and managing cloud Applications.

### Protocols and Technologies

**DQL (Ditto Query Language)**: SQL-like query language for interacting with Ditto documents. See the [Query Language](#ditto-query-language-dql) section for details.

**AWDL (Apple Wireless Direct Link)**: A proprietary Apple-developed technology that establishes a point-to-point Wi-Fi connection between two Apple devices.

**Peer-to-Peer Wi-Fi**: Direct WiFi mechanisms between devices without routers, including AWDL and WiFi Aware technologies.

**L2CAP (Logical Link Control Adaptation Protocol)**: Faster Bluetooth LE transport mode at lower complexity than GATT, supporting ~20 kB/s speeds.

**GATT (Generic ATTribute Profile)**: An older, slower mode of Bluetooth LE data transfer which has typical speed of 3 to 6 kB/s.

**Ditto Routing Protocol**: Custom OSPF-like shortest-path-first interior routing protocol for multi-hop mesh packets.

---

## References

- [Ditto Official Documentation](https://docs.ditto.live/)
- [Ditto Glossary](https://docs.ditto.live/home/glossary)
- [Ditto Document Model](https://docs.ditto.live/key-concepts/document-model)
- [Ditto Syncing Data](https://docs.ditto.live/key-concepts/syncing-data)
- [Ditto CRUD: Read](https://docs.ditto.live/sdk/latest/crud/read)
- [Ditto CRUD: Delete](https://docs.ditto.live/sdk/latest/crud/delete)
- [Ditto CRUD: Transactions](https://docs.ditto.live/sdk/latest/crud/transactions)
- [Ditto CRUD: Working with Attachments](https://docs.ditto.live/sdk/latest/crud/working-with-attachments)
- [Ditto CRUD: Observing Data Changes](https://docs.ditto.live/sdk/v5/crud/observing-data-changes)
- [Ditto Sync: Device Storage Management](https://docs.ditto.live/sdk/latest/sync/device-storage-management)
- [Ditto Query Language (DQL)](https://docs.ditto.live/sdk/latest/query-language)
- [Ditto DQL Strict Mode](https://docs.ditto.live/dql/strict-mode)
- [Ditto Best Practices: Data Modeling](https://docs.ditto.live/best-practices/data-modeling)
- [Ditto SDK Reference](https://docs.ditto.live/sdk/latest/)
- [Understanding CRDTs](https://crdt.tech/)

---

## Disclaimer

This document provides best practices and recommendations based on our experience and understanding of Ditto SDK. While we strive to keep this information accurate and up-to-date, technology evolves rapidly, and your specific use case may differ.

We encourage you to:
- Always refer to the [official Ditto documentation](https://docs.ditto.live/) for the most current information
- Test thoroughly in your own environment before deploying to production
- Adapt these patterns to fit your specific requirements

This guide is provided "as is" for educational and reference purposes. We are not responsible for any issues that may arise from implementing these patterns in your projects. Your use of this information is at your own discretion and risk.

---

**Last Updated**: 2025-12-19
