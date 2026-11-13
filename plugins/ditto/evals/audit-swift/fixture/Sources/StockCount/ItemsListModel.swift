import DittoSwift
import Foundation
import SwiftUI

/// The items of one location, updated live as counts sync.
@MainActor
final class ItemsListModel: ObservableObject {
    @Published private(set) var items: [Item] = []
    private let store: DittoStore
    private var observer: DittoStoreObserver?

    init(store: DittoStore) {
        self.store = store
    }

    func start(location: String) {
        guard observer == nil else { return }
        do {
            observer = try store.registerObserver(
                query: "SELECT * FROM items WHERE location = :location ORDER BY sku, _id",
                arguments: ["location": location]
            ) { [weak self] result in
                let decoder = JSONDecoder()
                let items = result.items.compactMap { try? decoder.decode(Item.self, from: $0.jsonData()) }
                MainActor.assumeIsolated { self?.items = items }
            }
        } catch {
            print("Could not watch items: \(error)")
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }

    deinit {
        observer?.cancel()
    }
}

struct ItemsListView: View {
    @StateObject private var model: ItemsListModel
    let location: String

    init(store: DittoStore, location: String) {
        _model = StateObject(wrappedValue: ItemsListModel(store: store))
        self.location = location
    }

    var body: some View {
        List(model.items) { item in
            Text(item.name ?? item.sku)
        }
        .onAppear { model.start(location: location) }
        .onDisappear { model.stop() }
    }
}
