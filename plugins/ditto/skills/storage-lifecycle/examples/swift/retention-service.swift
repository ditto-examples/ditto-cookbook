// Ditto SDK: 5.2.0 (Swift, DittoSwift 5.2.0)
//
// Services that own the subscriptions and run evictions on a schedule.
//
// The DQL and the rules are in ../evict-subscription-management-good.sql,
// ../ttl-eviction-small-peer.sql, and ../soft-delete-relay.sql. The same
// services for the other SDKs are in examples/<sdk>/retention-service.*.
// registerSubscription is @discardableResult, but a dropped subscription keeps
// syncing: keep every DittoSyncSubscription and cancel() it.
//
// Guide: § EVICT, § Time-based eviction, § Batching evictions, § Soft delete, subscriptions, and cleanup, § Subscriptions in Swift

import DittoSwift
import Foundation

/// ISO 8601 UTC timestamp with exactly millisecond precision, for example
/// "2026-10-08T10:30:00.123Z". Fixed precision keeps values sortable as text.
private func utcTimestamp(_ date: Date = Date()) -> String {
    Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
}

// Time-based retention: subscription and complementary, batched eviction

/// Keeps the last `retention` of orders on this device.
@MainActor
final class OrderRetention {
    private let ditto: Ditto
    private let retention: TimeInterval
    private var subscription: DittoSyncSubscription?

    init(ditto: Ditto, retention: TimeInterval = 7 * 24 * 60 * 60) {
        self.ditto = ditto
        self.retention = retention
    }

    // Same fixed-precision format as the stored timestamps (utcTimestamp()).
    private func cutoff() -> String { utcTimestamp(Date().addingTimeInterval(-retention)) }

    /// Call once at startup (before ditto.sync.start()).
    func start() throws {
        subscription = try subscribe(from: cutoff())
    }

    /// Call on a schedule, at most about once per day, preferably at a quiet time.
    func evictExpired() async throws -> Int {
        let cutoff = cutoff()
        // 1. Stop asking peers for documents older than the new cutoff.
        subscription?.cancel()
        // 3. Subscribe again with the moved boundary (the same cutoff value),
        //    even if the eviction failed.
        defer { subscription = try? subscribe(from: cutoff) }
        // 2. Evict the complement in short batches.
        return try await evictInBatches(before: cutoff)
    }

    private func subscribe(from cutoff: String) throws -> DittoSyncSubscription {
        try ditto.sync.registerSubscription(
            query: "SELECT * FROM orders WHERE createdAt >= :cutoff", arguments: ["cutoff": cutoff]
        )
    }

    /// Batching keeps each write transaction short. It does not reduce the sync
    /// cost of eviction: run the whole batched cleanup on the usual schedule,
    /// not as many separate cleanups.
    private func evictInBatches(before cutoff: String) async throws -> Int {
        var total = 0
        while true {
            let result = try await ditto.store.execute(
                query: "EVICT FROM orders WHERE createdAt < :cutoff LIMIT 1000 RETURNING COUNT(*) AS evicted",
                arguments: ["cutoff": cutoff]
            )
            let evicted = result.items.first?.value["evicted"] as? Int ?? 0
            total += evicted
            if evicted == 0 { return total }
        }
    }

    func stop() { subscription?.cancel() }
}

// Soft delete, Variant B: retention window, device-side EVICT

/// Keeps active orders and orders deleted within the retention window, and
/// evicts older deleted orders.
@MainActor
final class OrderSoftDeleteRetention {
    private let ditto: Ditto
    private let storeID: String
    /// Longer than the longest time a device is expected to stay offline.
    private let retention: TimeInterval = 30 * 24 * 60 * 60
    private var subscription: DittoSyncSubscription?

    init(ditto: Ditto, storeID: String) {
        self.ditto = ditto
        self.storeID = storeID
    }

    private func cutoff() -> String { utcTimestamp(Date().addingTimeInterval(-retention)) }

    func start() throws {
        subscription = try subscribe(cutoff: cutoff())
    }

    func evictExpired() async throws {
        let cutoff = cutoff()
        subscription?.cancel()
        defer { subscription = try? subscribe(cutoff: cutoff) }
        try await ditto.store.execute(
            query: "EVICT FROM orders WHERE storeId = :storeId AND isDeleted = true AND deletedAt < :cutoff",
            arguments: ["storeId": storeID, "cutoff": cutoff]
        )
    }

    private func subscribe(cutoff: String) throws -> DittoSyncSubscription {
        try ditto.sync.registerSubscription(
            query: """
            SELECT * FROM orders WHERE storeId = :storeId
            AND (coalesce(isDeleted, false) = false OR deletedAt >= :cutoff)
            """,
            arguments: ["storeId": storeID, "cutoff": cutoff]
        )
    }

    func stop() { subscription?.cancel() }
}

// Switching stores (the needed data changes)

/// Owns the store-scoped subscriptions for the app session.
@MainActor
final class StoreSync {
    private let ditto: Ditto
    private var subscriptions: [DittoSyncSubscription] = []
    private var currentStoreID: String?

    init(ditto: Ditto) {
        self.ditto = ditto
    }

    /// Call after login or when the user switches to another store.
    func switchStore(to newStoreID: String) async throws {
        // 1. Stop asking for the old store's data.
        cancelSubscriptions()
        // 2. Remove the old store's documents from this device only.
        currentStoreID = newStoreID
        try await evictOtherStores(keeping: newStoreID)
        // 3. Ask for the new store's data.
        subscriptions = [
            try ditto.sync.registerSubscription(
                query: "SELECT * FROM orders WHERE storeId = :storeId", arguments: ["storeId": newStoreID]
            ),
            try ditto.sync.registerSubscription(
                query: "SELECT * FROM orderItems WHERE storeId = :storeId", arguments: ["storeId": newStoreID]
            ),
        ]
    }

    /// Data that was already being transferred when the old subscriptions were
    /// cancelled can still arrive afterwards. Call this later, for example on the
    /// next app start or from a periodic cleanup, to evict it again.
    func evictLateArrivals() async throws {
        if let currentStoreID { try await evictOtherStores(keeping: currentStoreID) }
    }

    private func evictOtherStores(keeping storeID: String) async throws {
        try await ditto.store.execute(query: "EVICT FROM orders WHERE storeId != :storeId", arguments: ["storeId": storeID])
        try await ditto.store.execute(query: "EVICT FROM orderItems WHERE storeId != :storeId", arguments: ["storeId": storeID])
    }

    private func cancelSubscriptions() {
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
    }

    /// Call on logout.
    func stop() { cancelSubscriptions() }
}

// Run eviction at most once per day

/// Runs the retention cleanup at most once per day, for example when the app
/// becomes active. Persist lastRun in your own storage if needed.
@MainActor
final class DailyEvictionScheduler {
    private let retention: OrderRetention
    var lastRun: Date?

    init(retention: OrderRetention) {
        self.retention = retention
    }

    func runIfDue(now: Date = Date()) async throws {
        if let lastRun, now.timeIntervalSince(lastRun) < 24 * 60 * 60 { return }
        lastRun = now
        _ = try await retention.evictExpired()
    }
}

// ❌ BAD: An eviction from a view's onAppear runs on every screen visit. Each
// eviction triggers a resync with every connected peer. Use the scheduler above.
