// Observer backpressure for slow or asynchronous work in Ditto SDK 5.2.0 (Swift, DittoSwift 5.2.0).
//
// registerObserver(..., handler:) waits for the handler to return before the
// next result and then delivers the latest state; a handler that starts a Task
// and returns has no backpressure (Note (SDK 5.1.0 and 5.2.0)).
// registerObserver(..., handlerWithSignalNext:) delivers one result and waits
// until signalNext() is called; if it is never called, updates stop.
//
// Patterns: 1. a for-await loop over an AsyncStream that keeps only the newest
// result; 2. handlerWithSignalNext with signalNext() in defer; 3. signalling
// after work that finishes on the main actor; 4. signalNext() skipped after an
// error (bad); 5. a blocking handler on the main queue (bad); 6. a Task per
// update (bad).
//
// Guide: § Backpressure in Swift, § Backpressure (SDK 5.1+), § Choosing an observer API, § Keep observer callbacks fast

import DittoSwift
import Foundation
import SwiftUI

private func showError(_ error: Error) {
    // Report the error to your logging or crash-reporting pipeline.
}

// PATTERN 1: A for-await loop

/// ✅ GOOD: One update at a time. The stream buffers only the newest result
/// while the loop body runs; cancelling the task cancels the observer.
func aggregateSensorReadings(
    _ ditto: Ditto,
    deviceID: String,
    persistAggregates: ([[String: Any?]]) async throws -> Void
) async throws {
    let readings = AsyncStream<[[String: Any?]]>(bufferingPolicy: .bufferingNewest(1)) { continuation in
        do {
            let observer = try ditto.store.registerObserver(
                query: "SELECT * FROM sensorReadings WHERE deviceId = :deviceId ORDER BY recordedAt DESC LIMIT 100",
                arguments: ["deviceId": deviceID],
                deliverOn: DispatchQueue(label: "readings")
            ) { result in
                continuation.yield(result.items.map { $0.value })
            }
            continuation.onTermination = { _ in observer.cancel() }
        } catch {
            showError(error)
            continuation.finish()
        }
    }
    for await rows in readings {
        try await persistAggregates(rows) // the next iteration gets the latest state
    }
}

// PATTERN 2: handlerWithSignalNext

/// ✅ GOOD: Request the next result when the work is done, also after an error.
final class OrderUploader: @unchecked Sendable {
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto, upload: @escaping @Sendable ([[String: Any?]]) async throws -> Void) throws {
        stop()
        observer = try ditto.store.registerObserver(
            query: "SELECT * FROM orders WHERE status = :status ORDER BY createdAt, _id",
            arguments: ["status": "open"],
            deliverOn: DispatchQueue(label: "orders.upload")
        ) { result, signalNext in
            let orders = result.items.map { $0.value }
            Task {
                defer { signalNext() }
                do { try await upload(orders) } catch { showError(error) }
            }
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }
}

// PATTERN 3: Signal after work that finishes on the main actor

/// ✅ GOOD: The handler runs on a background queue, decodes there, applies the
/// rows on the main actor, and signals only then, so the UI is never handed
/// more than one pending update.
@MainActor
final class MainActorPacedOrders: ObservableObject {
    @Published private(set) var rows: [[String: Any?]] = []
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto) {
        observer = try? ditto.store.registerObserver(
            query: "SELECT * FROM orders ORDER BY createdAt DESC, _id LIMIT 200",
            deliverOn: DispatchQueue(label: "orders.paced")
        ) { [weak self] result, signalNext in
            let rows = result.items.map { $0.value } // decoded off the main thread
            Task { @MainActor in
                self?.rows = rows
                signalNext() // after the main actor has applied the update
            }
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }
}

// ANTI-PATTERNS

/// ❌ BAD: signalNext is skipped when the work throws; the observer silently
/// stops updating.
func fragileUploader(_ ditto: Ditto, upload: @escaping @Sendable ([[String: Any?]]) async throws -> Void) throws -> DittoStoreObserver {
    try ditto.store.registerObserver(query: "SELECT * FROM orders ORDER BY createdAt, _id") { result, signalNext in
        let orders = result.items.map { $0.value }
        Task {
            try await upload(orders)
            signalNext() // Never reached if upload throws.
        }
    }
}

/// ❌ BAD: Slow work in a handler on the main queue. The next result waits for
/// it, and so does the UI.
func slowHandlerOnMain(_ ditto: Ditto) throws -> DittoStoreObserver {
    try ditto.store.registerObserver(query: "SELECT * FROM orders ORDER BY _id") { result in
        Thread.sleep(forTimeInterval: 0.5) // stands in for slow decoding or I/O
        print(result.items.count)
    }
}

/// ❌ BAD: A Task per update: the uploads overlap, and an older result can
/// finish last.
func overlappingUploads(_ ditto: Ditto, upload: @escaping @Sendable ([[String: Any?]]) async -> Void) throws -> DittoStoreObserver {
    try ditto.store.registerObserver(query: "SELECT * FROM orders ORDER BY createdAt") { result in
        let orders = result.items.map { $0.value }
        Task { await upload(orders) }
    }
}
