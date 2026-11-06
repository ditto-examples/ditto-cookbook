// Partial UI updates and diffing in Ditto SDK 5.2.0 (Swift, DittoSwift 5.2.0, SwiftUI).
//
// Patterns: 1. one small observer per screen region; 2. a List with
// Identifiable rows (no DittoDiffer needed); 3. DittoDiffer to log what
// changed; 4. DittoDiffer driving UITableView batch updates (iOS); 5. one broad
// observer at the root of the screen (bad).
//
// Facts:
// - Assigning an equal value to a @Published property still makes every view
//   that observes the object re-evaluate its body: publish only real changes,
//   and map rows to Equatable values.
// - DittoDiffer().diff(result.items) returns insertions and updates (indexes in
//   the NEW list), deletions (indexes in the OLD list), and moves; the first
//   call reports every item as an insertion. Keep one differ per observer.
//
// Guide: § Partial UI updates in Swift, § Diffing results in Swift, § Partial UI Updates, § Diffing Results

import DittoSwift
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// PATTERN 1: One observer per region

/// ✅ GOOD: The badge observes a count and publishes only when it changes.
@MainActor
final class OpenOrdersBadgeModel: ObservableObject {
    @Published private(set) var count = 0
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto) {
        guard observer == nil else { return }
        observer = try? ditto.store.registerObserver(
            query: "SELECT COUNT(*) AS n FROM orders WHERE status = :status", arguments: ["status": "open"]
        ) { [weak self] result in
            let n = result.items.first?.value["n"] as? Int ?? 0
            MainActor.assumeIsolated { if self?.count != n { self?.count = n } }
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }
}

struct OpenOrdersBadge: View {
    let ditto: Ditto
    @StateObject private var model = OpenOrdersBadgeModel()

    var body: some View {
        Text("Open orders: \(model.count)")
            .onAppear { model.start(ditto) }
            .onDisappear { model.stop() }
    }
}

// PATTERN 2: Identifiable rows

struct OrderSummary: Identifiable, Equatable {
    let id: String
    let status: String
}

/// ✅ GOOD: Rows with stable identity (_id): SwiftUI updates only the rows
/// that changed, without DittoDiffer.
@MainActor
final class OrderSummariesModel: ObservableObject {
    @Published private(set) var rows: [OrderSummary] = []
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto, status: String) {
        observer?.cancel()
        observer = try? ditto.store.registerObserver(
            query: "SELECT _id, status FROM orders WHERE status = :status ORDER BY createdAt DESC, _id LIMIT 200",
            arguments: ["status": status]
        ) { [weak self] result in
            let rows = result.items.compactMap { item in
                (item.value["_id"] as? String).map { OrderSummary(id: $0, status: item.value["status"] as? String ?? "") }
            }
            MainActor.assumeIsolated { if self?.rows != rows { self?.rows = rows } }
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }
}

struct OrderSummaries: View {
    let ditto: Ditto
    @StateObject private var model = OrderSummariesModel()

    var body: some View {
        List(model.rows) { row in Text(row.id) }
            .onAppear { model.start(ditto, status: "open") }
            .onDisappear { model.stop() }
    }
}

/// ✅ GOOD: The screen itself observes nothing; each region updates independently.
struct OrdersRegionsScreen: View {
    let ditto: Ditto

    var body: some View {
        VStack {
            OpenOrdersBadge(ditto: ditto)
            OrderSummaries(ditto: ditto)
        }
    }
}

// PATTERN 3: Logging changes with DittoDiffer

/// ✅ GOOD: Report inserted, deleted, updated, and moved documents. The state
/// is touched only on the observer's serial queue.
final class RecentOrderChanges: @unchecked Sendable {
    private let differ = DittoDiffer()
    private var previousIDs: [String] = []
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto) throws {
        observer = try ditto.store.registerObserver(
            query: "SELECT _id, status FROM orders ORDER BY createdAt DESC, _id LIMIT 100",
            deliverOn: DispatchQueue(label: "orders.changes")
        ) { [weak self] result in
            guard let self else { return }
            let diff = differ.diff(result.items)
            let ids = result.items.map { $0.value["_id"] as? String ?? "" }
            for index in diff.deletions { print("deleted", previousIDs[index]) }
            for index in diff.insertions { print("inserted", ids[index]) }
            for index in diff.updates { print("updated", ids[index]) }
            for move in diff.moves { print("moved", move.from, "->", move.to) }
            previousIDs = ids
        }
    }

    func stop() { observer?.cancel() }
}

#if canImport(UIKit)
// PATTERN 4: DittoDiffer driving UITableView batch updates (iOS)

/// ✅ GOOD: Deletions against the old rows and insertions against the new
/// ones in one batch; moves as a deletion plus an insertion; updates reloaded
/// after the batch.
func applyDiff(_ diff: DittoDiff, to tableView: UITableView, update: () -> Void) {
    tableView.performBatchUpdates {
        update()
        tableView.deleteRows(at: (Array(diff.deletions) + diff.moves.map(\.from)).map { IndexPath(row: $0, section: 0) }, with: .automatic)
        tableView.insertRows(at: (Array(diff.insertions) + diff.moves.map(\.to)).map { IndexPath(row: $0, section: 0) }, with: .automatic)
    }
    let updated = diff.updates.map { IndexPath(row: $0, section: 0) }
    if !updated.isEmpty { tableView.reloadRows(at: updated, with: .none) }
}
#endif

// ANTI-PATTERN 5: One broad observer at the root

/// ❌ BAD: The root model observes every order and publishes the whole list on
/// every change, so the title, the filters, and every row update each time.
@MainActor
final class WholeOrdersScreenModel: ObservableObject {
    @Published var orders: [[String: Any?]] = []
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto) {
        observer = try? ditto.store.registerObserver(query: "SELECT * FROM orders") { [weak self] result in
            let orders = result.items.map { $0.value }
            MainActor.assumeIsolated { self?.orders = orders }
        }
    }

    func stop() { observer?.cancel() }
}
