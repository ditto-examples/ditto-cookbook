import DittoSwift
import Foundation

enum ItemError: Error { case invalid }

/// Returns a random (version 4) UUID in lowercase.
func newID() -> String {
    UUID().uuidString.lowercased()
}

/// Returns the time as an ISO 8601 UTC string with exactly millisecond precision.
func utcTimestamp(_ date: Date = Date()) -> String {
    Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
}

struct Item: Decodable, Identifiable, Equatable {
    let id: String
    let sku: String
    let name: String?
    let location: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case sku, name, location
    }
}

final class ItemRepository: Sendable {
    private let store: DittoStore

    init(store: DittoStore) {
        self.store = store
    }

    func createItem(warehouseID: String, sku: String, name: String, unitPrice: Double) async throws -> String {
        guard !warehouseID.isEmpty, !sku.isEmpty else { throw ItemError.invalid }
        let id = newID()
        let item: [String: Any?] = [
            "_id": id,
            "warehouseId": warehouseID,
            "sku": sku,
            "name": name,
            "unitPrice": unitPrice,
            "createdAt": utcTimestamp(),
        ]
        try await store.execute(query: "INSERT INTO items DOCUMENTS (:item)", arguments: ["item": item])
        return id
    }

    func moveItem(id: String, to location: String) async throws {
        guard !id.isEmpty, !location.isEmpty else { throw ItemError.invalid }
        try await store.execute(
            query: "UPDATE items SET location = :location WHERE _id = :id",
            arguments: ["id": id, "location": location]
        )
    }

    /// Records the quantity counted on this iPad for one item.
    func recordCount(itemID: String, quantity: Int) async throws {
        try await store.execute(
            query: "UPDATE items SET countedQuantity = :quantity, countedAt = :countedAt WHERE _id = :id",
            arguments: ["id": itemID, "quantity": quantity, "countedAt": Date()]
        )
    }

    /// The items that the user selected on the count sheet.
    func items(withIDs ids: [String]) async throws -> [Item] {
        let result = try await store.execute(
            query: "SELECT * FROM items WHERE _id IN (:ids) ORDER BY sku, _id",
            arguments: ["ids": ids]
        )
        let decoder = JSONDecoder()
        return result.items.compactMap { try? decoder.decode(Item.self, from: $0.jsonData()) }
    }

    /// Total value of the counted stock of a warehouse, in the warehouse currency.
    func countedStockValue(warehouseID: String) async throws -> Double {
        let result = try await store.execute(
            query: "SELECT unitPrice, countedQuantity FROM items WHERE warehouseId = :warehouseId",
            arguments: ["warehouseId": warehouseID]
        )
        var total = 0.0
        for item in result.items {
            let unitPrice = item.value["unitPrice"] as? Double ?? 0
            let quantity = item.value["countedQuantity"] as? Int ?? 0
            total += unitPrice * Double(quantity)
        }
        return total
    }
}
