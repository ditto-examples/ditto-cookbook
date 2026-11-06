// Ditto SDK: 5.2.0 (Swift, DittoSwift 5.2.0, Swift Testing)
//
// Local store tests: merge-sensitive writes, deletion and soft delete, observer
// lifecycle, subscription rules, and DQL validation with EXPLAIN. Each test uses
// withTestDitto from local-store-test-helper.swift, so every test gets its own
// empty store. The statements under test are inline so that each test is
// complete; in your suite, call your app's repository functions instead.
//
// What each test checks, as DQL and expected results, is in
// ../../reference/local-store-tests.md and in the guide's Testing Strategies; the same
// tests for the other SDKs are in examples/<sdk>/ with the same base name.
//
// Guide: § Testing Merge-Sensitive Writes, § Testing Deletion and Soft Delete, § Testing Observer Lifecycle, § Testing Subscription Rules, § Validating DQL in Tests, § Testing in Swift

// Tests/OrdersTests/LocalStoreTests.swift
import DittoSwift
import Foundation
import Testing

/// The rows of a query as an async sequence; cancelling the task that iterates
/// it, or releasing the stream, cancels the observer (as on the Swift page).
extension DittoStore {
    func rows(query: String, arguments: [String: Any?] = [:]) -> AsyncStream<[[String: Any?]]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            do {
                let observer = try registerObserver(
                    query: query, arguments: arguments, deliverOn: DispatchQueue(label: "ditto.rows")
                ) { result in
                    continuation.yield(result.items.map { $0.value })
                }
                continuation.onTermination = { _ in observer.cancel() }
            } catch {
                continuation.finish()
            }
        }
    }
}

@Test func addingALineItemKeepsTheExistingItems() async throws {
    try await withTestDitto { ditto in
        try await ditto.store.execute(
            query: "INSERT INTO orders DOCUMENTS (:order)",
            arguments: ["order": ["_id": "order-1", "items": ["item-1": ["productId": "p1", "quantity": 2]]]]
        )

        // The code under test: an upsert of a partial document (see "Arrays and Maps").
        try await ditto.store.execute(
            query: "INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF",
            arguments: ["patch": ["_id": "order-1", "items": ["item-2": ["productId": "p2", "quantity": 1]]]]
        )

        let result = try await ditto.store.execute(query: "SELECT * FROM orders WHERE _id = :id", arguments: ["id": "order-1"])
        let items = try #require(result.items.first?.value["items"] as? [String: Any?]) // a map, not an array
        #expect(Set(items.keys) == ["item-1", "item-2"])
    }
}

@Test func reUpsertingUnchangedDataIsANoOp() async throws {
    try await withTestDitto { ditto in
        let product: [String: Any?] = ["_id": "p1", "name": "Pen", "priceCents": 250]
        try await ditto.store.execute(
            query: "INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF",
            arguments: ["product": product]
        )
        let again = try await ditto.store.execute(
            query: "INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF",
            arguments: ["product": product]
        )
        #expect(again.mutatedDocumentIDs().isEmpty)
    }
}

// The code under test: the app's replaceAddress() (see "Assigning an object merges it").
func replaceAddress(_ ditto: Ditto, customerID: String, address: [String: Any?]) async throws {
    try await ditto.store.transaction(hint: "replaceAddress") { tx in
        try await tx.execute(query: "UPDATE customers UNSET address WHERE _id = :id", arguments: ["id": customerID])
        try await tx.execute(
            query: "UPDATE customers SET address = :address WHERE _id = :id",
            arguments: ["id": customerID, "address": address]
        )
        return .commit
    }
}

@Test func replaceAddressRemovesKeysThatAreNotInTheNewAddress() async throws {
    try await withTestDitto { ditto in
        try await ditto.store.execute(
            query: "INSERT INTO customers DOCUMENTS (:customer)",
            arguments: ["customer": ["_id": "c1", "address": ["city": "Oslo", "zip": "0150"]]]
        )
        try await replaceAddress(ditto, customerID: "c1", address: ["city": "Bergen"])

        let result = try await ditto.store.execute(query: "SELECT * FROM customers WHERE _id = :id", arguments: ["id": "c1"])
        // A plain SET would keep "zip": objects merge under the default settings.
        let address = try #require(result.items.first?.value["address"] as? [String: Any?])
        #expect(address.keys.sorted() == ["city"])
        #expect(address["city"] as? String == "Bergen")
    }
}

