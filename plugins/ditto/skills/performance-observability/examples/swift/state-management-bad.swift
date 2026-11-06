// State management anti-patterns with store observers in Ditto SDK 5.2.0 (Swift, DittoSwift 5.2.0, SwiftUI).
//
// Anti-patterns: 1. one broad observer at the root, with the DittoQueryResult
// kept in published state; 2. a dropped observer, and an observer never
// cancelled with a retain cycle; 3. heavy synchronous work in a handler on the
// main queue; 4. one observer per list row; 5. writing to the observed
// collection from its own handler.
//
// Guide: § Store Observers in Swift, § Observer lifecycle in Swift, § Keep observer callbacks fast, § Partial UI Updates

import DittoSwift
import Foundation
import SwiftUI

// ANTI-PATTERN 1: Broad observer, DittoQueryResult in state

/// ❌ BAD: Observes the whole collection without ORDER BY or LIMIT, keeps the
/// DittoQueryResult, and makes the whole dashboard re-render on every change.
@MainActor
final class OrdersDashboardModel: ObservableObject {
    @Published var result: DittoQueryResult?
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto) {
        observer = try? ditto.store.registerObserver(query: "SELECT * FROM orders") { [weak self] result in
            MainActor.assumeIsolated { self?.result = result }
        }
    }

    func stop() { observer?.cancel() }
}

// ANTI-PATTERN 2: Dropped observer, never cancelled

/// ❌ BAD: The view model throws the observer away (registerObserver is
/// @discardableResult) and captures self strongly: the observer runs, and the
/// model lives, for the lifetime of the Ditto instance.
@MainActor
final class LeakyOrderListModel: ObservableObject {
    @Published var count = 0

    func start(_ ditto: Ditto) {
        _ = try? ditto.store.registerObserver(query: "SELECT _id FROM orders ORDER BY _id") { result in
            let count = result.items.count
            MainActor.assumeIsolated { self.count = count }
        }
    }
}

// ANTI-PATTERN 3: Heavy synchronous work in the handler

/// ❌ BAD: Expensive computation on the main queue for every update. The next
/// result waits for the handler, and so does the UI. Deliver on a background
/// queue and publish only the result.
@MainActor
final class HeavySummaryModel: ObservableObject {
    @Published var summary = ""
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto) {
        observer = try? ditto.store.registerObserver(query: "SELECT * FROM orders") { [weak self] result in
            let json = result.items.map { String(decoding: $0.jsonData(), as: UTF8.self) }.sorted().joined()
            let digest = json.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) } // stands in for heavy work
            MainActor.assumeIsolated { self?.summary = String(digest) }
        }
    }

    func stop() { observer?.cancel() }
}

// ANTI-PATTERN 4: One observer per list row

/// ❌ BAD: Every row registers its own observer. Observe the list once and
/// pass values down.
struct OrderRowWithOwnObserver: View {
    let ditto: Ditto
    let orderID: String
    @StateObject private var model = RowObserverModel()

    var body: some View {
        Text(model.status)
            .onAppear { model.start(ditto, orderID: orderID) }
            .onDisappear { model.stop() }
    }
}

@MainActor
final class RowObserverModel: ObservableObject {
    @Published var status = ""
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto, orderID: String) {
        observer = try? ditto.store.registerObserver(
            query: "SELECT status FROM orders WHERE _id = :id", arguments: ["id": orderID]
        ) { [weak self] result in
            let status = result.items.first?.value["status"] as? String ?? ""
            MainActor.assumeIsolated { self?.status = status }
        }
    }

    func stop() { observer?.cancel() }
}

// ANTI-PATTERN 5: Writing to the observed collection from its handler

/// ❌ BAD: Each write triggers the observer again. This UPDATE has no guard, so
/// the handler and the write call each other without end.
func selfTriggeringObserver(_ ditto: Ditto) throws -> DittoStoreObserver {
    try ditto.store.registerObserver(query: "SELECT * FROM orders WHERE status = 'open'") { _ in
        Task {
            try? await ditto.store.execute(query: "UPDATE orders SET viewedAt = :now WHERE status = 'open'",
                                           arguments: ["now": Date().timeIntervalSince1970])
        }
    }
}
