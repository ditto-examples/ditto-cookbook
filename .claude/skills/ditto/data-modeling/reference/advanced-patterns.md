# Data Modeling Advanced Patterns

This reference contains MEDIUM/LOW priority patterns for specialized data modeling scenarios. These patterns address edge cases and advanced use cases affecting <20% of users.

## Table of Contents

- [Pattern 1: Two-Collection Pattern for Real-Time + Historical Data](#pattern-1-two-collection-pattern-for-real-time--historical-data)
- [Pattern 2: INITIAL Documents for Device-Local Templates](#pattern-2-initial-documents-for-device-local-templates)
- [Pattern 3: Type Validation in Schema-less Documents](#pattern-3-type-validation-in-schema-less-documents)
- [Pattern 4: Advanced ID Generation Patterns](#pattern-4-advanced-id-generation-patterns)
  - [Composite Keys](#composite-keys-multi-dimensional-organization)
  - [ULID (Time-Ordered IDs)](#ulid-time-ordered-ids)
  - [Human-Readable Display IDs](#human-readable-display-ids)
  - [Migration from Sequential IDs](#migration-from-sequential-ids)
- [Pattern 5: Field Naming Conventions](#pattern-5-field-naming-conventions)

---

## Pattern 1: Two-Collection Pattern for Real-Time + Historical Data

**Priority**: MEDIUM

**Problem**: Storing both real-time current state and complete historical events in a single collection causes performance issues: queries need `ORDER BY LIMIT 1`, working set grows over time, and resource usage is unpredictable.

**When to use**: Location tracking, sensor readings, order status updates—any scenario where you need both "latest value" and "full history"

### Solution: Dual Write Pattern

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
    '''
    INSERT INTO aircraft DOCUMENTS (:aircraft)
    ON ID CONFLICT DO UPDATE
    ''',
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

### Consumer Patterns

```dart
// Real-time display (observe bounded current state)
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM aircraft',
  onChange: (result, signalNext) {
    // Result set size bounded by number of aircraft (not update count)
    updateMapDisplay(result.items);
    WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
  },
);

// Historical analysis (one-time query for trajectory)
final result = await ditto.store.execute(
  '''
  SELECT * FROM position_events
  WHERE aircraft_id = :id AND timestamp >= :start
  ORDER BY timestamp ASC
  ''',
  arguments: {'id': aircraftId, 'start': startTime},
);

final trajectory = result.items.map((item) => item.value).toList();
renderFlightPath(trajectory);
```

### Why Separate Collections?

Independent data sets that don't need to be queried together benefit from separate collections (parallel sync efficiency). Different from splitting related data (like orders and items), which would require sequential queries.

### Benefits

- ✅ Predictable resource usage (current state collection has bounded size)
- ✅ Automatic conflict resolution (CRDT handles concurrent updates)
- ✅ Efficient real-time queries (no `ORDER BY LIMIT 1` needed)
- ✅ Complete audit trail (events collection preserves all history)
- ✅ Differentiated sync (devices sync only what they need)

### Trade-offs

| Single Collection (Events Only) | Two Collections (Dual Write) |
|--------------------------------|------------------------------|
| Simpler schema | Slightly more complex |
| Storage efficient (no duplication) | Duplicates "current state" |
| Queries need `ORDER BY LIMIT 1` | Current state directly queryable |
| Working set grows over time | Current state collection has fixed size |
| App handles conflict resolution | CRDT handles conflicts automatically |

**See Also**:
- `../examples/two-collection-pattern.dart`
- `reference/crdt-types-explained.md`

---

## Pattern 2: INITIAL Documents for Device-Local Templates

**Priority**: MEDIUM

**Problem**: Regular INSERT operations for device-local templates (form templates, default categories, seed data) generate unnecessary sync traffic when each device initializes the same default data.

**Detection**:
```dart
// CRITICAL: Regular INSERT for device-local defaults
final defaultCategories = [
  {'_id': 'cat_food', 'name': 'Food', 'icon': 'food'},
  {'_id': 'cat_drink', 'name': 'Drinks', 'icon': 'drink'},
];

await ditto.store.execute(
  'INSERT INTO categories DOCUMENTS (:categories)',
  arguments: {'categories': defaultCategories},
);
// Each device's INSERT syncs to other peers → unnecessary network traffic
```

### Solution: INITIAL DOCUMENTS

```dart
// ✅ GOOD: INITIAL prevents unnecessary sync
await ditto.store.execute(
  'INSERT INTO categories INITIAL DOCUMENTS (:categories)',
  arguments: {
    'categories': [
      {'_id': 'cat_food', 'name': 'Food', 'icon': 'food'},
      {'_id': 'cat_drink', 'name': 'Drinks', 'icon': 'drink'},
      {'_id': 'cat_dessert', 'name': 'Desserts', 'icon': 'dessert'},
    ],
  },
);

// Each device initializes independently
// If '_id' already exists locally, INITIAL does nothing
// No sync traffic generated for these default templates
```

### How INITIAL Works

- Documents inserted with INITIAL do nothing if the `_id` already exists locally
- All peers view INITIAL documents as the same INSERT operation
- Prevents sync conflicts and unnecessary network traffic for local defaults
- Cannot be overridden by `ON ID CONFLICT` policy

### Why Use INITIAL?

INITIAL documents prevent unnecessary synchronization of device-local data, reducing network traffic and avoiding sync conflicts for data that should exist independently on each device.

### Anti-Pattern

```dart
// ❌ BAD: Regular INSERT syncs unnecessarily
await ditto.store.execute(
  'INSERT INTO categories DOCUMENTS (:categories)',
  arguments: {'categories': defaultCategories},
);
// Generates sync traffic even though all devices have same defaults
```

### Use Cases

1. **Form Templates**: Device-local form structures that don't need sync
2. **Default Settings**: Initial configuration every device should have
3. **Category Lists**: Predefined categories for local organization
4. **UI Presets**: Default UI configurations per device

**See Also**:
- `../examples/initial-documents.dart`

---

## Pattern 3: Type Validation in Schema-less Documents

**Priority**: MEDIUM

**Problem**: Schema-less documents allow any type in any field. Without validation, type mismatches cause query failures or incorrect results.

**Detection**:
```dart
// CRITICAL: No type validation
{
  "_id": "user_123",
  "age": "twenty-five" // Should be number!
}

// Query expecting number fails or returns wrong results
await ditto.store.execute(
  'SELECT * FROM users WHERE age >= :minAge',
  arguments: {'minAge': 18},
);
// String comparison instead of numeric comparison
```

### Solution: Insert-Time Validation + Defensive Queries

#### Insert-Time Validation

```dart
// ✅ GOOD: Validate at insert time
Future<void> insertUser(Map<String, dynamic> userData) async {
  // Validate types before insert
  if (userData['age'] is! int) {
    throw ArgumentError('age must be integer');
  }
  if (userData['email'] is! String || !(userData['email'] as String).contains('@')) {
    throw ArgumentError('email must be valid string');
  }

  await ditto.store.execute(
    'INSERT INTO users DOCUMENTS (:user)',
    arguments: {'user': userData},
  );
}
```

#### Defensive Querying with Type Checking

```dart
// ✅ GOOD: Defensive query with type checking (SDK 4.x+)
await ditto.store.execute(
  'SELECT * FROM users WHERE is_number(age) AND age >= :minAge',
  arguments: {'minAge': 18},
);

// Schema validation query (find malformed documents)
final result = await ditto.store.execute(
  '''SELECT _id, type(age) AS ageType
     FROM users
     WHERE type(age) != :expectedType OR age IS NULL''',
  arguments: {'expectedType': 'number'},
);
```

### Anti-Patterns

```dart
// ❌ BAD: Type checking in every query (inefficient)
await ditto.store.execute(
  'SELECT * FROM users WHERE is_number(age) AND age >= :minAge',
  arguments: {'minAge': 18},
);
// Better: Validate at insert, then queries can assume correct types

// ❌ BAD: No validation at insert
await ditto.store.execute(
  'INSERT INTO users DOCUMENTS (:user)',
  arguments: {'user': userInput}, // No validation!
);
// Type mismatches will cause issues in all subsequent queries
```

### Use Cases

1. **User Input Validation**: Validate types before storing user-generated data
2. **Schema Migration**: Find and fix type mismatches in existing data
3. **Polymorphic Fields**: Query polymorphic fields with type guards
4. **Data Quality Checks**: Identify malformed documents in production

### Type Checking Operators (SDK 4.x+)

- `is_boolean(field)` - Check if field is boolean
- `is_number(field)` - Check if field is number
- `is_string(field)` - Check if field is string
- `type(field)` - Get type name as string ('boolean', 'number', 'string', 'array', 'object', 'null')

### Why Validate at Insert Time?

Type checking operators add query overhead. Validate at insert time to guarantee schema compliance without runtime checks. Use type checking only for defensive queries on untrusted data or polymorphic fields.

### When to Store vs Calculate

| Field Type | Store or Calculate? |
|------------|---------------------|
| Source data (price, quantity, birthdate) | ✅ Store |
| Derived values (lineTotal, age, average) | ✅ Calculate in app |
| Snapshot data (price at order time) | ✅ Store (denormalization for history) |
| Aggregates (sum, count, average) | ✅ Calculate in app |
| UI state (isExpanded, selected) | ❌ Never store (local state only) |

**See Also**:
- `.claude/guides/best-practices/ditto.md (lines 1156-1244: Type Checking Operators)`

---

## Pattern 4: Advanced ID Generation Patterns

**Priority**: MEDIUM

This section covers advanced ID generation techniques beyond basic UUID v4. For basic ID generation, see `../SKILL.md` Pattern 10.

### Composite Keys (Multi-Dimensional Organization)

Use complex object `_id` for multi-dimensional organization and hierarchical access control.

```dart
{
  "_id": {
    "locationId": "store_001",
    "orderId": "7c0c20ed-b285-48a6-80cd-6dcf06d52bcc"
  },
  // Duplicate for queries (POJO/DTO pattern)
  "locationId": "store_001",
  "orderId": "7c0c20ed-b285-48a6-80cd-6dcf06d52bcc"
}
// ⚠️ IMPORTANT: Once created, this _id structure cannot be modified

// Query by component (access specific field)
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE _id.locationId = :locId',
  arguments: {'locId': 'store_001'},
);

// Query by full object (exact match)
final result = await ditto.store.execute(
  '''SELECT * FROM orders WHERE _id = :idObj''',
  arguments: {
    'idObj': {
      'locationId': 'store_001',
      'orderId': '7c0c20ed-b285-48a6-80cd-6dcf06d52bcc'
    }
  },
);
```

**When to Use Composite Keys**:
- Multi-dimensional organization (e.g., order + location, user + device)
- Authorization rules requiring hierarchical access (e.g., filter by locationId)
- Natural composite primary keys in domain model

**Trade-offs**:
- ✅ Clear hierarchical structure
- ✅ Component-level queries without string parsing
- ✅ Better alignment with authorization rules
- ❌ More verbose than simple string IDs
- ❌ Requires careful design - **immutable after creation**
- ❌ Cannot restructure `_id` if requirements change (must create new documents)

### ULID (Time-Ordered IDs)

```dart
import 'package:ulid/ulid.dart';

final ulid = Ulid().toString(); // "01ARZ3NDEKTSV4RRFFQ69G5FAV"

await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {
    'order': {
      '_id': ulid,
      'orderNumber': '#42',
      'status': 'pending',
    }
  },
);
```

**When to Use ULID**:
- Time-ordered sorting required (e.g., display orders chronologically by ID)
- Lexicographically sortable IDs needed
- Timestamp embedded in ID for debugging

**Decision Tree**:
```
Need document _id?
  ↓
Simplest approach?
  ↓ YES → Omit _id (auto-generated UUID)
  ↓ NO
  ↓
Time-ordered sorting required?
  ↓ YES → Use ULID
  ↓ NO
  ↓
Permission scoping needed?
  ↓ YES → Use Composite Keys
  ↓ NO
  ↓
→ Use UUID v4 (general-purpose, recommended)
```

### Human-Readable Display IDs

```dart
// Add display fields alongside UUID with random suffix
import 'dart:math';

final now = DateTime.now();
final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
final randomSuffix = Random().nextInt(0xFFFF).toRadixString(16).toUpperCase().padLeft(4, '0');
final displayId = 'ORD-$dateStr-$randomSuffix';  // "ORD-20251219-A7F3"

await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {
    'order': {
      '_id': Uuid().v4(),  // UUID (collision-free, internal)
      'displayId': displayId,  // Display (date + random, for users)
      'orderNumber': '#42',
    }
  },
);
```

**Why This Pattern?**
- `_id`: Collision-free UUID for internal system use
- `displayId`: Human-readable for UI display and customer reference
- Random suffix reduces user confusion but not required for system correctness

**⚠️ NOTE**: `displayId` does not need to be globally unique (it's not the document ID). The random suffix helps avoid user confusion when multiple orders are created on the same day.

### Migration from Sequential IDs

If migrating from legacy sequential ID systems:

```dart
final uuid = Uuid();
final newOrderId = uuid.v4();
final legacyOrderId = 'order_20250115_001';

await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {
    'order': {
      '_id': newOrderId,                // New UUID (primary)
      'legacyOrderId': legacyOrderId,   // Keep for backward compatibility
      'orderNumber': '#42',
    }
  },
);

// Query by legacy ID
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE legacyOrderId = :legacyId',
  arguments: {'legacyId': 'order_20250115_001'},
);
```

**See Also**:
- [../examples/id-generation-patterns.dart](../examples/id-generation-patterns.dart)
- [../examples/complex-id-patterns.dart](../examples/complex-id-patterns.dart)
- [../examples/id-immutability-workaround.dart](../examples/id-immutability-workaround.dart)

---

## Pattern 5: Field Naming Conventions

**Priority**: MEDIUM

**Problem**: Invalid field names or inconsistent naming conventions cause query errors and maintenance issues

**Detection Triggers**:
```dart
// ❌ CRITICAL: Invalid field names (non-string keys)
{
  123: "value",        // Number as key - invalid
  true: "enabled",     // Boolean as key - invalid
  "_id": "doc_123"     // Valid (string)
}

// ⚠️ WARNING: Inconsistent naming
{
  "customerId": "user_123",     // camelCase
  "customer_name": "Alice",     // snake_case - inconsistent
  "CustomerEmail": "alice@..."  // PascalCase - inconsistent
}
```

### Root Cause

Ditto documents are JSON-like structures with specific constraints. Field names MUST be strings (not numbers or booleans).

### Solution: Consistent String Field Names

```dart
// ✅ GOOD: Consistent camelCase naming
{
  "_id": "order_123",
  "customerId": "cust_456",
  "customerName": "Alice Johnson",
  "customerEmail": "alice@example.com",
  "createdAt": "2025-01-15T10:00:00Z",
  "items": {
    "item_1": {
      "productId": "prod_1",
      "productName": "Widget",
      "quantity": 2
    }
  }
}

// ✅ GOOD: Consistent snake_case naming
{
  "_id": "order_123",
  "customer_id": "cust_456",
  "customer_name": "Alice Johnson",
  "customer_email": "alice@example.com",
  "created_at": "2025-01-15T10:00:00Z"
}
```

### Why Consistent Naming?

- **Code readability**: Clear patterns reduce cognitive load
- **Query simplicity**: Predictable field names simplify DQL queries
- **Team coordination**: Consistency enables collaboration
- **Migration ease**: Uniform naming simplifies schema changes

### Anti-Patterns

```dart
// ❌ BAD: Non-string field names (invalid)
{
  "_id": "doc_123",
  123: "numeric_key",      // ERROR: Numbers as keys not allowed
  true: "boolean_key"      // ERROR: Booleans as keys not allowed
}

// ❌ BAD: Inconsistent naming conventions
{
  "_id": "order_123",
  "customerId": "cust_456",     // camelCase
  "customer_name": "Alice",     // snake_case
  "CustomerEmail": "alice@..."  // PascalCase
}
// Harder to remember, error-prone

// ❌ BAD: Reserved DQL keywords without escaping
{
  "_id": "doc_123",
  "select": "value",    // DQL keyword - may cause parsing issues
  "from": "source",     // DQL keyword - may cause parsing issues
  "where": "condition"  // DQL keyword - may cause parsing issues
}
```

### Field Naming Best Practices

1. **Choose a convention and stick to it**:
   - **camelCase** (recommended for Dart/Flutter): `customerId`, `orderDate`, `totalAmount`
   - **snake_case** (common in databases): `customer_id`, `order_date`, `total_amount`
   - **Never mix conventions** within the same collection

2. **Avoid DQL reserved keywords**:
   - Keywords: `SELECT`, `FROM`, `WHERE`, `INSERT`, `UPDATE`, `DELETE`, etc.
   - If unavoidable, escape with backticks in queries: `` `select` ``

3. **Use descriptive names**:
   - ✅ `orderTotal` or `order_total`
   - ❌ `ot`, `t`, `x`

4. **Keep names concise**:
   - ✅ `createdAt` or `created_at`
   - ❌ `timestampWhenThisOrderWasCreated`

5. **Boolean prefixes**:
   - ✅ `isActive`, `hasDiscount`, `canEdit`
   - ❌ `active`, `discount`, `edit`

### Decision Guide

```
New project?
  ↓
Working with Dart/Flutter?
  ↓ YES → Use camelCase (aligns with Dart conventions)
  ↓ NO
  ↓
Integrating with SQL databases?
  ↓ YES → Use snake_case (aligns with SQL conventions)
  ↓ NO
  ↓
→ Choose based on team preference (be consistent!)
```

### Migration Strategy

If migrating from inconsistent naming:

```dart
// Dual-write pattern during migration
{
  "_id": "order_123",
  "customerId": "cust_456",        // New convention (camelCase)
  "customer_id": "cust_456",       // Legacy (snake_case) - keep temporarily
  "customerName": "Alice Johnson", // New
  "customer_name": "Alice Johnson" // Legacy - keep temporarily
}

// After all clients updated, remove legacy fields
{
  "_id": "order_123",
  "customerId": "cust_456",        // Keep
  "customerName": "Alice Johnson"  // Keep
}
```

### Why This Pattern?

- Ensures valid JSON structure (strings-only keys)
- Improves code maintainability through consistency
- Reduces query errors from typos
- Aligns with platform conventions (Dart, SQL, etc.)

**See Also**:
- `.claude/guides/best-practices/ditto.md (lines 1703-1809: Document Structure Best Practices)`

---

## Further Reading

- **SKILL.md**: Critical patterns (Tier 1)
- **common-patterns.md**: Common patterns (Tier 2)
- **Main Guide**: `.claude/guides/best-practices/ditto.md`
