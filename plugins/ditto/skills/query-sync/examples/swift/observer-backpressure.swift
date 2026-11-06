// Observer backpressure in Ditto SDK 5.2.0 (Swift, DittoSwift 5.2.0).
//
// registerObserver(..., handler:) waits for the handler to return before it
// delivers the next result, and then delivers the latest state; intermediate
// states are merged. A handler that blocks its queue therefore slows updates
// down, and on the main queue it freezes the UI. A handler that starts a Task
// and returns at once has no backpressure: every result starts a task, and the
// tasks overlap (Note (SDK 5.1.0 and 5.2.0)).
//
// | Situation                                       | API                                              |
// |-------------------------------------------------|--------------------------------------------------|
// | Updating UI state                               | handler: on .main, short and synchronous          |
// | Slow or asynchronous work per update            | handlerWithSignalNext: on a background queue      |
// | Slow work that fits a loop                      | an AsyncStream with .bufferingNewest(1)           |
//
// Guide: § Backpressure in Swift, § Backpressure (SDK 5.1+)

import DittoSwift
import Foundation

private func showError(_ error: Error) {
    // Report the error to your logging or crash-reporting pipeline.
}

/// ✅ GOOD: handlerWithSignalNext. One result is delivered, then Ditto waits
/// until signalNext() is called; signalNext() is called in defer, so an error
/// cannot stop updates.
final class OpenOrdersUploader: @unchecked Sendable {
    private let ditto: Ditto
    private let upload: @Sendable ([[String: Any?]]) async throws -> Void
    private var observer: DittoStoreObserver?

    init(ditto: Ditto, upload: @escaping @Sendable ([[String: Any?]]) async throws -> Void) {
        self.ditto = ditto
        self.upload = upload
    }

    func start() throws {
        stop() // Cancel a previous start, if any.
        let upload = self.upload
        observer = try ditto.store.registerObserver(
            query: "SELECT * FROM orders WHERE status = :status ORDER BY createdAt, _id",
            arguments: ["status": "open"],
            deliverOn: DispatchQueue(label: "orders.upload")
        ) { result, signalNext in
            let orders = result.items.map { $0.value } // copy before the slow work
            Task {
                defer { signalNext() } // Always signal, even after an error.
                do {
                    try await upload(orders)
                } catch {
                    showError(error)
                }
            }
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }
}

/// ✅ GOOD: A for-await loop over an AsyncStream that buffers only the newest
/// result: slow work in the loop body sees one update at a time and then the
/// latest state. Cancelling the task ends the loop and cancels the observer.
func aggregateReadings(
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
        try await persistAggregates(rows)
    }
}

/// ✅ GOOD: Only the latest state matters: a slow writer that signals when it
/// is done gets the merged latest state next.
final class LatestStateExporter: @unchecked Sendable {
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto, writeFile: @escaping @Sendable (Data) async throws -> Void) throws {
        observer = try ditto.store.registerObserver(
            query: "SELECT _id, status, total FROM orders WHERE status = :status ORDER BY _id",
            arguments: ["status": "open"],
            deliverOn: DispatchQueue(label: "orders.export")
        ) { result, signalNext in
            let json = Data("[".utf8) + result.items.map { $0.jsonData() }.joined(separator: Data(",".utf8)) + Data("]".utf8)
            Task {
                defer { signalNext() }
                try? await writeFile(json)
            }
        }
    }

    func stop() { observer?.cancel() }
}

/// ❌ BAD: signalNext() is skipped when the work throws, so the observer
/// silently stops delivering updates. Call it in defer.
func fragileObserver(_ ditto: Ditto, upload: @escaping @Sendable ([[String: Any?]]) async throws -> Void) throws -> DittoStoreObserver {
    try ditto.store.registerObserver(query: "SELECT * FROM orders ORDER BY createdAt, _id") { result, signalNext in
        let orders = result.items.map { $0.value }
        Task {
            try await upload(orders)
            signalNext() // Never reached if upload throws.
        }
    }
}

/// ❌ BAD: Never calling signalNext(). After the first result, no further
/// updates arrive.
func neverSignals(_ ditto: Ditto) throws -> DittoStoreObserver {
    try ditto.store.registerObserver(query: "SELECT * FROM orders ORDER BY _id") { result, _ in
        print("received \(result.items.count) orders")
    }
}

/// ❌ BAD: A Task per update: no backpressure, overlapping work, and an older
/// result can finish last.
func uploadWithoutBackpressure(_ ditto: Ditto, upload: @escaping @Sendable ([[String: Any?]]) async -> Void) throws -> DittoStoreObserver {
    try ditto.store.registerObserver(query: "SELECT * FROM orders ORDER BY createdAt") { result in
        let orders = result.items.map { $0.value }
        Task { await upload(orders) }
    }
}
