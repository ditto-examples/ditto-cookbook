// Diffing observer results with DittoDiffer in Ditto SDK 5.2.0 (Swift, DittoSwift 5.2.0).
//
// An observer delivers the complete result every time. DittoDiffer compares
// successive results by _id and returns a DittoDiff:
// - insertions: indexes in the NEW list of items that were added
// - deletions:  indexes in the OLD list of items that were removed
// - updates:    indexes in the NEW list of items whose value changed
// - moves:      [(from: oldIndex, to: newIndex)]
//
// Facts:
// - diff(_:) takes [DittoQueryResultItem]: pass result.items.
// - The first call reports every item as an insertion.
// - Keep one DittoDiffer per observer, used on one serial queue: it keeps the
//   previous result. Keep diffed queries bounded (LIMIT).
// - DittoDiffer does not return old items: keep previous values (or IDs).
// - DittoDiffer only accepts items produced by Ditto.
// - SwiftUI's List and ForEach with stable identifiers (_id) compute their own
//   differences and do not need DittoDiffer.
//
// Guide: § Diffing results in Swift, § Diffing Results

import DittoSwift
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// ✅ GOOD: Logging changes between results. Only the observer's serial
/// queue touches the state of this object.
final class OrderChangeLog: @unchecked Sendable {
    private let differ = DittoDiffer()
    private var previousIDs: [String] = []
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto) throws {
        observer = try ditto.store.registerObserver(
            query: "SELECT * FROM orders ORDER BY createdAt, _id LIMIT 200",
            deliverOn: DispatchQueue(label: "orders.diff")
        ) { [weak self] result in
            self?.log(result)
        }
    }

    private func log(_ result: DittoQueryResult) {
        let diff = differ.diff(result.items)
        let currentIDs = result.items.map { $0.value["_id"] as? String ?? "" }
        for index in diff.deletions { print("deleted", previousIDs[index]) } // index into the OLD list
        for index in diff.insertions { print("inserted", currentIDs[index]) } // index into the NEW list
        for index in diff.updates { print("updated", currentIDs[index]) } // index into the NEW list
        for move in diff.moves { print("moved", move.from, "->", move.to) }
        previousIDs = currentIDs
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }
}

#if canImport(UIKit)
/// ✅ GOOD: Driving UITableView batch updates from a DittoDiff (iOS). Deletions
/// refer to the old rows and insertions to the new ones, in one batch; a move is
/// a deletion plus an insertion; updated rows are reloaded after the batch.
final class OrdersTableController: UITableViewController {
    private let ditto: Ditto
    private let differ = DittoDiffer()
    private var observer: DittoStoreObserver?
    private var orders: [[String: Any?]] = []

    init(ditto: Ditto) {
        self.ditto = ditto
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "order")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        observer = try? ditto.store.registerObserver(
            query: "SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id LIMIT 200",
            arguments: ["status": "open"]
        ) { [weak self] result in
            MainActor.assumeIsolated { self?.apply(result) }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        observer?.cancel()
        observer = nil
    }

    private func apply(_ result: DittoQueryResult) {
        let diff = differ.diff(result.items)
        let next = result.items.map { $0.value }
        tableView.performBatchUpdates {
            orders = next
            let deleted = diff.deletions.map { IndexPath(row: $0, section: 0) }
                + diff.moves.map { IndexPath(row: $0.from, section: 0) }
            let inserted = diff.insertions.map { IndexPath(row: $0, section: 0) }
                + diff.moves.map { IndexPath(row: $0.to, section: 0) }
            tableView.deleteRows(at: deleted, with: .automatic)
            tableView.insertRows(at: inserted, with: .automatic)
        }
        let updated = diff.updates.map { IndexPath(row: $0, section: 0) }
        if !updated.isEmpty { tableView.reloadRows(at: updated, with: .none) }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { orders.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "order", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = orders[indexPath.row]["_id"] as? String
        cell.contentConfiguration = content
        return cell
    }
}
#endif

/// ❌ BAD: Diffing an unbounded observer of a whole collection. The differ keeps
/// the full previous result and compares every item on every change. Add a
/// WHERE filter and a LIMIT, or skip DittoDiffer when keyed rows are enough.
func diffEverything(_ ditto: Ditto) throws -> DittoStoreObserver {
    let differ = DittoDiffer()
    return try ditto.store.registerObserver(query: "SELECT * FROM orders ORDER BY _id",
                                            deliverOn: DispatchQueue(label: "diff.all")) { result in
        print(differ.diff(result.items).insertions.count, "inserted")
    }
}
