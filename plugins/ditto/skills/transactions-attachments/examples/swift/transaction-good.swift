// Ditto SDK 5.2 (Swift, DittoSwift 5.2.0): Transaction patterns
//
// Guide: § Transactions, § Transactions in Swift, § Transaction Rules
//
// DittoStore.transaction has two forms: a scope that returns
// DittoTransactionCompletionAction (.commit or .rollback), and a generic one
// whose return value commits. A scope that returns nothing does not compile
// ("missing return in closure expected to return 'DittoTransactionCompletionAction'"):
// return .commit. Throwing rolls back and rethrows the original error.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Atomic multi-document change that uses only tx.execute
// 2. ✅ Explicit rollback with DittoTransactionCompletionAction
// 3. ✅ Read-only transaction for a consistent snapshot, with a typed result
// 4. ✅ I/O before the transaction, short transaction afterwards
// 5. ✅ Handling a failed statement deliberately
// 6. ✅ One writer task instead of many concurrent writes
// 7. ✅ Releasing Ditto off the main thread (the release waits for open transactions)

import DittoSwift
import Foundation

/// ISO 8601 UTC timestamp with exactly millisecond precision, for example
/// "2026-10-08T10:30:00.123Z".
private func utcTimestamp(_ date: Date = Date()) -> String {
    Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
}

struct OrderNotFound: Error { let id: String }

// PATTERN 1: Atomic multi-document change

/// ✅ GOOD: Close an order and create its invoice atomically.
func closeOrderWithInvoice(_ ditto: Ditto, orderID: String, invoiceID: String) async throws {
    try await ditto.store.transaction(hint: "closeOrderWithInvoice") { tx in // the hint appears in logs
        let result = try await tx.execute(query: "SELECT * FROM orders WHERE _id = :id", arguments: ["id": orderID])
        guard let order = result.items.first?.value else { throw OrderNotFound(id: orderID) } // rolls back
        let invoice: [String: Any?] = [
            "_id": invoiceID,
            "orderId": orderID,
            "total": order["total"] ?? nil,
            "createdAt": utcTimestamp(),
        ]
        try await tx.execute(query: "INSERT INTO invoices DOCUMENTS (:invoice)", arguments: ["invoice": invoice])
        try await tx.execute(
            query: "UPDATE orders SET status = :status, invoiceId = :invoiceId WHERE _id = :id",
            arguments: ["id": orderID, "status": "closed", "invoiceId": invoiceID]
        )
        return .commit
    }
}

// PATTERN 2: Explicit rollback

/// ✅ GOOD: Returns true when the order was shipped.
func shipOrder(_ ditto: Ditto, orderID: String) async throws -> Bool {
    let action = try await ditto.store.transaction(hint: "shipOrder") { tx in
        let paid = try await tx.execute(
            query: "SELECT _id FROM orders WHERE _id = :id AND status = :status",
            arguments: ["id": orderID, "status": "paid"]
        )
        if paid.items.isEmpty { return .rollback } // nothing to ship
        try await tx.execute(
            query: "UPDATE orders SET status = :status WHERE _id = :id", arguments: ["id": orderID, "status": "shipped"]
        )
        return .commit
    }
    return action == .commit
}

// PATTERN 3: Read-only snapshot

/// ✅ GOOD: Both counts are read from the same snapshot.
func orderCounts(_ ditto: Ditto) async throws -> (open: Int, closed: Int) {
    try await ditto.store.transaction(hint: "orderCounts", isReadOnly: true) { tx in
        let open = try await tx.execute(query: "SELECT COUNT(*) AS n FROM orders WHERE status = 'open'")
        let closed = try await tx.execute(query: "SELECT COUNT(*) AS n FROM orders WHERE status = 'closed'")
        return (open.items.first?.value["n"] as? Int ?? 0, closed.items.first?.value["n"] as? Int ?? 0)
    }
}

// PATTERN 4: I/O first, then a short transaction

/// ✅ GOOD: The payment call happens before the transaction starts, so no other
/// write, and no change from other devices, waits for the network.
func checkout(_ ditto: Ditto, orderID: String, chargeCard: () async throws -> String) async throws {
    let paymentID = try await chargeCard()
    try await ditto.store.transaction(hint: "recordPayment") { tx in
        try await tx.execute(
            query: "UPDATE orders SET status = 'paid', paidAt = :paidAt WHERE _id = :id",
            arguments: ["id": orderID, "paidAt": utcTimestamp()]
        )
        try await tx.execute(
            query: "INSERT INTO payments DOCUMENTS (:payment)",
            arguments: ["payment": ["_id": paymentID, "orderId": orderID]]
        )
        return .commit
    }
}

// PATTERN 5: A failed statement, handled deliberately

/// ✅ GOOD: A caught error does NOT roll back the transaction: the statements
/// before and after it are committed. Decide explicitly, here by rolling back.
func reserveItem(_ ditto: Ditto, itemID: String, auditID: String) async throws -> Bool {
    let action = try await ditto.store.transaction(hint: "reserveItem") { tx in
        try await tx.execute(
            query: "UPDATE items SET reserved = true WHERE _id = :id", arguments: ["id": itemID]
        )
        do {
            // Fails if the audit entry exists already (an INSERT without ON ID CONFLICT).
            try await tx.execute(
                query: "INSERT INTO audit DOCUMENTS (:entry)",
                arguments: ["entry": ["_id": auditID, "itemId": itemID, "at": utcTimestamp()]]
            )
        } catch {
            return .rollback // also undoes the reservation above
        }
        return .commit
    }
    return action == .commit
}

// PATTERN 6: One writer instead of many concurrent writes

/// ✅ GOOD: Writes go through one actor, in order. Many concurrent store.execute
/// calls that wait for an open transaction each hold a thread of Swift's
/// cooperative pool; once every thread waits, the transaction and every task of
/// the process stop (14 writes on a 14-core Mac; fewer on a phone).
actor OrderWriter {
    private let ditto: Ditto

    init(ditto: Ditto) {
        self.ditto = ditto
    }

    func record(_ orders: [[String: Any?]]) async throws {
        // One statement for the batch; or a loop of awaited writes.
        try await ditto.store.execute(
            query: "INSERT INTO orders DOCUMENTS (:orders) ON ID CONFLICT DO UPDATE_LOCAL_DIFF",
            arguments: ["orders": orders]
        )
    }
}

// PATTERN 7: Releasing Ditto off the main thread

/// ✅ GOOD: Releasing the last reference to Ditto (DittoSwift 5.2.0 has no
/// close()) waits in deinit until every open transaction has ended, so let the
/// last reference go on a background task, not on the main thread.
final class DittoOwner: @unchecked Sendable {
    private(set) var ditto: Ditto?

    init(ditto: Ditto) {
        self.ditto = ditto
    }

    func shutDown() async {
        ditto?.sync.stop()
        let last = ditto
        ditto = nil
        await Task.detached { withExtendedLifetime(last) {} }.value
    }
}
