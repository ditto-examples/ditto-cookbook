// Store observer anti-patterns for Ditto SDK 5.2.0 (Swift, DittoSwift 5.2.0, SwiftUI).
//
// Every example compiles, but keeps observers running forever, blocks the main
// thread, retains results, or updates far more UI than needed. The corrected
// versions are in observer-patterns-good.swift and observer-backpressure.swift.
//
// Guide: § Store Observers in Swift, § Observer lifecycle in Swift, § Backpressure in Swift, § Stable ordering

import DittoSwift
import Foundation
import SwiftUI

/// ❌ BAD: The returned observer is thrown away. registerObserver is
/// @discardableResult, so this compiles without a warning, but the observer
/// keeps running for the lifetime of the Ditto instance, and every call adds
/// one more (Note (SDK 5.1.0 and 5.2.0)). Only ditto.store.observers can still
/// cancel it.
func watchOrderCountForever(_ ditto: Ditto, onCount: @escaping @Sendable (Int) -> Void) throws {
    _ = try ditto.store.registerObserver(query: "SELECT * FROM orders ORDER BY createdAt DESC") { result in
        onCount(result.items.count)
    }
}

/// ❌ BAD: Registered in body, never cancelled. SwiftUI evaluates body many
/// times; each evaluation adds an observer that is never cancelled.
struct OrdersInBody: View {
    let ditto: Ditto
    @State private var count = 0

    var body: some View {
        _ = try? ditto.store.registerObserver(query: "SELECT * FROM orders ORDER BY createdAt DESC, _id") { result in
            print(result.items.count)
        }
        return Text("\(count) orders")
    }
}

/// ❌ BAD: The model keeps its observer but never cancels it: neither when the
/// screen goes away nor in deinit. Because the handler captures self strongly,
/// the model is never deallocated either.
@MainActor
final class LeakyOrdersModel: ObservableObject {
    @Published var count = 0
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto) {
        observer = try? ditto.store.registerObserver(query: "SELECT _id FROM orders ORDER BY _id") { result in
            let count = result.items.count
            MainActor.assumeIsolated { self.count = count } // strong self, no cancel()
        }
    }
}

/// ❌ BAD: Keeping the DittoQueryResult in published state. Copy item.value
/// (or decoded models) out of the result instead.
@MainActor
final class RetainsResultModel: ObservableObject {
    @Published var lastResult: DittoQueryResult?
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto) {
        observer = try? ditto.store.registerObserver(query: "SELECT * FROM orders") { [weak self] result in
            MainActor.assumeIsolated { self?.lastResult = result }
        }
    }

    func stop() { observer?.cancel() }
}

/// ❌ BAD: No ORDER BY. Rows may change position between updates.
func observeTasksUnordered(_ ditto: Ditto, onRows: @escaping @Sendable ([[String: Any?]]) -> Void) throws -> DittoStoreObserver {
    try ditto.store.registerObserver(query: "SELECT * FROM tasks WHERE done = false") { result in
        onRows(result.items.map { $0.value })
    }
}

/// ❌ BAD: Slow work in a handler on the main queue. The SDK waits for the
/// handler before it delivers the next result, and the UI waits too.
func blockMainOnEveryChange(_ ditto: Ditto) throws -> DittoStoreObserver {
    try ditto.store.registerObserver(query: "SELECT * FROM orders ORDER BY _id") { result in
        let data = try? JSONSerialization.data(withJSONObject: result.items.map { $0.value.compactMapValues { $0 } })
        Thread.sleep(forTimeInterval: 0.5) // stands in for slow encoding or file I/O
        print(data?.count ?? 0)
    }
}

/// ❌ BAD: A Task per update without backpressure. Every result starts an
/// upload, the uploads overlap, and an older result can finish last. Use
/// handlerWithSignalNext (see observer-backpressure.swift).
func uploadOnEveryChange(_ ditto: Ditto, upload: @escaping @Sendable ([[String: Any?]]) async -> Void) throws -> DittoStoreObserver {
    try ditto.store.registerObserver(query: "SELECT * FROM orders ORDER BY createdAt") { result in
        let orders = result.items.map { $0.value }
        Task { await upload(orders) }
    }
}

/// ❌ BAD: Writing to the observed collection from its own observer without a
/// guard. Each write triggers the observer again.
/// Comparing with the stored time does not help: each device writes its own, so devices that
/// run this observer keep overwriting each other (guide: Writing from Observers).
func touchOnEveryChange(_ ditto: Ditto) throws -> DittoStoreObserver {
    try ditto.store.registerObserver(query: "SELECT * FROM orders WHERE status = 'open'") { _ in
        Task {
            try? await ditto.store.execute(
                query: "UPDATE orders SET lastSeenAt = :now WHERE status = :status",
                arguments: ["now": "\(Date())", "status": "open"]
            )
        }
    }
}

/// ❌ BAD: One observer per list row. Observe the list once and pass values
/// down to the rows.
@MainActor
final class OrderRowModel: ObservableObject {
    @Published var status: String?
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto, orderID: String) {
        observer = try? ditto.store.registerObserver(
            query: "SELECT * FROM orders WHERE _id = :id", arguments: ["id": orderID]
        ) { [weak self] result in
            let status = result.items.first?.value["status"] as? String
            MainActor.assumeIsolated { self?.status = status }
        }
    }

    func stop() { observer?.cancel() }
}

/// ❌ BAD: Observing a whole collection at the root and re-rendering the whole
/// screen (title, filters, list) on every change. Use one small observer per
/// region instead.
@MainActor
final class WholeScreenModel: ObservableObject {
    @Published var orders: [[String: Any?]] = []
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto) {
        observer = try? ditto.store.registerObserver(query: "SELECT * FROM orders") { [weak self] result in
            let orders = result.items.map { $0.value }
            MainActor.assumeIsolated { self?.orders = orders }
        }
    }

    func stop() { observer?.cancel() }

    var openCount: Int { orders.filter { $0["status"] as? String == "open" }.count }
}
