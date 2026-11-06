// Store observer performance in Ditto SDK 5.2.0 (Swift, DittoSwift 5.2.0, SwiftUI).
//
// Patterns: 1. the recommended pattern (a model owns the observer and cancels
// it); 2. a .task with an AsyncStream; 3. a fast handler with the heavy work on
// a background queue; 4. throttling a very busy collection with
// handlerWithSignalNext; 5. a dropped observer (bad); 6. a Task per update
// (bad); 7. an observer without ORDER BY, and one registered in body (bad).
//
// Guide: § Store Observers in Swift, § Observer lifecycle in Swift, § Stable ordering, § Keep observer callbacks fast, § Backpressure in Swift

import DittoSwift
import Foundation
import SwiftUI

// PATTERN 1: The recommended pattern

/// ✅ GOOD: The model registers once, copies values out on the main queue, and
/// cancels in stop() and deinit.
@MainActor
final class OpenOrdersModel: ObservableObject {
    @Published private(set) var orders: [[String: Any?]] = []
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto) {
        guard observer == nil else { return }
        observer = try? ditto.store.registerObserver(
            query: "SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id",
            arguments: ["status": "open"]
        ) { [weak self] result in
            let orders = result.items.map { $0.value }
            MainActor.assumeIsolated { self?.orders = orders }
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }

    deinit { observer?.cancel() }
}

struct OpenOrdersView: View {
    let ditto: Ditto
    @StateObject private var model = OpenOrdersModel()

    var body: some View {
        List(model.orders.indices, id: \.self) { index in
            Text(model.orders[index]["_id"] as? String ?? "")
        }
        .onAppear { model.start(ditto) }
        .onDisappear { model.stop() }
    }
}

// PATTERN 2: .task with an AsyncStream

/// ✅ GOOD: The observer lives exactly as long as the view's task.
struct OpenOrdersTaskView: View {
    let ditto: Ditto
    @State private var count = 0

    var body: some View {
        Text("\(count) open orders")
            .task {
                let counts = AsyncStream<Int>(bufferingPolicy: .bufferingNewest(1)) { continuation in
                    do {
                        let observer = try ditto.store.registerObserver(
                            query: "SELECT COUNT(*) AS n FROM orders WHERE status = 'open'",
                            deliverOn: DispatchQueue(label: "orders.count")
                        ) { result in
                            continuation.yield(result.items.first?.value["n"] as? Int ?? 0)
                        }
                        continuation.onTermination = { _ in observer.cancel() }
                    } catch {
                        continuation.finish()
                    }
                }
                for await n in counts where n != count { count = n }
            }
    }
}

// PATTERN 3: A fast handler, heavy work off the main thread

struct SalesSummary: Equatable {
    var revenueCents = 0
    var orderCount = 0
}

/// ✅ GOOD: The observer delivers on a background queue; the summary is
/// computed there, and only the result is published on the main actor.
@MainActor
final class SalesSummaryModel: ObservableObject {
    @Published private(set) var summary = SalesSummary()
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto) {
        observer = try? ditto.store.registerObserver(
            query: "SELECT total FROM orders WHERE status = 'closed'",
            deliverOn: DispatchQueue(label: "sales.summary")
        ) { [weak self] result in
            var summary = SalesSummary()
            for item in result.items {
                // Read numbers as NSNumber: a float that fits in 32 bits, such as 12.5,
                // comes back as Float, so `as? Double` would be nil.
                let total = (item.value["total"] as? NSNumber)?.doubleValue ?? 0
                summary.revenueCents += Int((total * 100).rounded())
                summary.orderCount += 1
            }
            let computed = summary
            Task { @MainActor in
                if self?.summary != computed { self?.summary = computed }
            }
        }
    }

    func stop() { observer?.cancel() }
}

// PATTERN 4: Throttling a very busy collection

/// ✅ GOOD: handlerWithSignalNext with a pause before signalNext() limits the
/// UI to about four updates a second; Ditto merges what changed meanwhile.
@MainActor
final class ThrottledReadingsModel: ObservableObject {
    @Published private(set) var latest: [[String: Any?]] = []
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto, interval: TimeInterval = 0.25) {
        observer = try? ditto.store.registerObserver(
            query: "SELECT * FROM sensorReadings ORDER BY recordedAt DESC LIMIT 50",
            deliverOn: DispatchQueue(label: "readings.throttled")
        ) { [weak self] result, signalNext in
            let rows = result.items.map { $0.value }
            Task { @MainActor in
                self?.latest = rows
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                signalNext()
            }
        }
    }

    func stop() { observer?.cancel() }
}

// ANTI-PATTERNS

/// ❌ BAD: The returned observer is thrown away; it keeps running and can no
/// longer be cancelled except through ditto.store.observers.
func countOrdersForever(_ ditto: Ditto, onCount: @escaping @Sendable (Int) -> Void) throws {
    _ = try ditto.store.registerObserver(query: "SELECT * FROM orders ORDER BY createdAt DESC") { result in
        onCount(result.items.count)
    }
}

/// ❌ BAD: Slow async work per update without backpressure.
func uploadEveryChange(_ ditto: Ditto, upload: @escaping @Sendable ([[String: Any?]]) async -> Void) throws -> DittoStoreObserver {
    try ditto.store.registerObserver(query: "SELECT * FROM orders ORDER BY createdAt") { result in
        let orders = result.items.map { $0.value }
        Task { await upload(orders) }
    }
}

/// ❌ BAD: No ORDER BY; rows may change position between updates.
func observeTasksUnordered(_ ditto: Ditto) throws -> DittoStoreObserver {
    try ditto.store.registerObserver(query: "SELECT * FROM tasks WHERE done = false") { _ in }
}

/// ✅ GOOD: Deterministic order; _id breaks ties between equal timestamps.
func observeTasksOrdered(_ ditto: Ditto) throws -> DittoStoreObserver {
    try ditto.store.registerObserver(query: "SELECT * FROM tasks WHERE done = false ORDER BY createdAt DESC, _id") { _ in }
}

/// ❌ BAD: The observer is created in body. Every evaluation registers another
/// observer that is never cancelled.
struct LeakyOrdersBadge: View {
    let ditto: Ditto

    var body: some View {
        _ = try? ditto.store.registerObserver(query: "SELECT COUNT(*) AS n FROM orders") { _ in }
        return Image(systemName: "bag")
    }
}
