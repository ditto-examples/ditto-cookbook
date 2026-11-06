-- DQL read anti-patterns for Ditto SDK 5.2.0 (every SDK).
--
-- Every statement below runs, but returns wrong results, is unsafe, or wastes
-- resources. The corrected versions are in dql-queries-good.sql.
--
-- Statements that fail outright are described in comments only:
-- - Inline object literal with unquoted keys in INSERT
--   (INSERT INTO orders DOCUMENTS ({_id: 'a'})): "Cannot convert to a literal".
-- - GROUP BY or HAVING that references a projection alias: rejected with
--   "... must depend only on group keys or aggregates".
-- - JOIN whose inner join key has no index (and is not _id): rejected with
--   "Joining to ... disallowed without appropriate index support".
-- - SELECT *, total * 2 AS doubled: unqualified * with other projections is
--   rejected; write SELECT orders.*, ... instead.
-- - Unqualified field that exists on both sides of a JOIN (SELECT name ...):
--   "Ambiguous reference to field: name". Qualify fields with their alias.
-- - USE IDS with the IDs wrapped in parentheses is rejected; use
--   USE IDS 'a', 'b' or USE IDS LIST :ids.
--
-- Guide: § Parameters and Literals, § MISSING and NULL,
--   § Filtering by Membership, § Reading Data with SELECT

-- ❌ BAD: String interpolation. The app pasted user input into the statement
-- text: input such as x' OR '1' = '1 changes its meaning (DQL injection),
-- quotes and backslashes break it, and the statement cannot be reused. How
-- interpolation looks in each SDK, and the fix: "Executing DQL in <SDK>" on
-- your SDK's page.
SELECT * FROM orders WHERE customerId = 'x' OR '1' = '1'

-- ❌ BAD: IN (:statuses) wraps the array in a one-element list, so no
-- document matches. Use IN :statuses.
-- Arguments: {"statuses": ["open", "pending"]}
SELECT * FROM orders WHERE status IN (:statuses)

-- ❌ BAD: ANY ... SATISFIES over a parameter in WHERE returns no rows in
-- SDK 5.1.0 and 5.2.0. Use status IN :statuses.
-- Arguments: {"statuses": ["open", "pending"]}
SELECT * FROM orders WHERE ANY s IN :statuses SATISFIES s = status END -- lint-ignore

-- ❌ BAD: Unquoted keys in a SELECT object literal produce no error, but the
-- object is returned as {} (the key is evaluated as a field reference).
SELECT {a: 1} AS o FROM system:dual

-- ❌ BAD: This filter drops documents where isDeleted is null or missing.
-- Use coalesce(isDeleted, false) = false.
SELECT * FROM tasks WHERE isDeleted != true ORDER BY createdAt -- lint-ignore

-- ❌ BAD: The null check is also true for a missing field, so this does not
-- test existence. Use IS NOT MISSING (plus the null check if null values
-- must be excluded as well).
SELECT * FROM tasks WHERE assignee IS NOT NULL ORDER BY _id -- lint-ignore

-- ❌ BAD: LIMIT without ORDER BY. The page contents are not well defined.
SELECT * FROM orders LIMIT 20

-- ❌ BAD: Expecting matching documents first. In ascending order false sorts
-- before true, so urgent tasks come last. Use DESC or an explicit CASE.
SELECT * FROM tasks ORDER BY priority = 'urgent', dueAt

-- ❌ BAD: Loading every document to count them, or to test existence, in app
-- code. Use SELECT COUNT(*) ... or SELECT _id ... LIMIT 1.
-- Arguments: {"status": "open"}
SELECT * FROM orders WHERE status = :status

-- ❌ BAD: Loading the whole collection to filter it in app code materializes
-- every document. Filter in WHERE.
SELECT * FROM orders

-- ❌ BAD: One query per ID in a loop (N+1). Use WHERE _id IN :ids once.
-- Arguments: {"id": "order-1"}
SELECT * FROM orders WHERE _id = :id

-- ❌ BAD: USE IDS with an array parameter treats the whole array as a single
-- ID and returns nothing. Use USE IDS LIST :ids or WHERE _id IN :ids.
-- Arguments: {"orderIds": ["order-1", "order-2"]}
SELECT * FROM orders USE IDS :orderIds

-- ❌ BAD: COUNT(field) skips false values, so this does not count documents
-- that have the field. SUM over zero rows returns MISSING, so revenue is
-- absent from the row. Use COUNT(isPaid IS NOT MISSING) and
-- ifmissing(SUM(total), 0).
-- Arguments: {"customerId": "customer-without-orders"}
SELECT COUNT(isPaid) AS withFlag, SUM(total) AS revenue
FROM orders WHERE customerId = :customerId

-- ❌ BAD: DISTINCT together with _id. Every document is already unique, so
-- DISTINCT only keeps every row in memory.
SELECT DISTINCT _id, status FROM orders
