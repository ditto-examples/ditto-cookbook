// Recommended subscription patterns for Ditto SDK 5.2.0 (Swift, DittoSwift 5.2.0, SwiftUI).
//
// Rules:
// - A subscription query is SELECT * FROM <collection> [WHERE <condition>].
//   Projections, DISTINCT, aggregates, JOIN, USE IDS, LIMIT and ORDER BY make
//   registerSubscription throw a DittoError at once.
// - Subscriptions are long-lived (app or feature scope) and scoped by stable
//   partition keys. Avoid changing subscriptions more often than about every
//   15 minutes.
// - Keep every DittoSyncSubscription and cancel() it when its data is no longer
//   relevant: registerSubscription is @discardableResult, and a dropped
//   subscription keeps syncing (Note (SDK 5.1.0 and 5.2.0)). Cancelling does
//   not delete local data.
// - UI filters, search, tabs, and sorting change local observers, not
//   subscriptions.
//
// Guide: § Subscriptions in Swift, § Subscription Lifecycle, § Filter locally instead of re-registering, § Cancelling subscriptions and local data

import DittoSwift
import Foundation
import SwiftUI

/// ✅ GOOD: A session-level service owns the long-lived subscriptions of one
/// workspace (store). Create it after login; call leaveStore() on logout.
@MainActor
final class OrderSync {
    private let ditto: Ditto
    private var subscriptions: [DittoSyncSubscription] = []
    private(set) var storeID: String?

    init(ditto: Ditto) {
        self.ditto = ditto
    }

    /// Call once after login or when the user enters a store.
    func enterStore(_ storeID: String) throws {
        guard storeID != self.storeID else { return } // Already subscribed: keep it stable.
        leaveStore()
        // Scope by a stable partition key; screens filter further locally.
        // orderItems carries a copied storeId because subscriptions cannot join.
        subscriptions = [
            try ditto.sync.registerSubscription(
                query: "SELECT * FROM orders WHERE storeId = :storeId", arguments: ["storeId": storeID]
            ),
            try ditto.sync.registerSubscription(
                query: "SELECT * FROM orderItems WHERE storeId = :storeId", arguments: ["storeId": storeID]
            ),
            // A small reference-data collection that every device needs may be
            // subscribed to without a filter.
            try ditto.sync.registerSubscription(query: "SELECT * FROM productCategories"),
        ]
        self.storeID = storeID
    }

    /// Call on logout or when the user leaves the store.
    func leaveStore() {
        for subscription in subscriptions {
            subscription.cancel()
        }
        subscriptions.removeAll()
        storeID = nil
    }
}

/// ✅ GOOD: Switching stores: cancel first, evict the old store's data from this
/// device, then subscribe to the new store. Evicting documents that still match
/// an active subscription is futile: peers send them back.
func switchStore(_ ditto: Ditto, current: [DittoSyncSubscription], newStoreID: String) async throws -> [DittoSyncSubscription] {
    for subscription in current {
        subscription.cancel()
    }
    try await ditto.store.execute(query: "EVICT FROM orders WHERE storeId != :storeId", arguments: ["storeId": newStoreID])
    try await ditto.store.execute(query: "EVICT FROM orderItems WHERE storeId != :storeId", arguments: ["storeId": newStoreID])
    return [
        try ditto.sync.registerSubscription(
            query: "SELECT * FROM orders WHERE storeId = :storeId", arguments: ["storeId": newStoreID]
        ),
        try ditto.sync.registerSubscription(
            query: "SELECT * FROM orderItems WHERE storeId = :storeId", arguments: ["storeId": newStoreID]
        ),
    ]
}

/// ✅ GOOD (soft delete, Variant A): Soft-deleted documents stay in the
/// subscription; local queries hide them with coalesce(isDeleted, false) = false.
/// Every device stores flagged documents, so any device can relay the flag to
/// one that missed it. For device-side EVICT, use a retention-window
/// subscription (Variant B, see the storage-lifecycle skill).
func subscribeToTeamTasks(_ ditto: Ditto, teamID: String) throws -> DittoSyncSubscription {
    try ditto.sync.registerSubscription(query: "SELECT * FROM tasks WHERE teamId = :teamId", arguments: ["teamId": teamID])
}

/// ✅ GOOD: Subscriptions for a local JOIN: one per collection the join reads.
func subscribeForOrderList(_ ditto: Ditto, storeID: String) throws -> [DittoSyncSubscription] {
    [
        try ditto.sync.registerSubscription(
            query: "SELECT * FROM orders WHERE storeId = :storeId", arguments: ["storeId": storeID]
        ),
        try ditto.sync.registerSubscription(
            query: "SELECT * FROM customers WHERE storeId = :storeId", arguments: ["storeId": storeID]
        ),
    ]
}

/// ✅ GOOD: The subscription (owned by OrderSync) stays stable while the user
/// switches status filters; only the local observer is replaced.
@MainActor
final class OrdersByStatusModel: ObservableObject {
    @Published private(set) var orders: [[String: Any?]] = []
    private let ditto: Ditto
    private var observer: DittoStoreObserver?

    init(ditto: Ditto) {
        self.ditto = ditto
    }

    func observe(storeID: String, status: String) {
        observer?.cancel() // Replacing a local observer is cheap.
        observer = try? ditto.store.registerObserver(
            query: "SELECT * FROM orders WHERE storeId = :storeId AND status = :status ORDER BY createdAt DESC, _id",
            arguments: ["storeId": storeID, "status": status]
        ) { [weak self] result in
            let orders = result.items.map { $0.value }
            MainActor.assumeIsolated { self?.orders = orders }
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }
}

struct OrdersByStatus: View {
    let storeID: String
    let status: String
    @StateObject private var model: OrdersByStatusModel

    init(ditto: Ditto, storeID: String, status: String) {
        self.storeID = storeID
        self.status = status
        _model = StateObject(wrappedValue: OrdersByStatusModel(ditto: ditto))
    }

    var body: some View {
        List(model.orders.indices, id: \.self) { index in
            Text(model.orders[index]["_id"] as? String ?? "")
        }
        .onAppear { model.observe(storeID: storeID, status: status) }
        .onChange(of: status) { newStatus in model.observe(storeID: storeID, status: newStatus) }
        .onDisappear { model.stop() }
    }
}

/// ✅ GOOD: Inspect active subscriptions for debugging. queryArguments is nil
/// for a subscription registered without arguments. The listed objects are
/// equal (==) to the ones you registered, but other objects.
func logActiveSubscriptions(_ ditto: Ditto) {
    for subscription in ditto.sync.subscriptions {
        print("subscription:", subscription.queryString, subscription.queryArguments as Any,
              "cancelled:", subscription.isCancelled)
    }
}

/// ✅ GOOD: Pausing sync does not require cancelling subscriptions.
/// stop() pauses them; start() resumes them.
func pauseSync(_ ditto: Ditto) { ditto.sync.stop() }
func resumeSync(_ ditto: Ditto) throws { try ditto.sync.start() }
