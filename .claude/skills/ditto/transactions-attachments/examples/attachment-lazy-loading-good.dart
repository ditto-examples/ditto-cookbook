// ============================================================================
// Attachment Lazy-Loading Pattern (Recommended)
// ============================================================================
//
// This example demonstrates the correct lazy-loading pattern for attachments,
// which are NOT automatically synced with document subscriptions.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Document query with metadata
// 2. ✅ Explicit fetchAttachment() calls
// 3. ✅ Error handling for fetch failures
// 4. ✅ Metadata-based UI display
// 5. ✅ Progressive loading (thumbnail first)
// 6. ✅ Attachment cancellation
// 7. ✅ Storage management
//
// CRITICAL: Attachments are NOT auto-synced!
// - Subscription syncs documents only
// - Must explicitly call fetchAttachment()
// - Each attachment fetched individually
//
// ============================================================================

import 'package:ditto/ditto.dart';
import 'dart:typed_data';

// ============================================================================
// PATTERN 1: Document Query with Metadata
// ============================================================================

/// ✅ GOOD: Store attachment metadata in document
class PhotoDocument {
  final String id;
  final DittoAttachmentToken imageToken;
  final Map<String, dynamic> metadata;

  PhotoDocument({
    required this.id,
    required this.imageToken,
    required this.metadata,
  });

  // Metadata helps display UI before attachment loads
  String get fileName => metadata['fileName'] as String;
  int get sizeBytes => metadata['sizeBytes'] as int;
  String get mimeType => metadata['mimeType'] as String;
  int get width => metadata['width'] as int;
  int get height => metadata['height'] as int;
}

/// Query photos and display metadata immediately
Future<List<PhotoDocument>> queryPhotosWithMetadata(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM photos ORDER BY createdAt DESC LIMIT 20',
  );

  final photos = result.items.map((item) {
    final doc = item.value;
    return PhotoDocument(
      id: doc['_id'] as String,
      imageToken: doc['imageToken'] as DittoAttachmentToken,
      metadata: doc['metadata'] as Map<String, dynamic>,
    );
  }).toList();

  print('✅ Queried ${photos.length} photos');
  print('   Documents synced, attachments NOT yet loaded');

  return photos;
}

// ============================================================================
// PATTERN 2: Explicit fetchAttachment() Calls
// ============================================================================

/// ✅ GOOD: Explicitly fetch attachment when needed
Future<Uint8List?> fetchPhotoImage(
  Ditto ditto,
  DittoAttachmentToken token,
  String photoId,
) async {
  print('📥 Fetching attachment for photo: $photoId');

  try {
    // ✅ Explicit fetch required
    final fetcher = ditto.store.fetchAttachment(token);

    // Wait for attachment to download
    final attachment = await fetcher.attachment;

    if (attachment != null) {
      final data = attachment.getData();
      print('  ✅ Attachment fetched: ${data.length} bytes');
      return data;
    } else {
      print('  ⚠️ Attachment not found');
      return null;
    }
  } catch (e) {
    print('  ❌ Failed to fetch attachment: $e');
    return null;
  }
}

// ============================================================================
// PATTERN 3: Error Handling for Fetch Failures
// ============================================================================

/// ✅ GOOD: Robust error handling
class AttachmentFetcher {
  final Ditto ditto;

  AttachmentFetcher(this.ditto);

  Future<AttachmentFetchResult> fetchWithErrorHandling(
    DittoAttachmentToken token,
    String documentId,
  ) async {
    try {
      final fetcher = ditto.store.fetchAttachment(token);

      // Set timeout
      final attachment = await fetcher.attachment.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          print('⏱️ Attachment fetch timeout for $documentId');
          return null;
        },
      );

      if (attachment == null) {
        return AttachmentFetchResult.notFound();
      }

      final data = attachment.getData();

      return AttachmentFetchResult.success(data);

    } on Exception catch (e) {
      print('❌ Attachment fetch error: $e');
      return AttachmentFetchResult.error(e.toString());
    }
  }
}

class AttachmentFetchResult {
  final Uint8List? data;
  final String? error;
  final bool isSuccess;

