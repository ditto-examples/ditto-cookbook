-- Ditto SDK 5.2.0 (every SDK)
--
-- Device-local, time-based retention on a Small Peer, plus tombstone TTL
-- settings passed when Ditto opens.
--
-- Guide: § Time-based eviction
--        § Batching evictions
--        § Tombstone TTL and reaping
--
-- Two different "TTLs" appear here:
-- - Retention window (app logic): how long documents stay on this device.
--   Implemented with a time-scoped subscription and EVICT of the complement.
-- - Tombstone TTL (system parameter TOMBSTONE_TTL_HOURS, default 168 = 7 days):
--   how long DELETE tombstones are kept before reaping. Pass it in the system
--   parameters of DittoConfig on every open (SDK 5.2+; on SDK 5.1, with ALTER
--   SYSTEM after every open and before sync starts). There is no SDK method
--   for it, it is not persisted, and it must never exceed the Ditto Server
--   tombstone TTL.
--
-- The startup code, and the retention service that runs the steps below:
-- "DittoConfig in <SDK>" on your SDK's page and retention-service in
-- examples/<sdk>/.

-- ============================================================================
-- Startup: the tombstone TTL
-- ============================================================================

-- Example only: raise the tombstone TTL to 14 days because devices in this
-- deployment may stay offline for up to two weeks. Keep it at or below the
-- Ditto Server TTL; changes on the server side go through Ditto support.
-- SDK 5.2+: pass {"TOMBSTONE_TTL_HOURS": 336} in the system parameters of
-- DittoConfig on every open. SDK 5.1: run this after every open, before sync
-- starts:
ALTER SYSTEM SET TOMBSTONE_TTL_HOURS = 336

-- ============================================================================
-- Retention: time-scoped subscription + complementary, batched eviction
-- ============================================================================

-- At startup, before sync starts. The cutoff is now minus the retention
-- period (for example 7 days), in the fixed-precision format of createdAt.
-- Subscription:
-- Arguments: {"cutoff": "2026-10-01T10:30:00.123Z"}
SELECT * FROM orders WHERE createdAt >= :cutoff

-- On a schedule, at most about once per day, preferably at a quiet time:
-- 1. Cancel the subscription.
-- 2. Evict the complement in short batches: repeat until a batch evicts 0.
--    Batching keeps each write transaction short. It does not reduce the sync
--    cost of eviction: run the whole batched cleanup on the usual schedule,
--    not as many separate cleanups.
-- Arguments: {"cutoff": "2026-10-02T10:30:00.123Z"}
EVICT FROM orders WHERE createdAt < :cutoff LIMIT 1000
RETURNING COUNT(*) AS evicted

-- 3. Subscribe again with the same cutoff, even if the eviction failed.
-- Subscription:
-- Arguments: {"cutoff": "2026-10-02T10:30:00.123Z"}
SELECT * FROM orders WHERE createdAt >= :cutoff

-- ============================================================================
-- Checking the effect
-- ============================================================================

-- The newest document count for orders is the last row whose key is
-- collection_num_docs[orders]. The values are collected periodically and can
-- lag behind recent writes.
SELECT key, value, timestamp FROM system:system_info
WHERE key LIKE 'collection_num_docs%'
ORDER BY timestamp ASC
