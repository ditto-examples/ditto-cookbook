-- Ditto SDK 5.2.0 (every SDK)
--
-- EVICT with correct subscription management.
--
-- Guide: § EVICT
--        § Cancelling subscriptions and local data
--
-- Key rules:
-- - EVICT removes documents from this device only. If an active subscription
--   still matches them, connected peers sync them back.
-- - Cancel or narrow the affected subscriptions BEFORE evicting, including
--   overlapping subscriptions that also match the documents.
-- - Evict exactly the complement of the remaining subscriptions (same cutoff,
--   `>=` in the subscription, `<` in the eviction).
-- - Keep subscription references in a long-lived service so they can be
--   cancelled.
-- - Evict on a schedule, at most about once per day.
-- - Target documents by ID with `WHERE _id IN :ids`, which works on every
--   SDK 5.x release (`USE IDS` alone evicts nothing on SDK 5.1.0).
--
-- The services that run these steps (time-based retention, switching stores,
-- a daily scheduler): retention-service in examples/<sdk>/.

-- ============================================================================
-- Pattern 1: Time-based retention with complementary queries
-- ============================================================================

-- Keep the last 7 days of orders on this device. The cutoff is now minus 7
-- days, in the same fixed-precision format as the stored timestamps.
-- At startup, before sync starts:
-- Subscription:
-- Arguments: {"cutoff": "2026-10-01T10:30:00.123Z"}
SELECT * FROM orders WHERE createdAt >= :cutoff

-- On a schedule, for example once a day, with a new cutoff:
-- 1. Cancel the subscription, to stop asking peers for the documents that are
--    about to be evicted.
-- 2. Evict exactly the complement of the new subscription:
-- Arguments: {"cutoff": "2026-10-02T10:30:00.123Z"}
EVICT FROM orders WHERE createdAt < :cutoff

-- 3. Subscribe again with the moved boundary, even if the eviction failed:
-- Subscription:
-- Arguments: {"cutoff": "2026-10-02T10:30:00.123Z"}
SELECT * FROM orders WHERE createdAt >= :cutoff

-- ============================================================================
-- Pattern 2: Switching stores (the needed data changes)
-- ============================================================================

-- After login or when the user switches to another store:
-- 1. Cancel the subscriptions for the old store's data.
-- 2. Remove the old store's documents from this device only:
-- Arguments: {"storeId": "store-2"}
EVICT FROM orders WHERE storeId != :storeId

-- Arguments: {"storeId": "store-2"}
EVICT FROM orderItems WHERE storeId != :storeId

-- 3. Ask for the new store's data:
-- Subscription:
-- Arguments: {"storeId": "store-2"}
SELECT * FROM orders WHERE storeId = :storeId

-- Subscription:
-- Arguments: {"storeId": "store-2"}
SELECT * FROM orderItems WHERE storeId = :storeId

-- Data that was already being transferred when the old subscriptions were
-- cancelled can still arrive afterwards. Run the two EVICT statements again
-- later, for example on the next app start or from a periodic cleanup.

-- ============================================================================
-- Pattern 3: Evicting specific documents by ID
-- ============================================================================

-- ✅ GOOD: `WHERE _id IN :ids` is planned as an ID scan. Only evict IDs that
-- no active subscription on this device still matches.
-- Arguments: {"ids": ["order-1", "order-2"]}
EVICT FROM orders WHERE _id IN :ids RETURNING _id

-- ============================================================================
-- Pattern 4: Run eviction at most once per day
-- ============================================================================

-- Run the retention cleanup at most once per day, for example when the app
-- starts after hours. Persist the time of the last run in your own storage if
-- the app restarts often.