  AttachmentFetchResult._({this.data, this.error, required this.isSuccess});

  factory AttachmentFetchResult.success(Uint8List data) =>
      AttachmentFetchResult._(data: data, isSuccess: true);

  factory AttachmentFetchResult.notFound() =>
      AttachmentFetchResult._(isSuccess: false, error: 'Not found');

  factory AttachmentFetchResult.error(String message) =>
      AttachmentFetchResult._(isSuccess: false, error: message);
}

// ============================================================================
// PATTERN 4: Metadata-Based UI Display
// ============================================================================

/// ✅ GOOD: Display metadata while attachment loads
class PhotoGalleryItem {
  final PhotoDocument photo;
  Uint8List? imageData;
  bool isLoading = false;
  String? loadError;

  PhotoGalleryItem(this.photo);

  /// Display metadata immediately (before image loads)
  String get displayText {
    final sizeMB = (photo.sizeBytes / 1024 / 1024).toStringAsFixed(2);
    return '${photo.fileName} (${sizeMB} MB, ${photo.width}x${photo.height})';
  }

  /// Load image on demand
  Future<void> loadImage(Ditto ditto) async {
    if (isLoading || imageData != null) return;

    isLoading = true;
    print('📥 Loading image: ${photo.fileName}');

    final fetcher = AttachmentFetcher(ditto);
    final result = await fetcher.fetchWithErrorHandling(
      photo.imageToken,
      photo.id,
    );

    if (result.isSuccess) {
      imageData = result.data;
      print('  ✅ Image loaded: ${photo.fileName}');
    } else {
      loadError = result.error;
      print('  ❌ Image load failed: $loadError');
    }

    isLoading = false;
  }
}

// ============================================================================
// PATTERN 5: Progressive Loading (Thumbnail First)
// ============================================================================

/// ✅ GOOD: Load thumbnail first, full image on demand
class ProgressivePhotoLoader {
  final Ditto ditto;

  ProgressivePhotoLoader(this.ditto);

  Future<void> loadPhotoProgressive(String photoId) async {
    // Query document with both tokens
    final result = await ditto.store.execute(
      'SELECT * FROM photos WHERE _id = :photoId',
      arguments: {'photoId': photoId},
    );

    if (result.items.isEmpty) {
      print('Photo not found');
      return;
    }

    final doc = result.items.first.value;
    final thumbnailToken = doc['thumbnailToken'] as DittoAttachmentToken;
    final fullImageToken = doc['fullImageToken'] as DittoAttachmentToken;

    // Step 1: Load thumbnail first (small, fast)
    print('📥 Loading thumbnail...');
    final thumbnail = await _fetchAttachment(thumbnailToken);
    if (thumbnail != null) {
      print('  ✅ Thumbnail loaded: ${thumbnail.length} bytes');
      // Display thumbnail in UI
    }

    // Step 2: Load full image in background
    print('📥 Loading full image...');
    final fullImage = await _fetchAttachment(fullImageToken);
    if (fullImage != null) {
      print('  ✅ Full image loaded: ${fullImage.length} bytes');
      // Replace thumbnail with full image in UI
    }

    print('✅ Progressive loading complete');
  }

  Future<Uint8List?> _fetchAttachment(DittoAttachmentToken token) async {
    try {
      final fetcher = ditto.store.fetchAttachment(token);
      final attachment = await fetcher.attachment;
      return attachment?.getData();
    } catch (e) {
      print('  ❌ Fetch failed: $e');
      return null;
    }
  }
}

// ============================================================================
// PATTERN 6: Attachment Fetcher Cancellation
// ============================================================================

/// ✅ GOOD: Cancel attachment fetch when no longer needed
class CancellableAttachmentFetcher {
  final Ditto ditto;
  DittoAttachmentFetcher? _currentFetcher;

  CancellableAttachmentFetcher(this.ditto);

