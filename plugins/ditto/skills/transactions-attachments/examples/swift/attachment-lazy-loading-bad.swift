// Ditto SDK 5.2 (Swift, DittoSwift 5.2.0, SwiftUI): Attachment loading anti-patterns
//
// Guide: § Fetching Attachments, § Attachments in Swift
//
// Every function below compiles. The problems appear at runtime.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ Treating the token as the file (subscriptions never download blobs)
// 2. ❌ Fetching every attachment as soon as documents sync (eager loading)
// 3. ❌ Starting a new fetch every time SwiftUI evaluates body
// 4. ❌ Never stopping fetchers when the UI goes away
// 5. ❌ Waiting for completion after stop() (no event ever arrives)
// 6. ❌ Bytes in a regular field and hand-made tokens
//
// See attachment-lazy-loading-good.swift for the correct patterns.

import DittoSwift
import Foundation
import SwiftUI

/// ❌ BAD: A subscription delivers the document with its token (id, len,
/// metadata), not the bytes. Casting the field to Data finds nothing.
func tokenIsNotData(_ ditto: Ditto, photoID: String) async throws -> Data? {
    let result = try await ditto.store.execute(
        query: "SELECT * FROM COLLECTION photos (image ATTACHMENT) WHERE _id = :id", arguments: ["id": photoID]
    )
    return result.items.first?.value["image"] as? Data // always nil
}

/// ❌ BAD: Every observer update starts a fetch for every photo, including
/// photos that are never shown. Each fetch downloads the full blob from peers.
final class EagerPhotoCache: @unchecked Sendable {
    private var observer: DittoStoreObserver?
    var images: [String: Data] = [:]

    func start(_ ditto: Ditto) throws {
        observer = try ditto.store.registerObserver(query: "SELECT * FROM COLLECTION photos (image ATTACHMENT)") { result in
            for item in result.items {
                guard let token = item.value["image"] as? [String: Any?] else { continue }
                _ = try? ditto.store.fetchAttachment(token: token.compactMapValues { $0 }) { _ in } // never stopped
            }
        }
    }
}

/// ❌ BAD: body runs many times; each evaluation starts another fetch, and none
/// of them is ever stopped.
struct FetchInBody: View {
    let ditto: Ditto
    let token: [String: Any?]

    var body: some View {
        _ = try? ditto.store.fetchAttachment(token: token.compactMapValues { $0 }) { _ in }
        return Image(systemName: "photo")
    }
}
// ✅ Fix: start the fetch when the view appears, keep the DittoAttachmentFetcher
// in a model, and stop() it when the view disappears.

/// ❌ BAD: A naive timeout. After stop(), no event arrives anymore, so this
/// continuation never resumes and the caller waits forever.
func naiveTimeout(_ ditto: Ditto, token: [String: Any?]) async throws -> Data? {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
        do {
            let fetcher = try ditto.store.fetchAttachment(token: token.compactMapValues { $0 }) { event in
                if case .completed(let attachment) = event { continuation.resume(returning: try? attachment.data()) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { fetcher.stop() } // and then?
        } catch {
            continuation.resume(throwing: error)
        }
    }
}
// ✅ Fix: a stall timer that restarts on every progress event and resumes the
// caller itself when it fires (see attachment-fetch-timeout.swift).

/// ❌ BAD: Two mistakes. The bytes go into a regular field, where they count
/// toward the document size and are sent with every change of the document;
/// and a hand-made dictionary is not an attachment token.
func inlineAndFakeToken(_ ditto: Ditto, photoID: String, bytes: Data) async throws {
    try await ditto.store.execute(
        query: "INSERT INTO photos DOCUMENTS (:photo)",
        arguments: ["photo": [
            "_id": photoID,
            "imageBase64": bytes.base64EncodedString(),
            "image": ["id": UUID().uuidString, "len": bytes.count],
        ]]
    )
}
// ✅ Fix: try await ditto.store.newAttachment(data: bytes, metadata: [...]) and
// insert it into a field declared as ATTACHMENT.
