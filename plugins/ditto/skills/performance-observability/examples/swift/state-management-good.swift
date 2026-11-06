// State management with store observers in Ditto SDK 5.2.0 (Swift, DittoSwift 5.2.0, SwiftUI).
//
// Patterns: 1. a model object that owns one observer and cancels it; 2.
// Equatable model values instead of DittoQueryResult objects; 3. separate
// observers for separate screen regions; 4. publishing only real changes;
// 5. subscriptions at feature scope, observers at screen scope.
//
// Guide: § Store Observers in Swift, § Observer lifecycle in Swift, § Partial UI updates in Swift, § Partial UI Updates, § Working with Query Results

import DittoSwift
import Foundation
import SwiftUI

/// A plain, immutable model of a row.
struct OrderItemModel: Identifiable, Equatable, Decodable {
    let id: String
    let status: String?
    let total: Double?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case status, total
    }
}

// PATTERN 1 + 2 + 4: A model that owns one observer

/// ✅ GOOD: Owns exactly one observer, decodes rows into Equatable values, and
/// publishes only when they changed.
@MainActor
final class OrdersStore: ObservableObject {
    @Published private(set) var orders: [OrderItemModel] = []
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto, storeID: String) {
        observer?.cancel()
        observer = try? ditto.store.registerObserver(
            query: "SELECT _id, status, total FROM orders WHERE storeId = :storeId ORDER BY createdAt DESC, _id LIMIT 200",
            arguments: ["storeId": storeID]
        ) { [weak self] result in
            let decoder = JSONDecoder()
            let orders = result.items.compactMap { try? decoder.decode(OrderItemModel.self, from: $0.jsonData()) }
            MainActor.assumeIsolated { if self?.orders != orders { self?.orders = orders } }
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }

    deinit { observer?.cancel() }
}

// PATTERN 3: A separate, tiny observer for a summary value

/// ✅ GOOD: COUNT(*) instead of counting the list; publishes only changes.
@MainActor
final class OpenOrderCount: ObservableObject {
    @Published private(set) var value = 0
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto, storeID: String) {
        observer?.cancel()
        observer = try? ditto.store.registerObserver(
            query: "SELECT COUNT(*) AS n FROM orders WHERE storeId = :storeId AND status = 'open'",
            arguments: ["storeId": storeID]
        ) { [weak self] result in
            let n = result.items.first?.value["n"] as? Int ?? 0
            MainActor.assumeIsolated { if self?.value != n { self?.value = n } }
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }
}

/// ✅ GOOD: The screen observes nothing itself; the badge and the list each
/// own their model, which the view starts and stops.
struct StoreOrdersScreen: View {
    let ditto: Ditto
    let storeID: String
    @StateObject private var orders = OrdersStore()
    @StateObject private var openCount = OpenOrderCount()

    var body: some View {
        VStack {
            Text("Open: \(openCount.value)")
            List(orders.orders) { order in
                OrderTile(order: order)
            }
        }
        .onAppear {
            orders.start(ditto, storeID: storeID)
            openCount.start(ditto, storeID: storeID)
        }
        .onDisappear {
            orders.stop()
            openCount.stop()
        }
    }
}

/// A row receives plain values from the list; it observes nothing.
struct OrderTile: View {
    let order: OrderItemModel

    var body: some View {
        HStack {
            Text(order.id)
            Spacer()
            Text(order.status ?? "")
        }
    }
}

// PATTERN 5: Subscriptions at feature scope

/// ✅ GOOD: Subscriptions live longer than screens. Observers never sync data;
/// the feature keeps the data on the device while screens come and go.
@MainActor
final class OrdersFeature {
    private var subscriptions: [DittoSyncSubscription] = []

    func start(_ ditto: Ditto, storeID: String) throws {
        stop()
        subscriptions = [
            try ditto.sync.registerSubscription(
                query: "SELECT * FROM orders WHERE storeId = :storeId", arguments: ["storeId": storeID]
            ),
        ]
    }

    func stop() {
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
    }
}
