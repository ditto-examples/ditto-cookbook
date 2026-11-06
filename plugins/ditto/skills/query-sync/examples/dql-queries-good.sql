-- Recommended DQL read patterns for Ditto SDK 5.2.0 (every SDK).
--
-- Covers: parameters, membership filters, quoted object keys, MISSING/NULL,
-- ORDER BY / LIMIT / keyset pagination, projections, aggregates, GROUP BY,
-- and JOIN (SDK 5.1+) with an index on the inner collection.
--
-- All statements read the local store only. Subscriptions decide which
-- documents are on the device (see subscription-lifecycle-good in
-- examples/<sdk>/). How each SDK passes the arguments: "Executing DQL in
-- <SDK>" on your SDK's page.
--
-- Guide: § Parameters and Literals, § MISSING and NULL,
--   § Filtering by Membership, § Reading Data with SELECT,
--   § Joining Collections (SDK 5.1+)

-- ---------------------------------------------------------------------------
-- Parameters
-- ---------------------------------------------------------------------------

-- ✅ GOOD: Every value from the app is passed as a typed parameter. The
-- statement text stays constant, so the prepared plan can be reused. The
-- array parameter is written IN :statuses, without parentheses.
-- Arguments: {"customerId": "c-1", "statuses": ["open", "pending"], "pageSize": 50}
SELECT * FROM orders
WHERE customerId = :customerId AND status IN :statuses
ORDER BY createdAt DESC, _id LIMIT :pageSize

-- ✅ GOOD: Text containing backslashes or quotes is passed as data.
-- Arguments: {"id": "device", "path": "C:\\temp\\exports"}
UPDATE settings SET exportPath = :path WHERE _id = :id

-- ---------------------------------------------------------------------------
-- Inline object literals
-- ---------------------------------------------------------------------------

-- ✅ GOOD (preferred): Pass the whole document as one parameter. createdAt is
-- sorted and compared, so it comes from the fixed-precision helper.
-- Arguments: {"order": {"_id": "order-1", "customerId": "c-1", "status": "open", "total": 0, "createdAt": "2026-10-08T10:30:00.123Z"}}
INSERT INTO orders DOCUMENTS (:order)

-- ✅ GOOD: If an object literal is written inline, every key is quoted.
INSERT INTO orders DOCUMENTS ({'_id': 'sample-order', 'status': 'open'})
ON ID CONFLICT DO NOTHING

-- ---------------------------------------------------------------------------
-- MISSING and NULL
-- ---------------------------------------------------------------------------

-- ✅ GOOD: coalesce() treats a missing or null isDeleted flag as false.
SELECT * FROM tasks WHERE coalesce(isDeleted, false) = false
ORDER BY createdAt, _id

-- ✅ GOOD: IS MISSING / IS NOT MISSING test whether a field exists.
SELECT _id, title FROM tasks WHERE assignee IS MISSING ORDER BY _id

-- ---------------------------------------------------------------------------
-- Membership
-- ---------------------------------------------------------------------------

-- ✅ GOOD: A field equals one of several values.
-- Arguments: {"statuses": ["open", "pending"]}
SELECT * FROM tasks WHERE status IN :statuses ORDER BY _id

-- ✅ GOOD: An array field contains a value (element lookups cannot use an index).
-- Arguments: {"tag": "urgent"}
SELECT * FROM tasks WHERE :tag IN tags ORDER BY _id

-- ✅ GOOD: Several documents by ID in one query (planned as an ID scan).
-- Arguments: {"ids": ["order-1", "order-2"]}
SELECT * FROM orders WHERE _id IN :ids

-- ---------------------------------------------------------------------------
-- Projections, ORDER BY, LIMIT
-- ---------------------------------------------------------------------------

-- ✅ GOOD: Only the fields the screen shows, computed fields aliased,
-- deterministic order with an _id tie-breaker.
-- Arguments: {"status": "open"}
SELECT _id, customerName, total * 1.1 AS totalWithTax
FROM orders WHERE status = :status
ORDER BY createdAt DESC, _id LIMIT 100

-- ✅ GOOD: Keyset pagination continues after the last row of the previous
-- page. _id breaks ties between rows that share the same createdAt. Load the
-- first page with the same query without the WHERE clause.
-- Arguments: {"after": "2026-10-08T10:30:00.123Z", "afterId": "task-42", "pageSize": 50}
SELECT _id, title, createdAt FROM tasks
WHERE createdAt < :after OR (createdAt = :after AND _id < :afterId)
ORDER BY createdAt DESC, _id DESC LIMIT :pageSize

-- ✅ GOOD: Put urgent tasks first explicitly (false sorts before true in ASC).
SELECT * FROM tasks WHERE coalesce(isDeleted, false) = false
ORDER BY CASE WHEN priority = 'urgent' THEN 0 ELSE 1 END, dueAt, _id

-- ✅ GOOD: An existence check stops at the first match.
-- Arguments: {"status": "open"}
SELECT _id FROM orders WHERE status = :status LIMIT 1

-- ---------------------------------------------------------------------------
-- Aggregates and GROUP BY
-- ---------------------------------------------------------------------------

-- ✅ GOOD: COUNT(*) instead of loading documents; empty sets defaulted.
-- Arguments: {"customerId": "c-1"}
SELECT COUNT(*) AS orderCount,
       ifmissing(SUM(total), 0) AS revenue,
       ifmissing(AVG(total), 0) AS averageOrder
FROM orders WHERE customerId = :customerId

-- ✅ GOOD: GROUP BY and HAVING repeat the expressions; ORDER BY may use aliases.
-- Arguments: {"since": "2026-10-01T00:00:00.000Z", "minRevenue": 1000}
SELECT date_format(createdAt, 'YYYY-MM-DD') AS day, SUM(total) AS revenue
FROM orders WHERE createdAt >= :since
GROUP BY date_format(createdAt, 'YYYY-MM-DD')
HAVING SUM(total) > :minRevenue
ORDER BY day

-- ✅ GOOD: DISTINCT on a low-cardinality field.
SELECT DISTINCT status FROM orders ORDER BY status

-- ---------------------------------------------------------------------------
-- JOIN (SDK 5.1+)
-- ---------------------------------------------------------------------------

-- ✅ GOOD: Create the index the join needs once per launch, at startup.
-- Indexes persist, and IF NOT EXISTS makes this idempotent.
CREATE INDEX IF NOT EXISTS idx_orders_customerId ON orders (customerId)

-- ✅ GOOD: The inner collection (orders) is looked up through
-- idx_orders_customerId. Fields are qualified and colliding names aliased.
-- Arguments: {"tier": "gold"}
SELECT c.name, o._id AS orderId, o.total
FROM customers c
JOIN orders o ON o.customerId = c._id
WHERE c.tier = :tier
ORDER BY c.name, o.total DESC

-- ✅ GOOD: Joining on the inner collection's _id needs no extra index.
-- Arguments: {"status": "open"}
SELECT o._id, o.total, c.name AS customerName
FROM orders o
JOIN customers c ON c._id = o.customerId
WHERE o.status = :status
ORDER BY o._id

-- ✅ GOOD: Customers without any order (unmatched LEFT JOIN rows).
SELECT c._id, c.name
FROM customers c
LEFT JOIN orders o ON o.customerId = c._id
WHERE o._id IS MISSING
