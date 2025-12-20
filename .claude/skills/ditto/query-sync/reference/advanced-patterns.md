# Query and Sync Advanced Patterns

This reference contains MEDIUM priority patterns for advanced query optimization scenarios in Ditto. These patterns address edge cases and performance optimization for power users.

## Table of Contents

- [Pattern 13: Large OFFSET Values](#pattern-13-large-offset-values)
- [Pattern 14: Expensive Operator Usage](#pattern-14-expensive-operator-usage)

---

### 13. Large OFFSET Values (Priority: MEDIUM)

**Platform**: All platforms

**Problem**: Large `OFFSET` values degrade performance linearly—Ditto must skip all offset documents sequentially.

**Detection**:
```dart
// RED FLAG
final result = await ditto.store.execute(
  'SELECT * FROM orders LIMIT 20 OFFSET 10000',
);
// Must skip 10,000 documents - slow!
```

**✅ DO (Use OFFSET sparingly)**:
```dart
// ✅ GOOD: Small OFFSET for pagination
final result = await ditto.store.execute(
  'SELECT * FROM orders ORDER BY createdAt DESC LIMIT 20 OFFSET 40',
);
// Returns orders 41-60 (reasonable offset)

// ✅ GOOD: Use WHERE for deep pagination
final result = await ditto.store.execute(
  '''SELECT * FROM orders
     WHERE createdAt < :cursor
     ORDER BY createdAt DESC LIMIT 20''',
  arguments: {'cursor': lastSeenTimestamp},
);
```

**❌ DON'T**:
```dart
// ❌ BAD: Large OFFSET (linear performance degradation)
final result = await ditto.store.execute(
  'SELECT * FROM products LIMIT 50 OFFSET 5000',
);

// ❌ BAD: LIMIT without ORDER BY (unpredictable results)
final result = await ditto.store.execute(
  'SELECT * FROM cars LIMIT 10',
);
// Different runs may return different sets
```

**Why**: `OFFSET` requires sequential skipping. For deep pagination, use cursor-based approaches (WHERE with timestamp/ID). Always combine `LIMIT` with `ORDER BY` for predictable results.

**Cursor-Based Pagination Pattern**:
```dart
// First page
var lastTimestamp = DateTime.now().toIso8601String();

var result = await ditto.store.execute(
  '''
  SELECT * FROM orders
  WHERE createdAt < :cursor
  ORDER BY createdAt DESC
  LIMIT 20
  ''',
  arguments: {'cursor': lastTimestamp},
);

// Next page (use last item's timestamp as cursor)
if (result.items.isNotEmpty) {
  lastTimestamp = result.items.last.value['createdAt'];
  result = await ditto.store.execute(
    '''
    SELECT * FROM orders
    WHERE createdAt < :cursor
    ORDER BY createdAt DESC
    LIMIT 20
    ''',
    arguments: {'cursor': lastTimestamp},
  );
}
```

**Performance Comparison**:

| Pagination Method | Performance | Memory |
|-------------------|-------------|--------|
| OFFSET 10000 | ❌ Scans 10,000 rows | ❌ High |
| Cursor-based | ✅ Direct seek | ✅ Constant |

**See Also**:
- `.claude/guides/best-practices/ditto.md` (lines 778-807: LIMIT and OFFSET)
- `../../performance-observability/reference/optimization-patterns.md` Pattern 9: Large OFFSET Performance

---

### 14. Expensive Operator Usage (Priority: MEDIUM)

**Platform**: All platforms

**Problem**: Using expensive operators (object introspection, complex patterns, type checking) without WHERE filters or choosing complex operators when simpler alternatives exist.

**Detection**:
```dart
// RED FLAGS
// Object introspection without filter
await ditto.store.execute(
  'SELECT * FROM products WHERE :key IN object_keys(metadata)',
  arguments: {'key': 'someKey'},
);

// Regex when LIKE works
await ditto.store.execute(
  'SELECT * FROM users WHERE regexp_like(email, \'^admin.*\')',
);

// Type checking on full collection
await ditto.store.execute(
  'SELECT * FROM documents WHERE type(field) = :expectedType',
  arguments: {'expectedType': 'string'},
);
```

**✅ DO (Filter first, use simpler operators)**:
```dart
// Filter first, then apply expensive operators
await ditto.store.execute(
  'SELECT * FROM products WHERE category = :cat AND :key IN object_keys(metadata)',
  arguments: {'cat': 'electronics', 'key': 'someKey'},
);

// Use simpler operators
await ditto.store.execute(
  'SELECT * FROM users WHERE email LIKE :pattern',
  arguments: {'pattern': 'admin%'},
);

// Date operators for temporal queries (SDK 4.11+)
await ditto.store.execute(
  'SELECT * FROM orders WHERE createdAt >= date_sub(clock(), :days, :unit)',
  arguments: {'days': 7, 'unit': 'day'},
);

// Conditional operators for null handling
await ditto.store.execute(
  'SELECT orderId, coalesce(discount, :default) AS finalDiscount FROM orders',
  arguments: {'default': 0.0},
);
```

**❌ DON'T**:
```dart
// Expensive operators on full collection
await ditto.store.execute(
  'SELECT * FROM documents WHERE object_length(metadata) > :threshold',
  arguments: {'threshold': 10},
);

// Complex regex for simple patterns
regexp_like(name, '^Apple.*') // Use LIKE 'Apple%' instead

// SIMILAR TO when LIKE suffices
field SIMILAR TO 'prefix%' // Use LIKE 'prefix%' instead
```

**Why**: Expensive operators (object_keys, object_values, SIMILAR TO, type checking) add significant overhead. Always filter with WHERE first to reduce working set. Use simpler operators (LIKE, starts_with) when they suffice.

**Performance Hierarchy** (fast → slow):
1. Index scans with simple comparisons
2. String prefix matching (LIKE 'prefix%', starts_with)
3. IN operator with small lists
4. Date operators (date_cast, date_add, etc.)
5. Conditional operators (coalesce, nvl, decode)
6. Type checking operators (is_number, is_string, type)
7. Object introspection (object_keys, object_values)
8. Advanced patterns (SIMILAR TO, regexp_like)

**Operator Optimization Examples**:

| Instead of | Use | Reason |
|-----------|-----|--------|
| `regexp_like(field, '^prefix')` | `LIKE 'prefix%'` or `starts_with(field, 'prefix')` | Simpler pattern matching |
| `type(field) = 'number'` | `is_number(field)` | Dedicated type check |
| `object_keys(metadata)` on full collection | Filter first: `WHERE category = 'X' AND ...` | Reduce working set |
| `SIMILAR TO 'pattern%'` | `LIKE 'pattern%'` | LIKE is sufficient |

**See Also**:
- `.claude/guides/best-practices/ditto.md` (lines 820-1625: DQL Operator Expressions)
- `../../performance-observability/reference/optimization-patterns.md` Pattern 10: Operator Performance

---

## Further Reading

- **SKILL.md**: Critical patterns (Tier 1)
- **common-patterns.md**: HIGH priority patterns (Tier 2)
- **Main Guide**: `.claude/guides/best-practices/ditto.md`
- **Related Skills**:
  - `performance-observability/SKILL.md`: Query performance optimization
  - `data-modeling/SKILL.md`: Schema design for efficient queries
