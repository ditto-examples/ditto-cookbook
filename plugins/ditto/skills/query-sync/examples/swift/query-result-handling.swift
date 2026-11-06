// Handling DittoQueryResult and DittoQueryResultItem in Ditto SDK 5.2.0 (Swift, DittoSwift 5.2.0).
//
// Rules:
// - items is an array of DittoQueryResultItem. item.value is a [String: Any?]
//   dictionary, decoded on the first read and kept by the item; it is a copy:
//   changing it changes neither the item nor the store.
// - item.jsonData() returns the row as UTF-8 JSON for JSONDecoder;
//   item.cborData() returns CBOR. dematerialize() releases the decoded row.
// - mutatedDocumentIDs() returns [DittoDocumentID]; use stringValue for string
//   IDs. commitID is a UInt64?, nil for reads. A write that changed nothing
//   still gets a commitID, which peers confirm only with their next sync
//   exchange (up to about 27 s), so track it only when mutatedDocumentIDs() is
//   not empty.
// - Copy what you need into your own values; do not keep DittoQueryResult or
//   DittoQueryResultItem objects in state, caches, or across observer calls.
//
// Guide: § Query results in Swift, § Working with Query Results

import DittoSwift
import Foundation

/// A plain, immutable model decoded from a result row. Fields that older
/// documents or concurrent edits can lack are optional.
struct Order: Decodable, Identifiable, Equatable {
    let id: String
    let status: String?
    let total: Double? // an integer total decodes too

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case status, total
    }
}

/// ✅ GOOD: Project only the needed fields, decode each row once, return models.
/// A row that does not decode is skipped instead of failing the list.
func loadOpenOrders(_ ditto: Ditto) async throws -> [Order] {
    let result = try await ditto.store.execute(
        query: "SELECT _id, status, total FROM orders WHERE status = :status ORDER BY _id",
        arguments: ["status": "open"]
    )
    let decoder = JSONDecoder()
    return result.items.compactMap { try? decoder.decode(Order.self, from: $0.jsonData()) }
}

/// ✅ GOOD: Read a single row and keep the value, not the item.
func loadOrder(_ ditto: Ditto, id: String) async throws -> Order? {
    let result = try await ditto.store.execute(
        query: "SELECT _id, status, total FROM orders WHERE _id = :id",
        arguments: ["id": id]
    )
    guard let item = result.items.first else { return nil }
    return try JSONDecoder().decode(Order.self, from: item.jsonData())
}

/// ✅ GOOD: Inspect which documents changed, calling mutatedDocumentIDs() once.
func closeOrders(_ ditto: Ditto, ids: [String]) async throws -> (changedIDs: [String], commitID: UInt64?) {
    let result = try await ditto.store.execute(
        query: "UPDATE orders SET status = :status WHERE _id IN :ids",
        arguments: ["status": "closed", "ids": ids]
    )
    let changedIDs = result.mutatedDocumentIDs().map { $0.stringValue }
    // Nothing to track when no document changed (for example, unknown IDs).
    return (changedIDs, changedIDs.isEmpty ? nil : result.commitID)
}

/// ✅ GOOD: Alternative encodings, for example to hand rows to another process.
func openOrdersAsJSON(_ ditto: Ditto) async throws -> [String] {
    let result = try await ditto.store.execute(
        query: "SELECT * FROM orders WHERE status = :status ORDER BY _id",
        arguments: ["status": "open"]
    )
    return result.items.map { String(decoding: $0.jsonData(), as: UTF8.self) }
}

/// ✅ GOOD: A cache holds plain models, never query results.
final class OrderCache {
    private var byID: [String: Order] = [:]

    func update(_ result: DittoQueryResult) {
        let decoder = JSONDecoder()
        byID = Dictionary(uniqueKeysWithValues: result.items.compactMap { item in
            (try? decoder.decode(Order.self, from: item.jsonData())).map { ($0.id, $0) }
        })
        // The DittoQueryResult goes out of scope after this method returns.
    }

    subscript(id: String) -> Order? { byID[id] }
}

/// ❌ BAD: Keeping DittoQueryResultItem objects alive in a cache. Each one
/// keeps its row (and its decoded value once read) in memory.
final class RetainingCache {
    private var items: [DittoQueryResultItem] = []

    func update(_ result: DittoQueryResult) {
        items = result.items
    }

    var count: Int { items.count }
}

/// ❌ BAD: Changing item.value to edit the document. The dictionary is a copy;
/// nothing reaches the store. Write the change with UPDATE.
func renameLocallyOnly(_ ditto: Ditto, id: String) async throws {
    let result = try await ditto.store.execute(query: "SELECT * FROM orders WHERE _id = :id", arguments: ["id": id])
    guard var order = result.items.first?.value else { return }
    order["status"] = "closed" // changes only this copy
    print(order)
}