  Future<Uint8List?> fetchWithCancellation(
    DittoAttachmentToken token,
    String documentId,
  ) async {
    // Cancel any in-progress fetch
    _currentFetcher?.cancel();

    print('📥 Starting fetch: $documentId');

    _currentFetcher = ditto.store.fetchAttachment(token);

    try {
      final attachment = await _currentFetcher!.attachment;

      if (attachment == null) {
        print('  ⚠️ Attachment not found');
        return null;
      }

      final data = attachment.getData();
      print('  ✅ Fetch complete: ${data.length} bytes');

      return data;
    } catch (e) {
      print('  ❌ Fetch cancelled or failed: $e');
      return null;
    } finally {
      _currentFetcher = null;
    }
  }

  /// Cancel current fetch (e.g., user navigated away)
  void cancelCurrentFetch() {
    if (_currentFetcher != null) {
      print('🚫 Cancelling attachment fetch');
      _currentFetcher!.cancel();
      _currentFetcher = null;
    }
  }

  void dispose() {
    cancelCurrentFetch();
  }
}

// ============================================================================
// PATTERN 7: Batch Attachment Fetching
// ============================================================================

/// ✅ GOOD: Fetch multiple attachments efficiently
class BatchAttachmentFetcher {
  final Ditto ditto;

  BatchAttachmentFetcher(this.ditto);

  Future<Map<String, Uint8List>> fetchBatch(
    List<PhotoDocument> photos,
  ) async {
    print('📥 Fetching ${photos.length} attachments in batch');

    final results = <String, Uint8List>{};

    // Fetch attachments in parallel
    final futures = photos.map((photo) async {
      try {
        final fetcher = ditto.store.fetchAttachment(photo.imageToken);
        final attachment = await fetcher.attachment.timeout(
          const Duration(seconds: 10),
        );

        if (attachment != null) {
          final data = attachment.getData();
          results[photo.id] = data;
          print('  ✅ Fetched: ${photo.fileName}');
        }
      } catch (e) {
        print('  ❌ Failed to fetch ${photo.fileName}: $e');
      }
    });

    await Future.wait(futures);

    print('✅ Batch fetch complete: ${results.length}/${photos.length} succeeded');

    return results;
  }
}

// ============================================================================
// PATTERN 8: Storage Management for Attachments
// ============================================================================

/// ✅ GOOD: Clean up old attachments
class AttachmentStorageManager {
  final Ditto ditto;

  AttachmentStorageManager(this.ditto);

  /// Evict old documents with attachments
  Future<void> cleanupOldPhotos() async {
    print('🧹 Cleaning up old photos...');

    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 90))
        .toIso8601String();

    // Query old photos
    final result = await ditto.store.execute(
      'SELECT _id FROM photos WHERE createdAt < :cutoff',
      arguments: {'cutoff': cutoffDate},
    );

    print('  Found ${result.items.length} old photos to evict');

    // EVICT documents (attachments cleaned up automatically)
    await ditto.store.execute(
      'EVICT FROM photos WHERE createdAt < :cutoff',
      arguments: {'cutoff': cutoffDate},
    );

    print('✅ Old photos evicted (attachments cleaned up by garbage collector)');
  }
}

// ============================================================================
// Complete Example: Photo Gallery
// ============================================================================

/// Production-ready photo gallery implementation
class PhotoGallery {
  final Ditto ditto;
  final List<PhotoGalleryItem> _items = [];
  final _fetcher = CancellableAttachmentFetcher;

  PhotoGallery(this.ditto);

  /// Load photo list (documents only)
  Future<void> loadPhotoList() async {
    print('📋 Loading photo list...');

    final photos = await queryPhotosWithMetadata(ditto);

    _items.clear();
    _items.addAll(photos.map((p) => PhotoGalleryItem(p)));

    print('✅ Photo list loaded: ${_items.length} items');
    print('   (Metadata available, images NOT loaded yet)');
  }

  /// Load visible images
  Future<void> loadVisibleImages(List<int> visibleIndices) async {
    print('📥 Loading ${visibleIndices.length} visible images...');

    for (final index in visibleIndices) {
      if (index >= 0 && index < _items.length) {
        await _items[index].loadImage(ditto);
      }
    }

    print('✅ Visible images loaded');
  }

  void dispose() {
    // Cancel any in-progress fetches
  }
}
