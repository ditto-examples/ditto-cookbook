# Storage Lifecycle Deletion Patterns

This reference contains HIGH and MEDIUM priority patterns for data deletion, EVICT management, and storage optimization in Ditto. These patterns address common scenarios for managing document lifecycle.

## Table of Contents

- [Pattern 4: Husked Document Filtering](#pattern-4-husked-document-filtering)
- [Pattern 5: EVICT Frequency Limits](#pattern-5-evict-frequency-limits)
- [Pattern 6: Opposite Query Pattern for EVICT](#pattern-6-opposite-query-pattern-for-evict)
- [Pattern 7: Top-Level Subscription Declaration](#pattern-7-top-level-subscription-declaration)
- [Pattern 8: Batch Deletion with LIMIT](#pattern-8-batch-deletion-with-limit)
- [Pattern 9: Big Peer TTL Management](#pattern-9-big-peer-ttl-management)
- [Pattern 10: Time-Based Eviction Patterns](#pattern-10-time-based-eviction-patterns)

---

### 4. Husked Document Filtering (Priority: HIGH)

**Problem**: Concurrent DELETE operations from Device A and UPDATE operations from Device B create "husked documents" containing only system fields (`_id`, `_meta`). These appear in query results and can cause UI issues.

**Detection**:
```dart
// Query returns husked documents
final result = await ditto.store.execute('SELECT * FROM tasks');

for (final item in result.items) {
  final taskName = item.value['name'];  // May be null if husked!
  if (taskName == null) {
    // Husked document detected
  }
}
```

### Solution: Filter Out Husked Documents

```dart
// ✅ GOOD: Filter out husked documents
final result = await ditto.store.execute(
  'SELECT * FROM tasks WHERE name IS NOT NULL'
);
// Only returns documents with actual data
```

### Why Husked Documents Occur

**Concurrent operations**:
- Device A: `DELETE FROM tasks WHERE _id = '123'`
- Device B: `UPDATE tasks SET priority = 'high' WHERE _id = '123'`

**After sync**:
- DELETE removes all fields except `_id`, `_meta`
- UPDATE adds `priority` field to deleted document
- Result: `{"_id": "123", "_meta": {...}, "priority": "high"}` (husked - missing other fields)

### Filtering Strategies

**Option 1: Field-Level Filtering** (Recommended):
```dart
// Filter by required fields
'SELECT * FROM tasks WHERE name IS NOT NULL AND status IS NOT NULL'
```

**Option 2: Logical Deletion Filtering**:
```dart
// If using isDeleted pattern
'SELECT * FROM tasks WHERE isDeleted != true'
```

**Option 3: Client-Side Filtering** (Last resort):
```dart
final items = result.items.where((item) {
  final value = item.value;
  return value.containsKey('name') && value.containsKey('status');
}).toList();
```

### Trade-offs

| Approach | Performance | Safety | Complexity |
|----------|------------|--------|------------|
| Field-level WHERE | ✅ Fast (server-side) | ✅ Guaranteed | ✅ Simple |
| Logical deletion | ✅ Fast (server-side) | ⚠️ Requires pattern | ⚠️ Additional field |
| Client-side | ❌ Slower | ✅ Flexible | ⚠️ More code |

- `../SKILL.md` Pattern 3: Logical Deletion Pattern
- 

---

### 5. EVICT Frequency Limits (Priority: HIGH)

**Problem**: Calling `EVICT` too frequently (e.g., on every query change) wastes CPU and battery. Ditto recommends EVICT at most once every few minutes.

**Detection**:
```dart
// ❌ BAD: EVICT on every observer callback
ditto.store.registerObserver(
  'SELECT * FROM tasks'
  onChange: (result) async {
    updateUI(result);

    // EVICT runs on every data change!
    await ditto.store.execute(
      'EVICT FROM tasks WHERE completedAt < :threshold'
      arguments: {'threshold': thirtyDaysAgo}
    );
  }
);
```

### Solution: Throttle EVICT Operations

```dart
// ✅ GOOD: EVICT with periodic throttling
class EvictionManager {
  DateTime? _lastEviction;
  static const _evictionInterval = Duration(minutes: 5);

  Future<void> evictIfNeeded(Ditto ditto) async {
    final now = DateTime.now();

    if (_lastEviction == null ||
        now.difference(_lastEviction!) > _evictionInterval) {
      await ditto.store.execute(
        'EVICT FROM tasks WHERE completedAt < :threshold'
        arguments: {
          'threshold': DateTime.now()
            .subtract(Duration(days: 30))
            .toIso8601String()
        }
      );
      _lastEviction = now;
    }
  }
}

// Use in observer
ditto.store.registerObserver(
  'SELECT * FROM tasks'
  onChange: (result) async {
    updateUI(result);
    await evictionManager.evictIfNeeded(ditto);  // Throttled
  }
);
```

### Recommended Intervals

| Use Case | Interval | Reason |
|----------|----------|--------|
| **High-traffic apps** | 5-10 minutes | Reduce overhead |
| **Background sync** | 1-5 minutes | More frequent cleanup |
| **Low-traffic apps** | 10-30 minutes | Less frequent data changes |
| **Manual trigger** | User-initiated | Explicit control |

### Alternative Patterns

**Option 2: Scheduled Background Task** (Recommended for mobile):
```dart
// Run EVICT in background task (e.g., WorkManager, BackgroundFetch)
void scheduleEviction() {
  Workmanager().registerPeriodicTask(
    'eviction-task'
    'evictionTask'
    frequency: Duration(hours: 1),  // Platform-specific minimum
  );
}

void evictionTask() async {
  final ditto = await Ditto.open(store);
  await ditto.store.execute(
    'EVICT FROM tasks WHERE completedAt < :threshold'
    arguments: {'threshold': thirtyDaysAgo}
  );
}
```

**Option 3: App Lifecycle Trigger**:
```dart
// EVICT on app background/resume
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    evictionManager.evictIfNeeded(ditto);
  }
}
```

- `../SKILL.md` Pattern 2: EVICT Without Subscription Cancellation
- 

---

### 6. Opposite Query Pattern for EVICT (Priority: HIGH)

**Problem**: EVICT queries should be the logical opposite of subscription queries. If subscription query is complex, EVICT query must match to avoid re-syncing evicted documents.

**Detection**:
```dart
// Subscription: Get active tasks
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM tasks WHERE status = :status AND priority >= :priority'
  arguments: {'status': 'active', 'priority': 5}
);

// ❌ BAD: EVICT query doesn't match subscription logic
await ditto.store.execute(
  'EVICT FROM tasks WHERE status != :status'
  arguments: {'status': 'active'}
);
// Problem: Evicts tasks with priority < 5 that should be synced!
```

### Solution: Match EVICT to Subscription

```dart
// ✅ GOOD: EVICT is logical opposite of subscription
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM tasks WHERE status = :status AND priority >= :priority'
  arguments: {'status': 'active', 'priority': 5}
);

// EVICT: Opposite condition
await ditto.store.execute(
  'EVICT FROM tasks WHERE status != :status OR priority < :priority'
  arguments: {'status': 'active', 'priority': 5}
);
// Correctly evicts tasks not matching subscription
```

### Complex Query Examples

**Subscription with multiple conditions**:
```dart
// Subscription
'SELECT * FROM orders WHERE (status = :status1 OR status = :status2) AND userId = :userId'

// Matching EVICT
'EVICT FROM orders WHERE (status != :status1 AND status != :status2) OR userId != :userId'
```

**Subscription with date range**:
```dart
// Subscription
'SELECT * FROM events WHERE timestamp >= :startDate AND timestamp <= :endDate'

// Matching EVICT
'EVICT FROM events WHERE timestamp < :startDate OR timestamp > :endDate'
```

### Why This Matters

If EVICT query is broader than subscription:
- ✅ Safe - Evicts only unsubscribed documents
- ⚠️ May leave some documents in store

If EVICT query is narrower than subscription:
- ❌ Dangerous - Re-syncs evicted documents
- ❌ Wastes bandwidth and storage

- `../SKILL.md` Pattern 2: EVICT Without Subscription Cancellation
- 

---

### 7. Top-Level Subscription Declaration (Priority: HIGH)

**Problem**: Creating subscriptions inside observer callbacks causes subscription churn (repeated cancel/recreate), wasting resources.

**Detection**:
```dart
// ❌ BAD: Subscription inside observer
ditto.store.registerObserver(
  'SELECT * FROM users WHERE _id = :userId'
  arguments: {'userId': currentUserId}
  onChange: (result) async {
    final user = result.items.first.value;

    // Subscription recreated on every observer callback!
    final tasksSub = ditto.sync.registerSubscription(
      'SELECT * FROM tasks WHERE userId = :userId'
      arguments: {'userId': user['_id']}
    );
  }
);
```

### Solution: Declare Subscriptions at Top Level

```dart
// ✅ GOOD: Subscriptions declared once
class TasksManager {
  DittoSyncSubscription? _userSubscription;
  DittoSyncSubscription? _tasksSubscription;
  DittoStoreObserver? _observer;

  void initialize(String userId) {
    // Create subscriptions once
    _userSubscription = ditto.sync.registerSubscription(
      'SELECT * FROM users WHERE _id = :userId'
      arguments: {'userId': userId}
    );

    _tasksSubscription = ditto.sync.registerSubscription(
      'SELECT * FROM tasks WHERE userId = :userId'
      arguments: {'userId': userId}
    );

    // Observer only updates UI
    _observer = ditto.store.registerObserver(
      'SELECT * FROM tasks WHERE userId = :userId'
      arguments: {'userId': userId}
      onChange: (result) {
        updateUI(result);  // No subscription logic here
      }
    );
  }

  void dispose() {
    _userSubscription?.cancel();
    _tasksSubscription?.cancel();
    _observer?.cancel();
  }
}
```

### When Subscription Changes Are Needed

**Dynamic subscriptions** (user changes filters):
```dart
// ✅ ACCEPTABLE: Recreate subscription when filter changes
void updateFilter(String newStatus) {
  _subscription?.cancel();  // Cancel old subscription
  _subscription = ditto.sync.registerSubscription(
    'SELECT * FROM tasks WHERE status = :status'
    arguments: {'status': newStatus}
  );
}
```

### Trade-offs

| Approach | Subscription Churn | Code Complexity | Use Case |
|----------|-------------------|-----------------|----------|
| Top-level (static) | ✅ None | ✅ Simple | Fixed queries |
| Top-level (dynamic) | ⚠️ On filter change | ⚠️ Moderate | User-driven filters |
| Inside observer | ❌ High | ❌ Complex | ❌ Avoid |

- `../../query-sync/SKILL.md` Pattern 3: Uncanceled Subscriptions
- 

---

### 8. Batch Deletion with LIMIT (Priority: MEDIUM)

**Problem**: Deleting thousands of documents in a single query can block the main thread and cause UI freezes.

**Detection**:
```dart
// ❌ BAD: Delete all at once (could be 10,000+ documents)
await ditto.store.execute(
  'DELETE FROM logs WHERE timestamp < :threshold'
  arguments: {'threshold': thirtyDaysAgo}
);
// Blocks UI for seconds if dataset is large
```

### Solution: Batch Deletion with LIMIT

```dart
// ✅ GOOD: Batch deletion with LIMIT
Future<void> batchDelete(Ditto ditto, String threshold) async {
  const batchSize = 100;
  var deletedCount = 0;

  do {
    final result = await ditto.store.execute(
      'DELETE FROM logs WHERE timestamp < :threshold LIMIT :limit'
      arguments: {'threshold': threshold, 'limit': batchSize}
    );

    deletedCount = result.mutatedDocumentIDs.length;

    // Yield to UI thread between batches
    await Future.delayed(Duration(milliseconds: 10));
  } while (deletedCount == batchSize);
}
```

### Batch Size Recommendations

| Document Complexity | Batch Size | Reason |
|--------------------|-----------|--------|
| **Simple documents** (<10 fields) | 100-500 | Fast per-doc deletion |
| **Complex documents** (>10 fields) | 50-100 | More processing per doc |
| **Very large documents** (>100 KB) | 10-50 | Significant I/O per doc |

### Alternative Patterns

**Option 2: Background Task** (Recommended for large datasets):
```dart
// Run batch deletion in background isolate (Flutter)
Future<void> deleteLargeDataset() async {
  await compute(_batchDeleteIsolate, {
    'threshold': thirtyDaysAgo
    'batchSize': 100
  });
}

void _batchDeleteIsolate(Map<String, dynamic> params) async {
  // Perform batch deletion without blocking main thread
  final ditto = await Ditto.open(store);
  await batchDelete(ditto, params['threshold']);
}
```

**Option 3: Progress Reporting**:
```dart
Stream<int> batchDeleteWithProgress(Ditto ditto, String threshold) async* {
  const batchSize = 100;
  var totalDeleted = 0;

  while (true) {
    final result = await ditto.store.execute(
      'DELETE FROM logs WHERE timestamp < :threshold LIMIT :limit'
      arguments: {'threshold': threshold, 'limit': batchSize}
    );

    final deletedCount = result.mutatedDocumentIDs.length;
    totalDeleted += deletedCount;

    yield totalDeleted;  // Emit progress

    if (deletedCount < batchSize) break;
    await Future.delayed(Duration(milliseconds: 10));
  }
}

// Usage
await for (final count in batchDeleteWithProgress(ditto, threshold)) {
  updateProgressUI(count);
}
```

- 

---

### 9. Big Peer TTL Management (Priority: MEDIUM)

**Problem**: Big Peer stores all documents by default. Setting TTL policies ensures automatic cleanup without manual EVICT.

**Background**: Big Peer is Ditto's cloud-based peer that synchronizes data across devices. Unlike mobile peers with limited storage, Big Peer has abundant storage but still benefits from TTL policies for data hygiene.

### Solution: Configure Big Peer TTL

**Via Ditto Portal**:
1. Navigate to your app in Ditto Portal
2. Go to Collections → Select collection
3. Configure TTL policy:
   - **Field**: `deletedAt` (or `completedAt`, `expiresAt`)
   - **Duration**: Time after field value (e.g., 30 days)
   - **Action**: DELETE (removes document permanently)

**Example TTL Policies**:

| Use Case | Field | Duration | Reason |
|----------|-------|----------|--------|
| **Soft-deleted tasks** | `deletedAt` | 30 days | Grace period for recovery |
| **Completed orders** | `completedAt` | 90 days | Regulatory compliance |
| **Temporary sessions** | `expiresAt` | 1 day | Short-lived data |
| **Log entries** | `timestamp` | 7 days | Recent logs only |

### How TTL Works

**Client-side**:
```dart
// Mark document for TTL deletion
await ditto.store.execute(
  'UPDATE tasks SET deletedAt = :timestamp WHERE _id = :id'
  arguments: {
    'id': taskId
    'timestamp': DateTime.now().toIso8601String()
  }
);
// Big Peer deletes after TTL expires
```

**Big Peer behavior**:
- Checks TTL policies periodically (typically every few minutes)
- Deletes documents when `field + duration < now`
- Deletion syncs to all peers via tombstone mechanism

### Benefits

- ✅ Automatic cleanup (no manual EVICT scripts)
- ✅ Consistent across all peers
- ✅ Reduces Big Peer storage costs
- ✅ Enforces data retention policies

### Limitations

- ⚠️ TTL configured via Portal (not programmatically)
- ⚠️ Minimum duration is typically 1 hour
- ⚠️ Deletion is asynchronous (not immediate)

- Ditto Portal documentation: [portal.ditto.live](https://portal.ditto.live)
- `../SKILL.md` Pattern 1: DELETE Without Tombstone TTL Strategy

---

### 10. Time-Based Eviction Patterns (Priority: MEDIUM)

**Problem**: Storing unbounded historical data causes storage bloat. Time-based eviction maintains a rolling window of recent data.

### Solution Options

#### Option 1: EVICT with Date Threshold (Recommended)

```dart
// ✅ GOOD: EVICT documents older than 30 days
Future<void> evictOldDocuments(Ditto ditto) async {
  final threshold = DateTime.now()
    .subtract(Duration(days: 30))
    .toIso8601String();

  await ditto.store.execute(
    'EVICT FROM events WHERE timestamp < :threshold'
    arguments: {'threshold': threshold}
  );
}

// Run periodically (e.g., daily)
Timer.periodic(Duration(days: 1), (_) => evictOldDocuments(ditto));
```

#### Option 2: EVICT with Record Count Limit

```dart
// ✅ GOOD: Keep only latest 1000 records per user
Future<void> evictExcessRecords(Ditto ditto, String userId) async {
  // Query to get timestamp of 1000th record
  final threshold = await ditto.store.execute(
    '''
    SELECT timestamp FROM events
    WHERE userId = :userId
    ORDER BY timestamp DESC
    LIMIT 1 OFFSET 999
    '''
    arguments: {'userId': userId}
  );

  if (threshold.items.isEmpty) return;  // Less than 1000 records

  final cutoffTime = threshold.items.first.value['timestamp'];

  // Evict records older than cutoff
  await ditto.store.execute(
    '''
    EVICT FROM events
    WHERE userId = :userId AND timestamp < :cutoff
    '''
    arguments: {'userId': userId, 'cutoff': cutoffTime}
  );
}
```

#### Option 3: Hybrid Approach (Date + Count)

```dart
// ✅ BEST: Keep latest 1000 OR last 30 days (whichever is more)
Future<void> evictWithHybridPolicy(Ditto ditto, String userId) async {
  final dateThreshold = DateTime.now()
    .subtract(Duration(days: 30))
    .toIso8601String();

  // Get 1000th record timestamp
  final countResult = await ditto.store.execute(
    '''
    SELECT timestamp FROM events
    WHERE userId = :userId
    ORDER BY timestamp DESC
    LIMIT 1 OFFSET 999
    '''
    arguments: {'userId': userId}
  );

  String evictThreshold;

  if (countResult.items.isEmpty) {
    // Less than 1000 records, use date only
    evictThreshold = dateThreshold;
  } else {
    final countCutoff = countResult.items.first.value['timestamp'] as String;
    // Use whichever is older (keeps more data)
    evictThreshold = countCutoff.compareTo(dateThreshold) < 0
      ? countCutoff
      : dateThreshold;
  }

  await ditto.store.execute(
    '''
    EVICT FROM events
    WHERE userId = :userId AND timestamp < :threshold
    '''
    arguments: {'userId': userId, 'threshold': evictThreshold}
  );
}
```

### Use Case Recommendations

| Use Case | Pattern | Threshold | Reason |
|----------|---------|-----------|--------|
| **Chat messages** | Date-based | 90 days | Users expect recent history |
| **Activity logs** | Date-based | 30 days | Audit requirements |
| **Analytics events** | Count-based | Latest 10K | Fixed storage budget |
| **Feed items** | Hybrid | 1000 or 7 days | Balance recency and quantity |

### Scheduling Strategies

**Daily cleanup** (Recommended):
```dart
Timer.periodic(Duration(days: 1), (_) => evictOldDocuments(ditto));
```

**On app background**:
```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    evictOldDocuments(ditto);
  }
}
```

**Manual trigger** (Settings screen):
```dart
ElevatedButton(
  onPressed: () => evictOldDocuments(ditto)
  child: Text('Clear Old Data')
);
```

- Pattern 5: EVICT Frequency Limits
- 

---

## Further Reading

- **SKILL.md**: Critical patterns (Tier 1)
- **Main Guide**: `.claude/guides/best-practices/ditto.md`
- **Related Skills**:
  - `query-sync/SKILL.md`: Subscription management
  - `data-modeling/SKILL.md`: Document lifecycle design
