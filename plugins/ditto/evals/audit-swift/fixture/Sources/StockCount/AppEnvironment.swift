import DittoSwift
import Foundation

/// The objects that the screens of the app use, created once at launch.
@MainActor
final class AppEnvironment {
    let items: ItemRepository
    let sync: InventorySync
    let store: DittoStore

    private init(items: ItemRepository, sync: InventorySync, store: DittoStore) {
        self.items = items
        self.sync = sync
        self.store = store
    }

    static func make(config: DittoConfig) async throws -> AppEnvironment {
        let ditto = try await Ditto.open(config: config)
        // The screens only need the store and sync, so keep those.
        return AppEnvironment(
            items: ItemRepository(store: ditto.store),
            sync: InventorySync(sync: ditto.sync),
            store: ditto.store
        )
    }
}
