// Ditto SDK 5.2 (Swift, DittoSwift 5.2.0): Attachment fetch timeouts
//
// Guide: § Fetching Attachments, § Availability, § Attachments in Swift
//
// Ditto has no fetch timeout and no "not available" event. While no reachable
// peer can deliver the blob, the fetch simply makes no progress, and after
// fetcher.stop() no further event arrives.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Stall timeout: restart a timer on every progress event
// 2. ✅ Stop the fetcher when the timer fires and report a retryable outcome
// 3. ✅ Resume the caller yourself after stop() (no event will)
// 4. ✅ Longer stall timeouts for larger files
// 5. ✅ Retry on user request instead of failing permanently

import DittoSwift
import Foundation

enum AttachmentFetchOutcome {
    case completed(Data)
    case stalled // no progress within the stall timeout; retry later
    case deleted
}

/// ✅ GOOD: Wraps one fetch. The result always arrives: completed, deleted, or
/// stalled when no progress came within stallTimeout. Only the fetcher's serial
/// queue touches the state of this object.
final class GuardedAttachmentFetch: @unchecked Sendable {
    private let queue = DispatchQueue(label: "attachment.fetch")
    private var fetcher: DittoAttachmentFetcher?
    private var stallTimer: DispatchWorkItem?
    private var continuation: CheckedContinuation<AttachmentFetchOutcome, Error>?

    func run(_ ditto: Ditto, token: [String: Any?], stallTimeout: TimeInterval) async throws -> AttachmentFetchOutcome {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                self.restartStallTimer(stallTimeout)
                do {
                    self.fetcher = try ditto.store.fetchAttachment(
                        token: token.compactMapValues { $0 }, deliverOn: self.queue
                    ) { [weak self] event in
                        self?.handle(event, stallTimeout: stallTimeout)
                    }
                } catch {
                    self.finish(.failure(error))
                }
            }
        }
    }

    private func handle(_ event: DittoAttachmentFetchEvent, stallTimeout: TimeInterval) {
        switch event {
        case .progress:
            restartStallTimer(stallTimeout) // progress resets the stall timer
        case .completed(let attachment):
            finish(Result { .completed(try attachment.data()) })
        case .deleted:
            finish(.success(.deleted))
        @unknown default:
            break
        }
    }

    private func restartStallTimer(_ timeout: TimeInterval) {
        stallTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            self?.fetcher?.stop()
            self?.finish(.success(.stalled)) // resume the caller ourselves: no event follows stop()
        }
        stallTimer = timer
        queue.asyncAfter(deadline: .now() + timeout, execute: timer)
    }

    private func finish(_ result: Result<AttachmentFetchOutcome, Error>) {
        stallTimer?.cancel()
        fetcher = nil
        continuation?.resume(with: result)
        continuation = nil // resume once
    }
}

/// ✅ GOOD: The token's len is known before the download starts, so larger
/// files get a longer stall timeout (at least 30 s, plus 10 s per MiB).
func stallTimeout(forTokenLength length: Int) -> TimeInterval {
    30 + Double(length) / (1024 * 1024) * 10
}

/// ✅ GOOD: A stalled fetch is not an error. Keep the token, show the retry
/// option, and fetch again when the user asks.
func loadWithRetry(_ ditto: Ditto, token: [String: Any?], userWantsRetry: () async -> Bool) async throws -> Data? {
    while true {
        let timeout = stallTimeout(forTokenLength: token["len"] as? Int ?? 0)
        switch try await GuardedAttachmentFetch().run(ditto, token: token, stallTimeout: timeout) {
        case .completed(let data): return data
        case .deleted: return nil
        case .stalled: if await !userWantsRetry() { return nil }
        }
    }
}
