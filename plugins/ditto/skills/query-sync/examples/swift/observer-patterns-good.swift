// Recommended store observer patterns for Ditto SDK 5.2.0 (Swift, DittoSwift 5.2.0, SwiftUI).
//
// A model object owns each observer: it registers the observer when the screen
// appears, copies plain values out of each result, and cancels the observer
// when the screen goes away and in deinit. registerObserver(query:arguments:
// deliverOn:handler:) delivers on the main queue by default, and the handler
// cannot throw. The method is @discardableResult, but a dropped
// DittoStoreObserver keeps running (Note (SDK 5.1.0 and 5.2.0)): keep it and
// call cancel().
//
// Observers read the local store only. Pair them with a long-lived
// subscription (see subscription-lifecycle-good.swift).
//
// Guide: § Store Observers in Swift, § Observer lifecycle in Swift, § Stable ordering, § Partial UI updates in Swift

import DittoSwift
import Foundation
import SwiftUI

private func showError(_ error: Error) {
    // Report the error to your logging or crash-reporting pipeline.
}

/// ✅ GOOD: The recommended observer pattern for SwiftUI.
@MainActor
final class OrdersListModel: ObservableObject {
    @Published private(set) var orders: [[String: Any?]] = []
    private let ditto: Ditto
    private var observer: DittoStoreObserver?

    init(ditto: Ditto) {
        self.ditto = ditto
    }

    func start() {
        guard observer == nil else { return }
        do {
            observer = try ditto.store.registerObserver(
                query: "SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id",
                arguments: ["status": "open"]
            ) { [weak self] result in // delivered on the main queue
                let orders = result.items.map { $0.value } // copy values out of the result
                MainActor.assumeIsolated { self?.orders = orders }
            }
        } catch {
            showError(error)
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }

    deinit {
        observer?.cancel() // also when the view never called stop()
    }
}

struct OrdersList: View {
    @StateObject private var model: OrdersListModel

    init(ditto: Ditto) {
        _model = StateObject(wrappedValue: OrdersListModel(ditto: ditto))
    }

    var body: some View {
        List(model.orders.indices, id: \.self) { index in
            Text(model.orders[index]["_id"] as? String ?? "")
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

/// ✅ GOOD: Rows mapped to Identifiable values, a projection, a deterministic
/// order with an _id tie-breaker, and a LIMIT that keeps the result set small.
struct TaskRow: Identifiable, Equatable {
    let id: String
    let title: String
}

@MainActor
final class TaskListModel: ObservableObject {
    @Published private(set) var tasks: [TaskRow] = []
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto, teamID: String) {
        observer?.cancel()
        observer = try? ditto.store.registerObserver(
            query: """
            SELECT _id, title, createdAt FROM tasks
            WHERE teamId = :teamId AND coalesce(isDeleted, false) = false
            ORDER BY createdAt DESC, _id LIMIT 200
            """,
            arguments: ["teamId": teamID]
        ) { [weak self] result in
            // Keep the handler short: copy values, then publish.
            let tasks = result.items.compactMap { item -> TaskRow? in
                guard let id = item.value["_id"] as? String else { return nil }
                return TaskRow(id: id, title: item.value["title"] as? String ?? "")
            }
            MainActor.assumeIsolated {
                if self?.tasks != tasks { self?.tasks = tasks }
            }
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }
}

struct TaskList: View {
    let ditto: Ditto
    let teamID: String
    @StateObject private var model = TaskListModel()

    var body: some View {
        List(model.tasks) { task in Text(task.title) } // identity by _id
            .onAppear { model.start(ditto, teamID: teamID) }
            .onDisappear { model.stop() }
    }
}

/// ✅ GOOD: An AsyncStream around an observer. Cancelling the task that
/// iterates it, or releasing the stream, cancels the observer. Create the
/// stream inside the task that iterates it.
extension DittoStore {
    func openOrderRows(status: String) -> AsyncStream<[[String: Any?]]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            do {
                let observer = try registerObserver(
                    query: "SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id",
                    arguments: ["status": status],
                    deliverOn: DispatchQueue(label: "orders.rows")
                ) { result in
                    continuation.yield(result.items.map { $0.value })
                }
                continuation.onTermination = { _ in observer.cancel() }
            } catch {
                showError(error)
                continuation.finish()
            }
        }
    }
}

struct OpenOrdersStream: View {
    let ditto: Ditto
    @State private var orders: [[String: Any?]] = []

    var body: some View {
        List(orders.indices, id: \.self) { index in
            Text(orders[index]["_id"] as? String ?? "")
        }
        .task {
            // SwiftUI cancels this task when the view disappears, which
            // cancels the observer.
            for await rows in ditto.store.openOrderRows(status: "open") {
                orders = rows
            }
        }
    }
}

/// ✅ GOOD: Partial UI updates. The badge observes COUNT(*) on its own and
/// publishes only when the count actually changes.
@MainActor
final class OpenOrdersCountModel: ObservableObject {
    @Published private(set) var count = 0
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto) {
        guard observer == nil else { return }
        observer = try? ditto.store.registerObserver(
            query: "SELECT COUNT(*) AS n FROM orders WHERE status = :status",
            arguments: ["status": "open"]
        ) { [weak self] result in
            let n = result.items.first?.value["n"] as? Int ?? 0
            MainActor.assumeIsolated {
                if self?.count != n { self?.count = n } // an equal value would still update views
            }
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }
}

struct OpenOrdersCount: View {
    let ditto: Ditto
    @StateObject private var model = OpenOrdersCountModel()

    var body: some View {
        Text("Open orders: \(model.count)")
            .onAppear { model.start(ditto) }
            .onDisappear { model.stop() }
    }
}

/// ✅ GOOD: The screen observes nothing itself; each region has its own
/// observer and updates independently.
struct OrdersScreen: View {
    let ditto: Ditto

    var body: some View {
        VStack {
            OpenOrdersCount(ditto: ditto)
            OrdersList(ditto: ditto)
        }
    }
}

/// ✅ GOOD: An observer owned by a non-UI object, delivered on its own serial
/// queue, released with stop(). The observed JOIN (SDK 5.1+) fires when either
/// collection changes. Project the keys of each row (o._id AS orderId): on SDK
/// 5.2.0, joined rows carry no _id of their own. Subscribe to both collections
/// separately.
final class OpenOrdersWithCustomers: @unchecked Sendable {
    private var observer: DittoStoreObserver?

    init(ditto: Ditto, onRows: @escaping @Sendable ([[String: Any?]]) -> Void) throws {
        observer = try ditto.store.registerObserver(
            query: """
            SELECT o._id AS orderId, o.total, c.name AS customerName
            FROM orders o JOIN customers c ON c._id = o.customerId
            WHERE o.status = :status ORDER BY o.createdAt DESC, o._id
            """,
            arguments: ["status": "open"],
            deliverOn: DispatchQueue(label: "orders.customers")
        ) { result in
            onRows(result.items.map { $0.value })
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }
}
