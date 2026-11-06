// Subscription anti-patterns for Ditto SDK 5.2.0 (Swift, DittoSwift 5.2.0, SwiftUI).
//
// Every example compiles and runs, but wastes bandwidth and storage, churns
// the mesh, or leaks subscriptions. The corrected versions are in
// subscription-lifecycle-good.swift.
//
// Subscription queries that make registerSubscription throw
// DittoError.storeError(reason: .queryNotSupported(...)) at once (described
// here instead of executed):
// - Projection, aggregate:  SELECT _id, status FROM orders
// - DISTINCT, GROUP BY:     SELECT DISTINCT status FROM orders
// - JOIN:                   SELECT * FROM orders o JOIN customers c ON c._id = o.customerId
//   -> "Unsupported feature: Joining"
// - USE IDS:                SELECT * FROM orders USE IDS 'order-1'
// - LIMIT / ORDER BY:       SELECT * FROM orders WHERE storeId = :storeId ORDER BY createdAt DESC LIMIT 50
//   -> "Unsupported feature: Limit or Order by" (while DQL_RESTRICT_SUBSCRIPTIONS
//      has its default value true; keep the default)
// Subscribe with SELECT * FROM c WHERE ... and sort, limit, project, or join in
// local queries instead.
//
// Guide: § Subscriptions in Swift, § Subscription Rules, § Subscription Lifecycle

import DittoSwift
import Foundation
import SwiftUI

/// ❌ BAD: A new subscription every time SwiftUI evaluates body, never
/// cancelled. Each call adds a subscription that keeps replicating until the
/// Ditto instance shuts down.
struct OrdersBadge: View {
    let ditto: Ditto
    let storeID: String

    var body: some View {
        _ = try? ditto.sync.registerSubscription(
            query: "SELECT * FROM orders WHERE storeId = :storeId", arguments: ["storeId": storeID]
        )
        return Image(systemName: "list.bullet.rectangle")
    }
}

/// ❌ BAD: A subscription owned by a screen. Every visit registers and cancels
/// it, making peers across the mesh re-evaluate what they owe the device and
/// interrupting in-flight transfers. Own it in an app or feature service.
struct OrdersScreenOwningSubscription: View {
    let ditto: Ditto
    let storeID: String
    @State private var subscription: DittoSyncSubscription?

    var body: some View {
        EmptyView()
            .onAppear {
                subscription = try? ditto.sync.registerSubscription(
                    query: "SELECT * FROM orders WHERE storeId = :storeId", arguments: ["storeId": storeID]
                )
            }
            .onDisappear { subscription?.cancel() }
    }
}

/// ❌ BAD: Re-registering the subscription whenever the user changes a filter
/// or search term. Change the local observer instead.
final class OrderSearchSync {
    private let ditto: Ditto
    private var subscription: DittoSyncSubscription?

    init(ditto: Ditto) {
        self.ditto = ditto
    }

    func searchChanged(storeID: String, status: String, customerName: String) throws {
        subscription?.cancel()
        subscription = try ditto.sync.registerSubscription(
            query: "SELECT * FROM orders WHERE storeId = :storeId AND status = :status AND customerName = :name",
            arguments: ["storeId": storeID, "status": status, "name": customerName]
        )
    }
}

/// ❌ BAD: The returned subscription is dropped without cancelling. It keeps
/// syncing for the lifetime of the Ditto instance; only ditto.sync.subscriptions
/// can still cancel it.
func subscribeAndForget(_ ditto: Ditto, storeID: String) throws {
    try ditto.sync.registerSubscription(
        query: "SELECT * FROM orders WHERE storeId = :storeId", arguments: ["storeId": storeID]
    )
}

/// ❌ BAD: Every device receives and stores every order of every tenant.
/// Filter by stable partition keys (tenant, store, region, team).
func subscribeToEverything(_ ditto: Ditto) throws -> DittoSyncSubscription {
    try ditto.sync.registerSubscription(query: "SELECT * FROM orders")
}

/// ❌ BAD: Filtering the subscription on fields that change often. Documents
/// leave the subscription's scope when they change state, so devices and
/// relays stop following them. Excluding soft-deleted documents has a similar
/// effect (see the guide section "Soft delete, subscriptions, and cleanup").
func subscribeToOpenUndeletedOrders(_ ditto: Ditto, storeID: String) throws -> DittoSyncSubscription {
    try ditto.sync.registerSubscription(
        query: "SELECT * FROM orders WHERE storeId = :storeId AND status = :status AND coalesce(isDeleted, false) = false",
        arguments: ["storeId": storeID, "status": "open"]
    )
}

/// ❌ BAD: Values interpolated into the subscription string. Use parameters.
func subscribeWithInterpolation(_ ditto: Ditto, storeID: String) throws -> DittoSyncSubscription {
    try ditto.sync.registerSubscription(query: "SELECT * FROM orders WHERE storeId = '\(storeID)'")
}

/// ❌ BAD: Evicting while the matching subscription is still active. Connected
/// peers notice the missing documents and send them back. Cancel first.
func evictWhileSubscribed(_ ditto: Ditto, oldStoreID: String) async throws {
    try await ditto.store.execute(query: "EVICT FROM orders WHERE storeId = :storeId", arguments: ["storeId": oldStoreID])
}

/// ❌ BAD: Expecting execute() to fetch data from peers. Without a matching
/// subscription it only sees what is already stored locally, and an empty
/// result does not mean that no data exists.
func orderExistsAnywhere(_ ditto: Ditto, orderID: String) async throws -> Bool {
    let result = try await ditto.store.execute(
        query: "SELECT _id FROM orders WHERE _id = :id LIMIT 1", arguments: ["id": orderID]
    )
    return !result.items.isEmpty
}
