-- Ditto SDK 5.2.0 (every SDK)
--
-- Indexing and Query Performance
--
-- Guide sections (../../guide/reference/best-practices/ and knowledge/):
-- - § Creating Indexes
-- - § Index Usage Rules
-- - § Composite indexes and key order (SDK 5.1+)
-- - § Strict mode and data types
-- - § ADVISE (SDK 5.1+)
-- - § EXPLAIN and PROFILE
-- - § Query Scope and Execution
--
-- Facts:
-- - Indexes are local to each device, persist across restarts, and are used by
--   execute and store observers (not by subscriptions; not on Ditto Server).
-- - In-memory stores (Flutter Web, the JavaScript SDK in browsers) do not
--   support indexes: skip index creation there.
-- - With DQL_STRICT_MODE = true the planner uses no secondary index scans
--   (ID lookups and full-collection COUNT(*) are not affected).
--   Keep the default (false) if you rely on indexes.
-- - CREATE INDEX IF NOT EXISTS checks only the name, not the field list.
--
-- PATTERNS DEMONSTRATED:
-- 1. ✅ Creating indexes once at startup (composite index, SDK 5.1+)
-- 2. ✅ Index-friendly predicates vs predicates that force a collection scan
-- 3. ✅ ADVISE for index suggestions (development only, SDK 5.1+)
-- 4. ✅ EXPLAIN to check the access path, PROFILE to measure
-- 5. ✅ One IN :ids query instead of one query per ID
-- 6. ✅ Index-friendly soft-delete filter
--
-- The startup code that runs these statements (and reports a failed index
-- instead of stopping), and the development helpers that print ADVISE and
-- PROFILE results: "App startup in <SDK>" and "Executing DQL in <SDK>" on your
-- SDK's page.

-- ============================================================================
-- PATTERN 1: Indexes at startup
-- ============================================================================

-- ✅ GOOD: Create the indexes this app relies on, once per launch, after
-- opening Ditto and before queries and observers start. Composite index
-- (SDK 5.1+): equality field first, then range/sort field. On SDK 5.1.0, keep
-- all keys in one direction, for example (status, createdAt): indexes that mix
-- ASC and DESC keys return results in the wrong order there
-- (§ Known Issues in SDK 5.1.0). Without an index, queries that use it fall
-- back to a collection scan (and a JOIN on it fails): report and continue.
CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt ON orders (status, createdAt DESC)

CREATE INDEX IF NOT EXISTS idx_orders_customer_createdAt ON orders (customerId, createdAt DESC)

CREATE INDEX IF NOT EXISTS idx_products_name ON products (name)

-- ❌ BAD: Creating an index right before a query. Creation scans the whole
-- collection; create indexes at startup instead.
CREATE INDEX IF NOT EXISTS idx_orders_customerId ON orders (customerId)

-- Arguments: {"customerId": "c-1"}
SELECT * FROM orders WHERE customerId = :customerId

-- ============================================================================
-- PATTERN 2: Index-friendly predicates
-- ============================================================================

-- ✅ GOOD: Equality on the leading key, range and sort on the second key,
-- sort direction matching idx_orders_customer_createdAt.
-- Arguments: {"customerId": "c-1", "since": "2026-10-01T00:00:00.000Z"}
SELECT _id, status, total, createdAt FROM orders
WHERE customerId = :customerId AND createdAt >= :since
ORDER BY createdAt DESC LIMIT 50

-- ❌ BAD: The sort direction does not match the index (createdAt DESC), so
-- an extra sort step is needed.
-- Arguments: {"customerId": "c-1"}
SELECT * FROM orders WHERE customerId = :customerId ORDER BY createdAt ASC

-- ✅ GOOD: A constant, case-sensitive LIKE prefix uses an index range scan.
SELECT _id, name FROM products WHERE name LIKE 'Pen%' ORDER BY name

-- ❌ BAD: Functions applied to the field force a collection scan, even with
-- an index on name. (Functions on the value side, such as `= :param`, are
-- fine.) Expression indexes such as `(lower(name))` do not exist.
SELECT _id, name FROM products WHERE starts_with(name, 'Pen')

-- Arguments: {"name": "pen"}
SELECT _id, name FROM products WHERE lower(name) = :name

-- ❌ BAD: Every OR branch must be indexable. notes has no index, so the
-- whole query becomes a collection scan. Element lookups such as
-- array_contains(tags, 'x') cannot use an index either.
SELECT COUNT(*) AS n FROM orders WHERE status = 'urgent' OR notes = 'urgent'

-- ============================================================================
-- PATTERN 3: ADVISE (development only, SDK 5.1+)
-- ============================================================================

-- ✅ GOOD: ADVISE plans the statement without executing it and suggests
-- CREATE INDEX statements in advice.suggestedIndexes (each with a reason and a
-- statement; advice.outcome explains an empty list). Copy the suggestions into
-- the startup code. Do not run ADVISE AND PROVISION in production code paths;
-- it creates indexes as a side effect. `isDeleted = false` is correct only
-- when every document has the field; otherwise keep the coalesce form (see
-- § Indexing soft-delete filters).
-- Arguments: {"status": "open"}
ADVISE SELECT * FROM orders WHERE status = :status AND isDeleted = false
ORDER BY createdAt DESC

-- ============================================================================
-- PATTERN 4: EXPLAIN vs PROFILE (development only)
-- ============================================================================

-- ✅ GOOD: EXPLAIN parses and plans the statement but never runs it. Use it to
-- check the access path in the plan: `indexScan`, `idScan`, or `countScan` is
-- good; an operator `scan` on a large collection is a warning sign. Do not use
-- it to measure.
-- Arguments: {"status": "open"}
EXPLAIN SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC

-- ✅ GOOD: PROFILE runs the SELECT and appends one row keyed
-- `~request_profile` after the result rows. Compare documentsIn and
-- documentsOut of each step: a filter that discards most of its input usually
-- needs an index.
-- Arguments: {"status": "open"}
PROFILE SELECT * FROM orders WHERE status = :status

-- ============================================================================
-- PATTERN 5: Query scope
-- ============================================================================

-- ❌ BAD: One query per ID, run in a loop.
-- Arguments: {"id": "order-1"}
SELECT * FROM orders WHERE _id = :id

-- ✅ GOOD: One query, planned as an ID scan. The query string stays constant,
-- so the prepared-statement cache is reused.
-- Arguments: {"ids": ["order-1", "order-2"]}
SELECT * FROM orders WHERE _id IN :ids

-- ✅ GOOD: A full-collection COUNT(*) is answered by a count scan without
-- reading documents (SDK 5.1+). For existence checks, LIMIT 1 is simplest.
-- Arguments: {"status": "open"}
SELECT _id FROM orders WHERE status = :status LIMIT 1

-- ============================================================================
-- PATTERN 6: Index-friendly soft-delete filter
-- ============================================================================

-- ✅ GOOD: `coalesce(isDeleted, false) = false` alone is a collection scan.
-- Combine it with a selective, indexed predicate (here status, the leading
-- key of idx_orders_status_createdAt); the coalesce condition is then applied
-- as a filter after the index scan.
-- Arguments: {"status": "open"}
SELECT * FROM orders WHERE status = :status AND coalesce(isDeleted, false) = false
ORDER BY createdAt DESC

-- ✅ GOOD: Index-friendly equivalent of coalesce(isDeleted, false) = false
-- when an index on isDeleted exists.
SELECT * FROM orders
WHERE isDeleted IS MISSING OR isDeleted IS NULL OR isDeleted = false
