-- Ditto SDK 5.2.0 (every SDK)
--
-- Soft delete that propagates reliably through the mesh.
--
-- Guide: § Soft Delete
--        § Soft delete, subscriptions, and cleanup
--
-- Key rules:
-- - Soft delete is an ordinary UPDATE, so it syncs like any other change and
--   does not depend on the tombstone TTL.
-- - Filter with coalesce(isDeleted, false) = false. `isDeleted != true` and
--   `NOT isDeleted` silently drop documents where the field is missing or null.
-- - Keep flagged documents in the subscriptions of devices that relay data.
--   A device that subscribes only to active documents still receives the flag
--   and a restore for documents it holds, but it cannot relay the flag for
--   documents it did not already hold, and a cleanup DELETE never reaches it.
--   Two designs:
--   Variant A: subscribe to the whole collection or partition; clean up with a
--   DELETE on the Ditto Server (or another authorized peer) that syncs to
--   every device. Device-side EVICT does not work here (documents sync back).
--   Variant B: subscribe to active documents plus documents deleted within a
--   retention window; each device evicts exactly the complement.
--
-- The service that owns the Variant B subscription and moves its cutoff:
-- retention-service in examples/<sdk>/.

-- ============================================================================
-- Writes
-- ============================================================================

-- ✅ GOOD: New documents start with isDeleted = false.
-- Arguments: {"order": {"_id": "order-1", "status": "open", "isDeleted": false, "createdAt": "2026-10-08T10:30:00.123Z"}}
INSERT INTO orders DOCUMENTS (:order)

-- ✅ GOOD: Set a flag and a UTC timestamp instead of deleting. deletedAt is
-- compared with cleanup cutoffs, so it needs the fixed-precision helper.
-- Arguments: {"id": "order-1", "deletedAt": "2026-10-08T10:30:00.123Z"}
UPDATE orders SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id

-- ✅ GOOD: A soft delete can be undone.
-- Arguments: {"id": "order-1"}
UPDATE orders SET isDeleted = false UNSET deletedAt WHERE _id = :id

-- ============================================================================
-- Reads
-- ============================================================================

-- ✅ GOOD: coalesce() treats missing and null as "not deleted". A screen
-- observes this query; the subscription keeps the flagged documents.
-- Arguments: {"status": "open"}
SELECT * FROM orders
WHERE status = :status AND coalesce(isDeleted, false) = false
ORDER BY createdAt DESC

-- ✅ GOOD: Index-friendly equivalent of the coalesce() filter when an index
-- on isDeleted exists. Returns the same documents.
SELECT * FROM orders
WHERE isDeleted IS MISSING OR isDeleted IS NULL OR isDeleted = false

-- ❌ BAD: Misses every document where isDeleted is missing or null
-- (for example documents written before the flag was introduced).
SELECT * FROM orders WHERE isDeleted != true -- lint-ignore

-- ============================================================================
-- Variant A: whole-collection subscription, cleanup by a synced DELETE
-- ============================================================================

-- ✅ GOOD (Variant A): The subscription (owned by a long-lived service)
-- includes soft-deleted orders; local queries hide them.
-- Subscription:
-- Arguments: {"storeId": "store-12"}
SELECT * FROM orders WHERE storeId = :storeId

-- Cleanup is a DELETE executed on the Ditto Server after the retention
-- period, which syncs to every device. Repeat until nothing is affected.
-- Arguments: {"cutoff": "2026-09-08T00:00:00.000Z"}
DELETE FROM orders WHERE isDeleted = true AND deletedAt < :cutoff LIMIT 30000

-- ============================================================================
-- Variant B: retention-window subscription, cleanup by device-side EVICT
-- ============================================================================

-- ✅ GOOD (Variant B): Keep active orders and orders deleted within the
-- retention window (longer than the longest time a device is expected to stay
-- offline, for example 30 days). On a schedule, at most about once a day:
-- 1. cancel the subscription, 2. evict the complement with the new cutoff,
-- 3. subscribe again with the same cutoff, also when the eviction failed. The
-- cutoff moves only there, never on screen changes.
-- Subscription:
-- Arguments: {"storeId": "store-12", "cutoff": "2026-09-08T00:00:00.000Z"}
SELECT * FROM orders WHERE storeId = :storeId
AND (coalesce(isDeleted, false) = false OR deletedAt >= :cutoff)

-- Arguments: {"storeId": "store-12", "cutoff": "2026-09-08T00:00:00.000Z"}
EVICT FROM orders
WHERE storeId = :storeId AND isDeleted = true AND deletedAt < :cutoff

-- ❌ BAD (in a mesh where devices sync through each other): Flagged documents
-- leave the subscription immediately. A device that joins later never stores
-- them, so it cannot relay the flag to a device that missed it, and a cleanup
-- DELETE does not reach devices that hold a flagged copy.
-- Subscription:
SELECT * FROM orders WHERE coalesce(isDeleted, false) = false
