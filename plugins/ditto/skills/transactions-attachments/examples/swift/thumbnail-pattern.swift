// Ditto SDK 5.2 (Swift, DittoSwift 5.2.0, SwiftUI): Thumbnail pattern
//
// Guide: § Thumbnail Pattern, § Attachments in Swift
//
// Lists of photos should not download full-size images. Store a small preview
// next to the full-size attachment and fetch the full-size file only when the
// user opens it.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Insert a thumbnail attachment and a full-size attachment together
// 2. ✅ List rows fetch only thumbnails (lazily, one fetcher per row)
// 3. ✅ The full-size image is fetched when the user opens the photo, with a
//       longer stall timeout
//
// Why: every device that subscribes to photos receives both tokens, but
// downloads only the thumbnails that are shown. Full-size blobs cross the
// network only for the photos users open, which matters most on slow
// peer-to-peer transports such as Bluetooth LE.

import DittoSwift
import Foundation
import SwiftUI

private func utcTimestamp(_ date: Date = Date()) -> String {
    Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
}

/// ✅ GOOD: The app downscales the image beforehand (for example with
/// UIGraphicsImageRenderer or CGImageSource thumbnails).
func savePhotoWithThumbnail(_ ditto: Ditto, photoID: String, thumbnailBytes: Data, fullSizeURL: URL) async throws {
    let thumbnail = try await ditto.store.newAttachment(data: thumbnailBytes, metadata: ["kind": "thumbnail", "mimeType": "image/jpeg"])
    let fullSize = try await ditto.store.newAttachment(path: fullSizeURL.path, metadata: ["kind": "full", "mimeType": "image/jpeg"])
    try await ditto.store.execute(
        query: "INSERT INTO COLLECTION photos (thumbnail ATTACHMENT, image ATTACHMENT) DOCUMENTS (:photo)",
        arguments: ["photo": [
            "_id": photoID,
            "thumbnail": thumbnail,
            "image": fullSize,
            "createdAt": utcTimestamp(),
        ]]
    )
}

/// One lazily fetched image: the fetch starts when the view appears and stops
/// when it disappears; no progress within stallTimeout shows a retry button.
@MainActor
final class LazyAttachmentModel: ObservableObject {
    @Published private(set) var data: Data?
    @Published private(set) var stalled = false
    private var fetcher: DittoAttachmentFetcher?
    private var timer: Task<Void, Never>?

    func load(_ ditto: Ditto, token: [String: Any?], stallTimeout: TimeInterval) {
        stop()
        stalled = false
        restart(stallTimeout)
        fetcher = try? ditto.store.fetchAttachment(token: token.compactMapValues { $0 }) { [weak self] event in
            MainActor.assumeIsolated {
                switch event {
                case .progress: self?.restart(stallTimeout)
                case .completed(let attachment): self?.timer?.cancel(); self?.data = try? attachment.data()
                case .deleted: self?.timer?.cancel(); self?.stalled = true
                @unknown default: break
                }
            }
        }
    }

    private func restart(_ timeout: TimeInterval) {
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.fetcher?.stop()
            self?.stalled = true
        }
    }

    func stop() {
        timer?.cancel()
        fetcher?.stop()
        fetcher = nil
    }
}

struct LazyAttachmentImage: View {
    let ditto: Ditto
    let token: [String: Any?]
    let stallTimeout: TimeInterval
    @StateObject private var model = LazyAttachmentModel()

    var body: some View {
        Group {
            if let data = model.data, let image = Self.image(data) {
                image.resizable().scaledToFill()
            } else if model.stalled {
                Button("Retry") { model.load(ditto, token: token, stallTimeout: stallTimeout) }
            } else {
                ProgressView()
            }
        }
        .onAppear { model.load(ditto, token: token, stallTimeout: stallTimeout) }
        .onDisappear { model.stop() }
    }

    private static func image(_ data: Data) -> Image? {
        #if canImport(UIKit)
        UIImage(data: data).map(Image.init(uiImage:))
        #else
        NSImage(data: data).map(Image.init(nsImage:))
        #endif
    }
}

/// ✅ GOOD: Rows fetch only thumbnails; the full-size image is fetched when the
/// user opens the photo, with a longer stall timeout for the larger file.
struct PhotoRow: View {
    let ditto: Ditto
    let photo: [String: Any?]
    @State private var showsFullSize = false

    var body: some View {
        HStack {
            Group {
                if let thumbnail = photo["thumbnail"] as? [String: Any?] {
                    LazyAttachmentImage(ditto: ditto, token: thumbnail, stallTimeout: 30)
                } else {
                    Image(systemName: "photo")
                }
            }
            .frame(width: 56, height: 56)
            .clipped()
            Text(photo["_id"] as? String ?? "")
        }
        .onTapGesture { showsFullSize = true }
        .sheet(isPresented: $showsFullSize) {
            if let fullSize = photo["image"] as? [String: Any?] {
                LazyAttachmentImage(ditto: ditto, token: fullSize, stallTimeout: 120)
            }
        }
    }
}
