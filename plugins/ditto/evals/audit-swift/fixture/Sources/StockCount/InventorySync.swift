import DittoSwift
import Foundation

/// Owns the subscription of the warehouse that the iPad is counting in.
@MainActor
final class InventorySync {
    private let sync: DittoSync
    private var subscription: DittoSyncSubscription?
    private var warehouseID: String?

    init(sync: DittoSync) {
        self.sync = sync
    }

    func enterWarehouse(_ warehouseID: String) throws {
        guard warehouseID != self.warehouseID else { return }
        leaveWarehouse()
        subscription = try sync.registerSubscription(
            query: "SELECT * FROM items WHERE warehouseId = :warehouseId",
            arguments: ["warehouseId": warehouseID]
        )
        self.warehouseID = warehouseID
    }

    func leaveWarehouse() {
        subscription?.cancel()
        subscription = nil
        warehouseID = nil
    }
}