@Test func activeOrdersQueryTreatsAMissingOrNullFlagAsNotDeleted() async throws {
    try await withTestDitto { ditto in
        try await ditto.store.execute(
            query: "INSERT INTO orders DOCUMENTS (:orders)",
            arguments: ["orders": [
                ["_id": "deleted", "isDeleted": true],
                ["_id": "active", "isDeleted": false],
                ["_id": "nullFlag", "isDeleted": nil] as [String: Any?],
                ["_id": "noFlag"],
            ]]
        )

        // The query used by the app's repository.
        let result = try await ditto.store.execute(
            query: "SELECT _id FROM orders WHERE coalesce(isDeleted, false) = false ORDER BY _id"
        )
        #expect(result.items.map { $0.value["_id"] as? String } == ["active", "noFlag", "nullFlag"])
    }
}

@Test func deletingByIDRemovesExactlyTheListedDocuments() async throws {
    try await withTestDitto { ditto in
        try await ditto.store.execute(
            query: "INSERT INTO orders DOCUMENTS (:orders)",
            arguments: ["orders": [["_id": "o1"], ["_id": "o2"], ["_id": "o3"]]]
        )

        // The statement used by the app; WHERE _id IN :ids, not USE IDS.
        let deleted = try await ditto.store.execute(
            query: "DELETE FROM orders WHERE _id IN :ids", arguments: ["ids": ["o1", "o2"]]
        )
        #expect(deleted.mutatedDocumentIDs().count == 2)

        let remaining = try await ditto.store.execute(query: "SELECT _id FROM orders")
        #expect(remaining.items.map { $0.value["_id"] as? String } == ["o3"])
    }
}

@Test func observerSeesANewOrderAndIsCancelledCleanly() async throws {
    try await withTestDitto { ditto in
        let sawOrder = Task {
            // Created inside the task, so that the stream is released with it.
            let stream = ditto.store.rows(
                query: "SELECT * FROM orders WHERE status = :status ORDER BY _id",
                arguments: ["status": "open"]
            )
            for await rows in stream where rows.count == 1 { return true }
            return false
        }

        try await ditto.store.execute(
            query: "INSERT INTO orders DOCUMENTS (:order)",
            arguments: ["order": ["_id": "order-1", "status": "open"]]
        )
        let timeout = Task { try await Task.sleep(nanoseconds: 5_000_000_000); sawOrder.cancel() }
        #expect(await sawOrder.value)
        timeout.cancel()

        // The task has ended and released the stream, which cancelled the observer.
        #expect(ditto.store.observers.isEmpty)
    }
}

@Test func subscriptionsWithOrderByAndLimitOrJoinAreRejected() async throws {
    try await withTestDitto { ditto in
        #expect(throws: DittoError.self) {
            try ditto.sync.registerSubscription(query: "SELECT * FROM orders ORDER BY createdAt DESC LIMIT 50")
        }
        #expect(throws: DittoError.self) {
            try ditto.sync.registerSubscription(query: "SELECT * FROM orders o JOIN customers c ON o.customerId = c._id")
        }
    }
}

@Test func theAppsSubscriptionsAreValid() async throws {
    try await withTestDitto { ditto in
        let subscriptions = [
            try ditto.sync.registerSubscription(
                query: "SELECT * FROM orders WHERE storeId = :storeId", arguments: ["storeId": "store-1"]
            ),
            try ditto.sync.registerSubscription(query: "SELECT * FROM products"),
        ]
        for subscription in subscriptions {
            subscription.cancel()
            #expect(subscription.isCancelled)
        }
    }
}

/// The app's statements with representative arguments. In a real app, keep
/// the statement strings in your repository and reference them here.
let appStatements: [(statement: String, arguments: [String: Any?])] = [
    ("SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC", ["status": "open"]),
    ("UPDATE orders SET status = :status WHERE _id = :id", ["status": "closed", "id": "order-1"]),
    ("DELETE FROM orders WHERE _id IN :ids", ["ids": ["order-1"]]),
]

@Test func everyAppStatementCanBePlanned() async throws {
    try await withTestDitto { ditto in
        for (statement, arguments) in appStatements {
            // EXPLAIN throws if a statement cannot be parsed or planned.
            try await ditto.store.execute(query: "EXPLAIN \(statement)", arguments: arguments)
        }
    }
}

@Test func theOpenOrdersQueryUsesItsIndex() async throws {
    // In your suite, create indexes with the same startup code as the app
    // (for example, through the configure parameter of withTestDitto).
    try await withTestDitto(configure: { ditto in
        try await ditto.store.execute(
            query: "CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt ON orders (status, createdAt DESC)"
        )
    }) { ditto in
        let plan = try await ditto.store.execute(
            query: "EXPLAIN SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC",
            arguments: ["status": "open"]
        )
        let json = String(decoding: plan.items.first?.jsonData() ?? Data(), as: UTF8.self)
        #expect(json.contains("indexScan"))
    }
}
