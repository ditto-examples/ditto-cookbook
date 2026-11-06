# Local Store Test Examples

The local store tests from `§ Testing Strategies`, as the statements each test runs and the result it expects, for every SDK. The complete test files for each SDK are `local-store-tests` in `../examples/<sdk>/` and the *Testing in <SDK>* section of its page. In your suite, call your app's repository functions instead of the inline statements.

## Testing Merge-Sensitive Writes

A single device cannot reproduce a concurrent merge, but it can verify that your code produces the **write shape** that merges well: field-level updates instead of whole-document rewrites, maps keyed by ID instead of arrays, and upserts that skip unchanged values (see [CRDT Types and Merge Behavior](../../guide/reference/knowledge/crdt-types.md) and [Arrays and Maps](../../guide/reference/best-practices/data-modeling.md#arrays-and-maps)). Assert the local semantics your code relies on, so that a refactoring that switches to a whole-document write or an array is caught.

```sql
-- Test: adding a line item keeps the existing items (map keyed by ID)
-- Arguments: {"order": {"_id": "order-1", "items": {"item-1": {"productId": "p1", "quantity": 2}}}}
INSERT INTO orders DOCUMENTS (:order)

-- The code under test: an upsert of a partial document (see "Arrays and Maps")
-- Arguments: {"patch": {"_id": "order-1", "items": {"item-2": {"productId": "p2", "quantity": 1}}}}
INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- Expected: items is a map (not an array) with the keys item-1 and item-2
-- Arguments: {"id": "order-1"}
SELECT * FROM orders WHERE _id = :id
```

```sql
-- Test: re-upserting unchanged data is a no-op
-- Arguments: {"product": {"_id": "p1", "name": "Pen", "priceCents": 250}}
INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- Run the same statement again. Expected: no mutated document IDs
-- Arguments: {"product": {"_id": "p1", "name": "Pen", "priceCents": 250}}
INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF
```

```sql
-- Test: replacing an address removes keys that are not in the new address
-- Arguments: {"customer": {"_id": "c1", "address": {"city": "Oslo", "zip": "0150"}}}
INSERT INTO customers DOCUMENTS (:customer)

-- The code under test: both statements in one transaction
-- (see "Assigning an object merges it")
-- Arguments: {"id": "c1"}
UPDATE customers UNSET address WHERE _id = :id

-- Arguments: {"id": "c1", "address": {"city": "Bergen"}}
UPDATE customers SET address = :address WHERE _id = :id

-- Expected: address is {"city": "Bergen"}. A plain SET would keep "zip":
-- objects merge under the default settings.
-- Arguments: {"id": "c1"}
SELECT * FROM customers WHERE _id = :id
```

If your app declares types (`REGISTER`, `COUNTER`, `ATTACHMENT`) or enables strict mode, test those statements with the same declarations and settings; mixed declarations produce results that look like data loss (see [Keep type declarations consistent](../../guide/reference/best-practices/data-modeling.md#keep-type-declarations-consistent)).


## Testing Deletion and Soft Delete

Deletion logic fails silently: a filter that excludes documents without the flag, or a statement that completes without removing anything. Insert documents in every state your data can be in (flag `true`, `false`, `null`, and missing) and assert exactly which ones your queries return (see [Soft Delete](../../guide/reference/best-practices/deletion-and-storage.md#soft-delete) and [MISSING and NULL](../../guide/reference/best-practices/dql.md#missing-and-null)).

```sql
-- Test: the active-orders query treats a missing or null flag as not deleted
-- Arguments: {"orders": [{"_id": "deleted", "isDeleted": true}, {"_id": "active", "isDeleted": false}, {"_id": "nullFlag", "isDeleted": null}, {"_id": "noFlag"}]}
INSERT INTO orders DOCUMENTS (:orders)

-- The query used by the app's repository. Expected: active, noFlag, nullFlag
SELECT _id FROM orders WHERE coalesce(isDeleted, false) = false ORDER BY _id
```

```sql
-- Test: deleting by ID removes exactly the listed documents
-- Arguments: {"orders": [{"_id": "o1"}, {"_id": "o2"}, {"_id": "o3"}]}
INSERT INTO orders DOCUMENTS (:orders)

-- The statement used by the app; WHERE _id IN :ids, not USE IDS.
-- Expected: two mutated document IDs
-- Arguments: {"ids": ["o1", "o2"]}
DELETE FROM orders WHERE _id IN :ids

-- Expected: only o3
SELECT _id FROM orders
```

Assertions on the number of removed documents also catch SDK 5.1.0, where `DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate (no `WHERE` clause, or `WHERE true`) removes nothing (see [Known Issues in SDK 5.1.0](../../guide/reference/knowledge/upgrading.md#known-issues-in-sdk-510)). Run the same tests on every SDK release that devices in the field use. Tombstone expiry, husk documents, and "zombie data" from devices that were offline longer than the tombstone TTL involve several peers; cover them in multi-device tests (see [Testing on Multiple Devices](../../guide/reference/best-practices/testing.md#testing-on-multiple-devices)).


## Testing Observer Lifecycle

Test that your observers deliver updates, and that your cleanup code releases them (see [Observer Lifecycle](../../guide/reference/best-practices/observers.md#observer-lifecycle)). Register the observer, write a matching document, wait for a specific result with a timeout instead of a fixed delay, then run the same cleanup that the screen runs and check that the observer reports itself as cancelled. Do not assert on the number of callbacks; it is not guaranteed.

```sql
-- The observer under test
-- Arguments: {"status": "open"}
SELECT * FROM orders WHERE status = :status ORDER BY _id

-- The write that it must see within the timeout
-- Arguments: {"order": {"_id": "order-1", "status": "open"}}
INSERT INTO orders DOCUMENTS (:order)
```

For UI tests of screens that own observers, keep the observer behind your own interface and inject a stream or a fake you control. The differs accept only items produced by Ditto, so code that uses one needs a real store (see [Diffing Results](../../guide/reference/best-practices/observers.md#diffing-results)).


## Testing Subscription Rules

Registering a subscription validates the query when it is called, even before sync starts. It fails for projections, aggregates, `DISTINCT`, `GROUP BY`, `JOIN`, `USE IDS`, and (while the system parameter `DQL_RESTRICT_SUBSCRIPTIONS` has its default value `true`) `ORDER BY` and `LIMIT`. `WHERE` filters are allowed (see [Subscription Rules](../../guide/reference/best-practices/sync-and-subscriptions.md#subscription-rules) and [The sending peer evaluates a subscription's WHERE clause like a local query](../../guide/reference/knowledge/observations/subscriptions-and-replication.md#the-sending-peer-evaluates-a-subscriptions-where-clause-like-a-local-query)). A test that registers every subscription your app uses, and then cancels it, catches invalid subscription queries without a network. You can also assert that the forms your app must not use are rejected:

<!-- subscription expect-error -->
```sql
-- Test: subscriptions with projections or ORDER BY and LIMIT are rejected
SELECT _id, status FROM orders

SELECT * FROM orders ORDER BY createdAt DESC LIMIT 50
```

<!-- subscription -->
```sql
-- Test: the app's subscriptions are valid; cancel each one afterwards
-- Arguments: {"storeId": "store-1"}
SELECT * FROM orders WHERE storeId = :storeId

SELECT * FROM products
```


## Validating DQL in Tests

Keep the DQL statements of your app as constants in one place (for example, a repository class), and run each of them through `EXPLAIN` with representative arguments. `EXPLAIN` parses and plans a statement without executing it (see [EXPLAIN and PROFILE](../../guide/reference/best-practices/indexing-and-performance.md#explain-and-profile)), so the test catches syntax errors and other statements that cannot be planned, without touching any data. For hot queries, also assert that the plan uses the index you created; a later change to the query or to strict mode (which disables index scans on SDK 5.1.0 and 5.2.0; see [Strict mode and data types](../../guide/reference/best-practices/indexing-and-performance.md#strict-mode-and-data-types)) then fails the test.

```sql
-- Test: every app statement can be planned; EXPLAIN fails if it cannot
-- Arguments: {"status": "open"}
EXPLAIN SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC

-- Arguments: {"status": "closed", "id": "order-1"}
EXPLAIN UPDATE orders SET status = :status WHERE _id = :id

-- Arguments: {"ids": ["order-1"]}
EXPLAIN DELETE FROM orders WHERE _id IN :ids
```

```sql
-- Test: the open-orders query uses its index. Create the index with the same
-- startup code as the app; expected: the plan contains "indexScan"
CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt ON orders (status, createdAt DESC)

-- Arguments: {"status": "open"}
EXPLAIN SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC
```

During development, `ADVISE` (SDK 5.1+) suggests the indexes these statements need (see [ADVISE (SDK 5.1+)](../../guide/reference/best-practices/indexing-and-performance.md#advise-sdk-51)).
