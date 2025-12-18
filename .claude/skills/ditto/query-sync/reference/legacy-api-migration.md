# Legacy API Migration Guide

**Target Audience**: JavaScript, Swift, and Kotlin developers migrating from SDK versions < 4.12

**NOT APPLICABLE**: Flutter SDK (Flutter never had the legacy builder API)

---

## Overview

The Ditto SDK underwent a major API evolution from builder-based methods to DQL (Ditto Query Language) string-based queries:

- **Legacy Builder API**: Deprecated in SDK 4.12 (2023), removed in SDK v5 (2024)
- **Current DQL API**: Introduced in SDK 4.8, now the only supported method
- **Migration Timeline**: All non-Flutter projects must migrate to DQL API

---

## Why the Migration?

### Problems with Legacy Builder API

1. **Type Safety Issues**: Runtime errors from incorrect query construction
2. **Limited Query Capabilities**: Complex queries were impossible or cumbersome
3. **Platform Inconsistencies**: Different behavior across platforms
4. **Poor Performance**: Inefficient query compilation
5. **Maintenance Burden**: Two parallel APIs created confusion

### Benefits of DQL API

1. **SQL Familiarity**: Developers familiar with SQL can quickly learn DQL
2. **Powerful Queries**: Complex queries, aggregations, and joins-like patterns
3. **Consistent Behavior**: Same query syntax across all platforms
4. **Better Performance**: Optimized query execution engine
5. **Future-Proof**: All new features target DQL only

---

## Platform-Specific Migration Status

### Flutter (Dart)

**Status**: ✅ No migration needed

Flutter SDK **never had the legacy builder API**. All Flutter code has always used DQL.

```dart
// Flutter has ALWAYS used this API:
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);
```

### JavaScript

**Status**: ⚠️ Migration required (if using SDK < 4.12)

**Legacy API (DEPRECATED)**:
```javascript
// ❌ DEPRECATED - Will not work in SDK v5+
const orders = await ditto.store
  .collection('orders')
  .find("status == 'active'")
  .exec();
```

**Current DQL API**:
```javascript
// ✅ CURRENT - Use this
const result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status',
  { arguments: { status: 'active' } }
);

const orders = result.items.map(item => item.value);
```

### Swift

**Status**: ⚠️ Migration required (if using SDK < 4.12)

**Legacy API (DEPRECATED)**:
```swift
// ❌ DEPRECATED - Will not work in SDK v5+
let orders = try ditto.store
  .collection("orders")
  .find("status == 'active'")
  .exec()
```

**Current DQL API**:
```swift
// ✅ CURRENT - Use this
let result = try await ditto.store.execute(
  query: "SELECT * FROM orders WHERE status = :status",
  arguments: ["status": "active"]
)

let orders = result.items.map { $0.value }
```

### Kotlin

**Status**: ⚠️ Migration required (if using SDK < 4.12)

**Legacy API (DEPRECATED)**:
```kotlin
// ❌ DEPRECATED - Will not work in SDK v5+
val orders = ditto.store
  .collection("orders")
  .find("status == 'active'")
  .exec()
```

**Current DQL API**:
```kotlin
// ✅ CURRENT - Use this
val result = ditto.store.execute(
  "SELECT * FROM orders WHERE status = :status",
  mapOf("status" to "active")
)

val orders = result.items.map { it.value }
```

---

## Common Migration Patterns

### Quick Reference Tables

