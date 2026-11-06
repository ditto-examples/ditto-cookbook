// Ditto SDK 5.2 (Swift, DittoSwift 5.2.0, SwiftUI): Lazy attachment loading
//
// Guide: § Fetching Attachments, § Attachments in Swift
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Subscriptions sync tokens only; blobs are fetched explicitly
// 2. ✅ Fetch lazily: only rows that a List shows fetch, when they appear
// 3. ✅ One DittoAttachmentFetcher per row model, stopped when the row goes away
// 4. ✅ Progress, completion, deletion, and @unknown default in the switch
// 5. ✅ Stall timeout with a retry button (Ditto has no fetch timeout)
// 6. ✅ Token metadata (name, size) shown before the download starts

import DittoSwift
import Foundation
import SwiftUI

/// Returns the attachment token stored in field, or nil if absent. A token is a
/// dictionary with id, len, and metadata; it is not the file.
func attachmentToken(_ document: [String: Any?], field: String) -> [String: Any?]? {
    document[field] as? [String: Any?]
}

/// ✅ GOOD: Fetches one attachment when started, reports progress, restarts a
/// stall timer on every progress event, and stops the fetcher in stop().
@MainActor
final class AttachmentImageModel: ObservableObject {
    @Published private(set) var data: Data?
    @Published private(set) var progress: Double?
    @Published private(set) var failed = false
    private let ditto: Ditto
    private let stallTimeout: TimeInterval
    private var fetcher: DittoAttachmentFetcher?
    private var stallTimer: Task<Void, Never>?
    private var generation = 0

    init(ditto: Ditto, stallTimeout: TimeInterval = 30) {
        self.ditto = ditto
        self.stallTimeout = stallTimeout
    }

    func load(_ token: [String: Any?]) {
        stop()
        data = nil
        failed = false
        progress = nil
        generation += 1
        let current = generation
        restartStallTimer()
        do {
            fetcher = try ditto.store.fetchAttachment(token: token.compactMapValues { $0 }) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event, generation: current) }
            }
        } catch {
            failed = true
        }
    }

    private func handle(_ event: DittoAttachmentFetchEvent, generation: Int) {
        guard generation == self.generation else { return } // an event of a replaced fetch
        switch event {
        case .progress(let downloaded, let total):
            restartStallTimer()
            if total > 0 { progress = Double(downloaded) / Double(total) }
        case .completed(let attachment):
            stallTimer?.cancel()
            data = try? attachment.data()
            failed = data == nil
        case .deleted:
            stallTimer?.cancel()
            failed = true
        @unknown default:
            break
        }
    }

    private func restartStallTimer() {
        stallTimer?.cancel()
        let timeout = stallTimeout
        stallTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.fetcher?.stop()
            self?.failed = true
        }
    }

    func stop() {
        stallTimer?.cancel()
        fetcher?.stop()
        fetcher = nil
    }
}

struct AttachmentImage: View {
    let token: [String: Any?]
    @StateObject private var model: AttachmentImageModel

    init(ditto: Ditto, token: [String: Any?], stallTimeout: TimeInterval = 30) {
        self.token = token
        _model = StateObject(wrappedValue: AttachmentImageModel(ditto: ditto, stallTimeout: stallTimeout))
    }

    var body: some View {
        content
            .onAppear { model.load(token) }
            .onChange(of: token["id"] as? String) { _ in model.load(token) }
            .onDisappear { model.stop() }
    }

    @ViewBuilder private var content: some View {
        if let data = model.data, let image = platformImage(data) {
            image.resizable().scaledToFill()
        } else if model.failed {
            Button("Retry") { model.load(token) }
        } else {
            VStack {
                ProgressView(value: model.progress)
                // Metadata is known before the download starts.
                Text("\((token["metadata"] as? [String: Any?])?["name"] as? String ?? "") \(token["len"] as? Int ?? 0) bytes")
                    .font(.caption)
            }
        }
    }

    private func platformImage(_ data: Data) -> Image? {
        #if canImport(UIKit)
        UIImage(data: data).map(Image.init(uiImage:))
        #else
        NSImage(data: data).map(Image.init(nsImage:))
        #endif
    }
}

/// ✅ GOOD: The observer delivers documents (with tokens). Each row that the
/// List shows starts its own fetch when it appears and stops it when it
/// disappears.
@MainActor
final class PhotoGalleryModel: ObservableObject {
    @Published private(set) var photos: [[String: Any?]] = []
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto) {
        observer = try? ditto.store.registerObserver(
            query: "SELECT * FROM COLLECTION photos (image ATTACHMENT) ORDER BY createdAt DESC, _id LIMIT 100"
        ) { [weak self] result in
            let photos = result.items.map { $0.value }
            MainActor.assumeIsolated { self?.photos = photos }
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }
}

struct PhotoGallery: View {
    let ditto: Ditto
    @StateObject private var model = PhotoGalleryModel()

    var body: some View {
        List(model.photos.indices, id: \.self) { index in
            if let token = attachmentToken(model.photos[index], field: "image") {
                AttachmentImage(ditto: ditto, token: token).frame(height: 120)
            }
        }
        .onAppear { model.start(ditto) }
        .onDisappear { model.stop() }
    }
}
