-- Ditto SDK 5.2.0 (every SDK)
--
-- EVICT anti-patterns. Every sequence below runs, but defeats the purpose of
-- eviction or, on SDK 5.1.0, removes nothing.
--
-- Guide: § EVICT
--        § Eviction frequency
--
-- Corrected versions: evict-subscription-management-good.sql, and
-- retention-service in examples/<sdk>/.

-- ============================================================================
-- ❌ Anti-pattern 1: Evicting while a matching subscription is active
-- ============================================================================

-- ❌ BAD: This subscription stays registered ...
-- Subscription:
SELECT * FROM orders

-- ... while the app evicts. The subscription still matches the evicted
-- documents, so connected peers notice they are missing and sync them back.
-- Arguments: {"cutoff": "2026-10-01T00:00:00.000Z"}
EVICT FROM orders WHERE createdAt < :cutoff

-- ============================================================================
-- ❌ Anti-pattern 2: Evict, then re-subscribe to everything
-- ============================================================================

-- ❌ BAD: Cancelling first is not enough. After the eviction above, the app
-- registers this subscription, which matches the evicted documents again, so
-- they sync straight back.
-- ✅ FIX: Subscribe with `createdAt >= :cutoff` using the same cutoff.
-- Subscription:
SELECT * FROM orders

-- ============================================================================
-- ❌ Anti-pattern 3: Subscription and eviction boundaries do not match
-- ============================================================================

-- ❌ BAD: The subscription keeps 30 days, the eviction removes everything
-- older than 7 days. Documents between 7 and 30 days old are evicted and
-- synced back on every run.
-- ✅ FIX: Use one cutoff value for both statements (`>=` and `<`).
-- Arguments: {"cutoff": "2026-10-01T00:00:00.000Z"}
EVICT FROM orders WHERE createdAt < :cutoff

-- Subscription:
-- Arguments: {"cutoff": "2026-09-08T00:00:00.000Z"}
SELECT * FROM orders WHERE createdAt >= :cutoff

-- ============================================================================
-- ❌ Anti-pattern 4: Evicting on every screen visit
-- ============================================================================

-- ❌ BAD: Running the eviction each time a screen opens. Each eviction
-- triggers a resync with every connected peer, and evicting on every screen
-- visit overloads them. (SDK 5.1+) Ditto logs a warning when post-eviction
-- cleanup runs too frequently.
-- ✅ FIX: Evict on a schedule, at most about once per day.

-- ============================================================================
-- ❌ Anti-pattern 5: USE IDS without WHERE while devices run SDK 5.1.0
-- ============================================================================

-- ❌ BAD where any device still runs SDK 5.1.0: there it completes without an
-- error but evicts nothing (SDK 5.2.0 evicts the listed documents; see
-- § Known Issues in SDK 5.1.0).
-- ✅ FIX: `EVICT FROM orders WHERE _id IN :ids`, which works on every release.
-- Arguments: {"ids": ["order-1", "order-2"]}
EVICT FROM orders USE IDS LIST :ids

-- ============================================================================
-- ❌ Anti-pattern 6: Losing the subscription reference
-- ============================================================================

-- ❌ BAD: Registering a subscription without keeping the returned object.
-- Without a reference, the subscription cannot be cancelled before eviction.
-- Do not rely on garbage collection to cancel it.
-- ✅ FIX: Keep subscriptions in a long-lived service and cancel them there.

-- ============================================================================
-- ❌ Anti-pattern 7: Using DELETE to free local storage
-- ============================================================================

-- ❌ BAD: DELETE removes the documents for every peer and leaves tombstones.
-- ✅ FIX: Use EVICT (local only) with a complementary subscription.
-- Arguments: {"cutoff": "2026-10-01T00:00:00.000Z"}
DELETE FROM orders WHERE createdAt < :cutoff

-- ============================================================================
-- ❌ Anti-pattern 8: Evicting soft-deleted documents that the subscription
-- still covers
-- ============================================================================

-- ❌ BAD: With a whole-collection subscription (Variant A), soft-deleted
-- documents still match it, so evicted documents sync straight back.
-- ✅ FIX: Either clean up with a DELETE on the Ditto Server that syncs to every
-- device (Variant A), or subscribe with a retention window and evict its exact
-- complement (Variant B). See soft-delete-relay.sql.
-- Subscription:
-- Arguments: {"storeId": "store-12"}
SELECT * FROM orders WHERE storeId = :storeId

-- Arguments: {"storeId": "store-12"}
EVICT FROM orders WHERE storeId = :storeId AND isDeleted = true