For a comprehensive CRUD operation mapping table, see:
- **[Legacy API to DQL Quick Reference](.claude/guides/best-practices/ditto.md#legacy-api-to-dql-quick-reference)** - Systematic method-by-method mapping with SDK version requirements

For observer migration with DittoDiffer pattern, see:
- **[Replacing Legacy observeLocal](.claude/guides/best-practices/ditto.md#replacing-legacy-observelocal-with-store-observers-sdk-412)** - Complete pattern for migrating from `observeLocal` event handling

For deployment constraints when using DQL subscriptions, see:
- **[DQL Subscription Forward-Compatibility](.claude/guides/best-practices/ditto.md#dql-subscription-forward-compatibility-sdk-45)** - Critical SDK v4.5+ requirements for all peers

---

### Pattern 1: Basic Find Query

**Before (Legacy)**:
```javascript
const products = await ditto.store
  .collection('products')
  .find("isActive == true")
  .exec();
```

**After (DQL)**:
```javascript
const result = await ditto.store.execute(
  'SELECT * FROM products WHERE isActive = true'
);

const products = result.items.map(item => item.value);
```

**Key Changes**:
- `collection()` → `FROM`
- `find()` → `WHERE`
- `exec()` → `execute()`
- Extract data with `.items.map(item => item.value)`

---

### Pattern 2: Find by ID

**Before (Legacy)**:
```javascript
const order = await ditto.store
  .collection('orders')
  .findByID('order_123')
  .exec();
```

**After (DQL)**:
```javascript
const result = await ditto.store.execute(
  'SELECT * FROM orders WHERE _id = :id',
  { arguments: { id: 'order_123' } }
);

const order = result.items.length > 0 ? result.items[0].value : null;
```

**Key Changes**:
- `findByID()` → `WHERE _id = :id` with parameterized query
- Handle empty results explicitly

---

### Pattern 3: Find with Complex Condition

**Before (Legacy)**:
```javascript
const orders = await ditto.store
  .collection('orders')
  .find("status == 'pending' AND totalAmount > 100")
  .exec();
```

**After (DQL)**:
```javascript
const result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status AND totalAmount > :amount',
  { arguments: { status: 'pending', amount: 100 } }
);

const orders = result.items.map(item => item.value);
```

**Key Changes**:
- `AND` operator remains the same
- Use parameterized queries for values
- DQL uses `=` instead of `==` for equality

---

### Pattern 4: Upsert

**Before (Legacy)**:
```javascript
await ditto.store
  .collection('products')
  .upsert({
    _id: 'product_123',
    name: 'Widget',
    price: 29.99
  });
```

**After (DQL)**:
```javascript
await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)',
  {
    arguments: {
      product: {
        _id: 'product_123',
        name: 'Widget',
        price: 29.99
      }
    }
  }
);
```

**Key Changes**:
- `upsert()` → `INSERT INTO ... DOCUMENTS`
- Pass document as named parameter

---

### Pattern 5: Update

**Before (Legacy)**:
```javascript
await ditto.store
  .collection('orders')
  .findByID('order_123')
  .update(updater => {
    updater.set('status', 'completed');
  });
```

**After (DQL)**:
```javascript
await ditto.store.execute(
  'UPDATE orders SET status = :status WHERE _id = :id',
  {
    arguments: {
      id: 'order_123',
      status: 'completed'
    }
  }
);
```

**Key Changes**:
- Explicit `UPDATE ... SET ... WHERE` syntax
- No callback-based updater
- All changes in single statement

---

### Pattern 6: Remove/Delete

**Before (Legacy)**:
```javascript
await ditto.store
  .collection('orders')
  .findByID('order_123')
  .remove();
```

**After (DQL)**:
```javascript
// Option 1: DELETE (creates tombstone)
await ditto.store.execute(
  'DELETE FROM orders WHERE _id = :id',
  { arguments: { id: 'order_123' } }
);

// Option 2: EVICT (removes from local store, no tombstone)
await ditto.store.execute(
  'EVICT FROM orders WHERE _id = :id',
  { arguments: { id: 'order_123' } }
);
```

**Key Changes**:
- `remove()` → `DELETE` or `EVICT`
- Choose based on tombstone requirements

---

### Pattern 7: Observe (Real-time Updates)

**Before (Legacy)**:
```javascript
const liveQuery = ditto.store
  .collection('orders')
  .find("status == 'active'")
  .observeLocal((orders, event) => {
    console.log('Orders updated:', orders);
  });

// Cancel later
liveQuery.stop();
```

**After (DQL)**:
```javascript
// Step 1: Register subscription (mesh sync)
const subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE status = :status',
  { arguments: { status: 'active' } }
);

// Step 2: Register observer (local changes)
const observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders WHERE status = :status',
  { arguments: { status: 'active' } },
  (result, signalNext) => {
    const orders = result.items.map(item => item.value);
    console.log('Orders updated:', orders);
    signalNext(); // Signal ready for next update
  }
);

// Cancel later (in reverse order)
observer.cancel();
subscription.cancel();
```

**Key Changes**:
- `observeLocal()` → separate `registerSubscription()` + `registerObserverWithSignalNext()`
- Two-step pattern: subscription for sync, observer for local changes
- Must call `signalNext()` for backpressure control
- Cancel in reverse order

---

## Migration Checklist

### Pre-Migration

- [ ] **Check SDK Version**: Confirm you're using SDK 4.12+ (check package.json/build.gradle/Package.swift)
- [ ] **Inventory Legacy API Usage**: Search codebase for:
  - `.collection(`
  - `.find(`
  - `.findByID(`
  - `.upsert(`
  - `.update(`
  - `.remove(`
  - `.observeLocal(`
  - `.exec(`
- [ ] **Review Test Coverage**: Ensure queries have test coverage for regression detection
- [ ] **Read DQL Documentation**: Familiarize team with DQL syntax

### During Migration

- [ ] **Migrate One Collection at a Time**: Don't refactor everything at once
- [ ] **Add Integration Tests**: Test migrated queries against real Ditto instance
- [ ] **Use Parameterized Queries**: Prevent SQL injection-like vulnerabilities
- [ ] **Extract QueryResultItems Immediately**: Avoid memory leaks (see query-result-handling-good.dart)
- [ ] **Update Observer Patterns**: Use `registerObserverWithSignalNext` for backpressure
- [ ] **Handle Subscriptions Properly**: Register + cancel in correct lifecycle

### Post-Migration

- [ ] **Remove Legacy API Calls**: Delete all deprecated methods
- [ ] **Update Documentation**: Document new query patterns for team
- [ ] **Performance Testing**: Verify query performance (DQL should be faster)
- [ ] **Monitor for Issues**: Watch for runtime errors in production
- [ ] **Upgrade to SDK v5+**: Legacy API completely removed in v5

---

## Query Syntax Comparison

### Equality

| Legacy | DQL |
|--------|-----|
| `find("status == 'active'")` | `WHERE status = 'active'` |

**Note**: DQL uses single `=` for equality (like SQL), not `==`

### Inequality

| Legacy | DQL |
|--------|-----|
| `find("price > 100")` | `WHERE price > 100` |
| `find("quantity != 0")` | `WHERE quantity != 0` |

### Logical Operators

| Legacy | DQL |
|--------|-----|
| `find("status == 'active' AND price > 100")` | `WHERE status = 'active' AND price > 100` |
| `find("status == 'active' OR status == 'pending'")` | `WHERE status = 'active' OR status = 'pending'` |

**Better**: Use `IN` for multiple values
```sql
WHERE status IN ('active', 'pending')
```

### Nested Fields

| Legacy | DQL |
|--------|-----|
| `find("address.city == 'Tokyo'")` | `WHERE address.city = 'Tokyo'` |

### Array Contains (CONTAINS)

| Legacy | DQL |
|--------|-----|
| `find("CONTAINS(tags, 'urgent')")` | `WHERE 'urgent' IN tags` |

---

## Common Migration Pitfalls

### Pitfall 1: Retaining QueryResultItems

**Problem**:
```javascript
// ❌ BAD: Storing QueryResultItems causes memory leak
class OrdersService {
  constructor() {
    this.queryResult = null; // Don't store entire QueryResult!
  }

  async loadOrders() {
    this.queryResult = await ditto.store.execute('SELECT * FROM orders');
  }
}
```

**Solution**:
```javascript
// ✅ GOOD: Extract data immediately
class OrdersService {
  constructor() {
    this.orders = []; // Store plain data
  }

  async loadOrders() {
    const result = await ditto.store.execute('SELECT * FROM orders');
    this.orders = result.items.map(item => item.value); // Extract!
  }
}
```

### Pitfall 2: Not Calling signalNext()

**Problem**:
```javascript
// ❌ BAD: Missing signalNext() blocks observer
const observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders',
  (result, signalNext) => {
    const orders = result.items.map(item => item.value);
    console.log(orders);
    // Missing signalNext()! Observer will block after first callback
  }
);
```

**Solution**:
```javascript
// ✅ GOOD: Always call signalNext()
const observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders',
  (result, signalNext) => {
    const orders = result.items.map(item => item.value);
    console.log(orders);
    signalNext(); // CRITICAL: Signal ready for next update
  }
);
```

### Pitfall 3: Using == Instead of = in DQL

**Problem**:
```javascript
// ❌ BAD: DQL doesn't use == for equality
const result = await ditto.store.execute(
  "SELECT * FROM orders WHERE status == 'active'" // Syntax error!
);
```

**Solution**:
```javascript
// ✅ GOOD: Use single = for equality
const result = await ditto.store.execute(
  "SELECT * FROM orders WHERE status = 'active'"
);
```

### Pitfall 4: Not Canceling Subscriptions

**Problem**:
```javascript
// ❌ BAD: Subscription and observer never canceled - memory leak
function setupOrders() {
  ditto.sync.registerSubscription('SELECT * FROM orders');
  ditto.store.registerObserverWithSignalNext(
    'SELECT * FROM orders',
    (result, signalNext) => {
      // Process...
      signalNext();
    }
  );
  // No references stored, can't cancel!
}
```

**Solution**:
```javascript
// ✅ GOOD: Store references and cancel in cleanup
class OrdersService {
  constructor(ditto) {
    this.ditto = ditto;
    this.subscription = null;
    this.observer = null;
  }

  initialize() {
    this.subscription = this.ditto.sync.registerSubscription('SELECT * FROM orders');
    this.observer = this.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      (result, signalNext) => {
        // Process...
        signalNext();
      }
    );
  }

  dispose() {
    // Cancel in reverse order
    if (this.observer) this.observer.cancel();
    if (this.subscription) this.subscription.cancel();
  }
}
```

---

## SDK Version Detection

### JavaScript

```javascript
import pkg from 'ditto/package.json';

const version = pkg.version;
console.log('Ditto SDK version:', version);

if (version.startsWith('4.') && parseInt(version.split('.')[1]) < 12) {
  console.warn('Please upgrade to SDK 4.12+ to use DQL API');
}
```

### Swift

```swift
// Check SDK version at compile time
#if DITTO_SDK_VERSION >= 4012
  // DQL API available
#else
  #error("Please upgrade to Ditto SDK 4.12+")
#endif
```

### Kotlin

```kotlin
// Check at runtime
val version = Ditto.sdkVersion
println("Ditto SDK version: $version")

if (version < "4.12") {
    error("Please upgrade to SDK 4.12+ to use DQL API")
}
```

---

## Additional Resources

- **DQL Syntax Reference**: [Ditto DQL Documentation](https://docs.ditto.live/dql/)
- **Migration Examples**: See `examples/` directory in this Skill
- **Main Best Practices**: `.claude/guides/best-practices/ditto.md`
- **Query Optimization**: `reference/query-optimization.md`

---

## Need Help?

- **Documentation**: https://docs.ditto.live/sdk/latest/
- **Support**: support@ditto.live
- **Community**: Ditto Community Slack
