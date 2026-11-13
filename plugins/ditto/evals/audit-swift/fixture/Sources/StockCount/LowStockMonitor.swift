import DittoSwift
import Foundation

/// Shows a banner while items of the warehouse are below their reorder level.
@MainActor
final class LowStockMonitor: ObservableObject {
    @Published private(set) var lowStockCount = 0
    private let store: DittoStore
    private var observer: DittoStoreObserver?

    init(store: DittoStore) {
        self.store = store
    }

    /// Called from the dashboard's onAppear.
    func start(warehouseID: String) {
        do {
            observer = try store.registerObserver(
                query: """
                SELECT COUNT(*) AS n FROM items
                WHERE warehouseId = :warehouseId AND countedQuantity < reorderLevel
                """,
                arguments: ["warehouseId": warehouseID]
            ) { [weak self] result in
                let count = result.items.first?.value["n"] as? Int ?? 0
                MainActor.assumeIsolated { self?.lowStockCount = count }
            }
        } catch {
            print("Could not watch low stock: \(error)")
        }
    }
}
