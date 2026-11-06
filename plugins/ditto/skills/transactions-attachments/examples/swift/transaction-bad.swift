// Ditto SDK 5.2 (Swift, DittoSwift 5.2.0): Transaction anti-patterns
//
// Guide: § Transaction Rules, § Transactions in Swift, § Concurrency and Duration
//
// Every function below compiles. The problems appear at runtime
// (Note (SDK 5.1.0 and 5.2.0) for the observed ones).
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ ditto.store.execute (or tx.store.execute) inside a transaction
// 2. ❌ A nested read-write transaction
// 3. ❌ Network calls or timers inside a transaction
// 4. ❌ Keeping the DittoTransaction and using it later
// 5. ❌ Swallowing an error and committing a half-done change
// 6. ❌ Many concurrent writes while a transaction is open
// 7. ❌ Releasing the last reference to Ditto on the main thread during a transaction
// 8. ❌ Wrapping a single statement in a transaction (adds nothing)
//
// A scope that returns nothing does not compile; return .commit or a value.
// See transaction-good.swift for the correct patterns.

import DittoSwift
import Foundation

/// ❌ BAD: A write through ditto.store.execute inside a read-write transaction
/// never returns, and every later write waits behind it. tx.store is
/// ditto.store itself, so tx.store.execute is the same mistake. Reads through
/// ditto.store.execute return but do not see the transaction's own writes.
func storeExecuteInsideTransaction(_ ditto: Ditto, orderID: String) async throws {
    try await ditto.store.transaction { tx in
        try await tx.execute(query: "UPDATE orders SET status = 'closing' WHERE _id = :id", arguments: ["id": orderID])
        try await ditto.store.execute(query: "UPDATE orders SET status = 'closed' WHERE _id = :id", arguments: ["id": orderID])
        return .commit
    }
}

/// ❌ BAD: Only one read-write transaction runs at a time; the inner one waits
/// for the outer one, which waits for the inner one.
func nestedTransaction(_ ditto: Ditto, orderID: String) async throws {
    try await ditto.store.transaction { tx in
        try await tx.execute(query: "UPDATE orders SET status = 'paid' WHERE _id = :id", arguments: ["id": orderID])
        try await recordPaymentDate(ditto, orderID: orderID) // starts its own transaction
        return .commit
    }
}

private func recordPaymentDate(_ ditto: Ditto, orderID: String) async throws {
    try await ditto.store.transaction { tx in
        try await tx.execute(query: "UPDATE orders SET paidAt = :now WHERE _id = :id",
                             arguments: ["id": orderID, "now": Date().timeIntervalSince1970])
        return .commit
    }
}
// ✅ Fix: pass the outer DittoTransaction to helpers instead of starting a new one.

/// ❌ BAD: While this transaction waits for the network, every other write,
/// and every change from other devices, waits too.
func networkInsideTransaction(_ ditto: Ditto, orderID: String, chargeCard: @escaping @Sendable () async throws -> Void) async throws {
    try await ditto.store.transaction { tx in
        try await chargeCard()
        try await tx.execute(query: "UPDATE orders SET status = 'paid' WHERE _id = :id", arguments: ["id": orderID])
        return .commit
    }
}
// ✅ Fix: call chargeCard() first, then record the result in one short transaction.

/// ❌ BAD: A DittoTransaction is only valid inside its scope. Using it later
/// throws DittoError.storeError(reason: .backendError(message: "<store> No
/// active write transaction found with id ...")). commitID is nil inside the
/// transaction as well: read it from a write after the transaction.
final class LeakyOrderService: @unchecked Sendable {
    private var lastTransaction: DittoTransaction?

    func begin(_ ditto: Ditto) async throws {
        try await ditto.store.transaction { tx in
            self.lastTransaction = tx
            return .commit
        }
    }

    func finishLater(orderID: String) async throws {
        try await lastTransaction?.execute(query: "UPDATE orders SET status = 'done' WHERE _id = :id", arguments: ["id": orderID])
    }
}

/// ❌ BAD: A caught error does not roll back: the order is marked closed even
/// though the invoice was not written.
func swallowedError(_ ditto: Ditto, orderID: String, invoiceID: String) async throws {
    try await ditto.store.transaction { tx in
        try await tx.execute(query: "UPDATE orders SET status = 'closed' WHERE _id = :id", arguments: ["id": orderID])
        do {
            try await tx.execute(query: "INSERT INTO invoices DOCUMENTS (:i)", arguments: ["i": ["_id": invoiceID]])
        } catch {
            print("invoice failed: \(error)") // and then commits anyway
        }
        return .commit
    }
}
// ✅ Fix: rethrow, or return .rollback.

/// ❌ BAD: One task per write while a transaction may be open. Each waiting
/// write holds a thread of the cooperative pool; once every thread waits, the
/// transaction cannot resume, and every task of the process stops.
func recordScansConcurrently(_ ditto: Ditto, scans: [[String: Any?]]) {
    for scan in scans {
        Task.detached {
            try await ditto.store.execute(query: "INSERT INTO scans DOCUMENTS (:scan)", arguments: ["scan": scan])
        }
    }
}

/// ❌ BAD: Releasing the last reference to Ditto runs deinit, which waits for
/// every open transaction; on the main thread, the UI freezes until then.
@MainActor
final class MainThreadShutdown {
    var ditto: Ditto?

    func signOut() {
        ditto = nil // blocks the main thread while a transaction is open
    }
}

/// ❌ BAD (unnecessary): A single UPDATE is already atomic. The transaction
/// only adds overhead and holds the write lock longer.
func singleStatementTransaction(_ ditto: Ditto, orderID: String) async throws {
    try await ditto.store.transaction { tx in
        try await tx.execute(query: "UPDATE orders SET status = 'open' WHERE _id = :id", arguments: ["id": orderID])
        return .commit
    }
}
// ✅ Fix: call ditto.store.execute(...) directly.
