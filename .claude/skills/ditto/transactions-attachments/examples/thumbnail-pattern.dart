// ============================================================================
// Thumbnail Pattern for Attachments
// ============================================================================
//
// This example demonstrates the recommended two-attachment pattern for
// photos and large files in Ditto: storing both a thumbnail and full-size image.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Two-attachment storage (thumbnail + full)
// 2. ✅ Size-based auto-fetch logic
// 3. ✅ Progressive image loading
// 4. ✅ User-initiated full download
// 5. ✅ Thumbnail generation
// 6. ✅ Metadata for both attachments
// 7. ✅ Bandwidth optimization
//
// WHY THIS PATTERN:
// - Thumbnails load quickly (instant gallery view)
// - Full images load only when needed (saves bandwidth)
// - Better user experience (progressive loading)
// - Works well on slow networks
// - Optimizes storage on devices
//
// ============================================================================

import 'package:ditto/ditto.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:image/image.dart' as img;

// ============================================================================
// PATTERN 1: Two-Attachment Storage
// ============================================================================

/// ✅ GOOD: Store both thumbnail and full image
class ThumbnailPhotoUploader {
  final Ditto ditto;

  ThumbnailPhotoUploader(this.ditto);

  Future<void> uploadPhoto(File photoFile) async {
    print('📤 Uploading photo with thumbnail...');

    // Read original image
    final originalBytes = await photoFile.readAsBytes();
    final originalImage = img.decodeImage(originalBytes);

    if (originalImage == null) {
      throw Exception('Failed to decode image');
    }

    print('  Original: ${originalImage.width}x${originalImage.height} (${originalBytes.length} bytes)');

    // Generate thumbnail (max 200px on longest side)
    final thumbnail = _generateThumbnail(originalImage, maxSize: 200);
    final thumbnailBytes = Uint8List.fromList(img.encodeJpg(thumbnail, quality: 85));

    print('  Thumbnail: ${thumbnail.width}x${thumbnail.height} (${thumbnailBytes.length} bytes)');

    // Create both attachments
    final fullAttachment = await ditto.store.newAttachment(
      '/path/to/photo.jpg',
      metadata: {'type': 'photo_full'},
    );

    final thumbnailAttachment = await ditto.store.newAttachment(
      '/path/to/thumbnail.jpg',
      metadata: {'type': 'photo_thumbnail'},
    );

    // Store document with both tokens
    final photoId = 'photo_${DateTime.now().millisecondsSinceEpoch}';

    await ditto.store.execute(
      '''INSERT INTO photos (
        _id,
        fileName,
        fullImageToken,
        fullImageMetadata,
        thumbnailToken,
        thumbnailMetadata,
        createdAt
      ) VALUES (
        :id,
        :fileName,
        :fullToken,
        :fullMetadata,
        :thumbToken,
        :thumbMetadata,
        :createdAt
      )''',
      arguments: {
        'id': photoId,
        'fileName': photoFile.path.split('/').last,
        'fullToken': fullAttachment,
        'fullMetadata': {
          'sizeBytes': originalBytes.length,
          'width': originalImage.width,
          'height': originalImage.height,
          'mimeType': 'image/jpeg',
        },
        'thumbToken': thumbnailAttachment,
        'thumbMetadata': {
          'sizeBytes': thumbnailBytes.length,
          'width': thumbnail.width,
          'height': thumbnail.height,
          'mimeType': 'image/jpeg',
        },
        'createdAt': DateTime.now().toIso8601String(),
      },
    );

    print('✅ Photo uploaded with thumbnail');
    print('  Photo ID: $photoId');
    print('  Full size: ${(originalBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
    print('  Thumbnail size: ${(thumbnailBytes.length / 1024).toStringAsFixed(2)} KB');
  }

  img.Image _generateThumbnail(img.Image original, {required int maxSize}) {
    final width = original.width;
    final height = original.height;

    if (width <= maxSize && height <= maxSize) {
      return original;
    }

    if (width > height) {
      return img.copyResize(original, width: maxSize);
    } else {
      return img.copyResize(original, height: maxSize);
    }
  }
}

// ============================================================================
// PATTERN 2: Size-Based Auto-Fetch Logic
// ============================================================================

/// ✅ GOOD: Auto-fetch thumbnails, on-demand full images
class SizeBasedFetchStrategy {
  final Ditto ditto;
  static const int AUTO_FETCH_THRESHOLD = 1024 * 1024; // 1 MB

  SizeBasedFetchStrategy(this.ditto);

  Future<void> loadPhotoWithStrategy(String photoId) async {
    print('📥 Loading photo with size-based strategy...');

    // Query photo document
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
    final fullMetadata = doc['fullImageMetadata'] as Map<String, dynamic>;
    final fullSizeBytes = fullMetadata['sizeBytes'] as int;

    // ✅ STRATEGY: Always auto-fetch thumbnail (small)
    print('  📥 Auto-fetching thumbnail (always)...');
    final thumbnail = await _fetchAttachment(thumbnailToken);

    if (thumbnail != null) {
      print('  ✅ Thumbnail loaded: ${thumbnail.length} bytes');
      // Display thumbnail in UI immediately
    }

    // ✅ STRATEGY: Auto-fetch full image only if small
    if (fullSizeBytes < AUTO_FETCH_THRESHOLD) {
      print('  📥 Auto-fetching full image (small file)...');
      final fullImage = await _fetchAttachment(fullImageToken);

      if (fullImage != null) {
        print('  ✅ Full image loaded: ${fullImage.length} bytes');
        // Replace thumbnail with full image
      }
    } else {
      print('  ⏸️ Full image is large (${(fullSizeBytes / 1024 / 1024).toStringAsFixed(2)} MB)');
      print('  Waiting for user action to download');
    }
  }

  Future<Uint8List?> _fetchAttachment(DittoAttachmentToken token) async {
    try {
      final fetcher = ditto.store.fetchAttachment(token);
      final attachment = await fetcher.attachment.timeout(
        const Duration(seconds: 10),
      );
      return attachment?.getData();
    } catch (e) {
      print('  ❌ Fetch failed: $e');
      return null;
    }
  }
}

// ============================================================================
// PATTERN 3: Progressive Image Loading
// ============================================================================

/// ✅ GOOD: Progressive loading with state management
class ProgressivePhotoLoader {
  final Ditto ditto;

  ProgressivePhotoLoader(this.ditto);

  Future<PhotoLoadState> loadPhotoProgressive(String photoId) async {
    print('📥 Progressive photo loading: $photoId');

    final state = PhotoLoadState(photoId);

    // Query document
    final result = await ditto.store.execute(
      'SELECT * FROM photos WHERE _id = :photoId',
      arguments: {'photoId': photoId},
    );

    if (result.items.isEmpty) {
      state.error = 'Photo not found';
      return state;
    }

    final doc = result.items.first.value;
    state.fileName = doc['fileName'] as String;
    state.thumbnailToken = doc['thumbnailToken'] as DittoAttachmentToken;
    state.fullImageToken = doc['fullImageToken'] as DittoAttachmentToken;
    state.fullImageMetadata = doc['fullImageMetadata'] as Map<String, dynamic>;

    // Phase 1: Load thumbnail
    print('  Phase 1: Loading thumbnail...');
    state.isThumbnailLoading = true;

    final thumbnail = await _fetchAttachment(state.thumbnailToken!);
    state.isThumbnailLoading = false;

    if (thumbnail != null) {
      state.thumbnailData = thumbnail;
      state.hasThumbnail = true;
      print('  ✅ Thumbnail loaded: ${thumbnail.length} bytes');
    } else {
      print('  ⚠️ Thumbnail not available');
    }

    // Phase 2: Load full image in background
    print('  Phase 2: Loading full image in background...');
    state.isFullImageLoading = true;

    final fullImage = await _fetchAttachment(state.fullImageToken!);
    state.isFullImageLoading = false;

    if (fullImage != null) {
      state.fullImageData = fullImage;
      state.hasFullImage = true;
      print('  ✅ Full image loaded: ${fullImage.length} bytes');
    } else {
      print('  ⚠️ Full image not available');
    }

    print('✅ Progressive loading complete');
    return state;
  }

  Future<Uint8List?> _fetchAttachment(DittoAttachmentToken token) async {
    try {
      final fetcher = ditto.store.fetchAttachment(token);
      final attachment = await fetcher.attachment;
      return attachment?.getData();
    } catch (e) {
      return null;
    }
  }
}

class PhotoLoadState {
  final String photoId;
  String? fileName;
  DittoAttachmentToken? thumbnailToken;
  DittoAttachmentToken? fullImageToken;
  Map<String, dynamic>? fullImageMetadata;

  Uint8List? thumbnailData;
  Uint8List? fullImageData;

  bool isThumbnailLoading = false;
  bool isFullImageLoading = false;
  bool hasThumbnail = false;
  bool hasFullImage = false;
  String? error;

  PhotoLoadState(this.photoId);

  String get displayStatus {
    if (error != null) return '❌ Error: $error';
    if (isFullImageLoading) return '⏳ Loading full image...';
    if (isThumbnailLoading) return '⏳ Loading thumbnail...';
    if (hasFullImage) return '✅ Full image loaded';
    if (hasThumbnail) return '✅ Thumbnail loaded';
    return 'Not loaded';
  }

  int? get fullImageSizeBytes {
    return fullImageMetadata?['sizeBytes'] as int?;
  }

  String get fullImageSizeMB {
    final bytes = fullImageSizeBytes;
    if (bytes == null) return 'Unknown';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}

// ============================================================================
// PATTERN 4: User-Initiated Full Download
// ============================================================================

/// ✅ GOOD: User controls when to download full image
class UserInitiatedDownload {
  final Ditto ditto;
  final Map<String, PhotoDownloadState> _downloads = {};

  UserInitiatedDownload(this.ditto);

  Future<void> loadPhotoList() async {
    print('📋 Loading photo list (thumbnails only)...');

    final result = await ditto.store.execute(
      'SELECT * FROM photos ORDER BY createdAt DESC LIMIT 20',
    );

    for (final item in result.items) {
      final doc = item.value;
      final photoId = doc['_id'] as String;
      final fileName = doc['fileName'] as String;
      final thumbnailToken = doc['thumbnailToken'] as DittoAttachmentToken;
      final fullMetadata = doc['fullImageMetadata'] as Map<String, dynamic>;

      final state = PhotoDownloadState(
        photoId: photoId,
        fileName: fileName,
        thumbnailToken: thumbnailToken,
        fullImageToken: doc['fullImageToken'] as DittoAttachmentToken,
        fullImageSizeBytes: fullMetadata['sizeBytes'] as int,
      );

      _downloads[photoId] = state;

      // Auto-fetch thumbnail
      _fetchThumbnail(photoId);
    }

    print('✅ Photo list loaded (${_downloads.length} photos)');
  }

  Future<void> _fetchThumbnail(String photoId) async {
    final state = _downloads[photoId];
    if (state == null) return;

    state.isThumbnailLoading = true;

    final fetcher = ditto.store.fetchAttachment(state.thumbnailToken);
    final attachment = await fetcher.attachment;

    state.isThumbnailLoading = false;

    if (attachment != null) {
      state.thumbnailData = attachment.getData();
      state.hasThumbnail = true;
      print('  ✅ Thumbnail loaded: ${state.fileName}');
    }
  }

  /// User taps "Download Full Image" button
  Future<void> downloadFullImage(String photoId) async {
    final state = _downloads[photoId];
    if (state == null) return;

    if (state.hasFullImage) {
      print('Full image already downloaded');
      return;
    }

    print('📥 User requested full image download: ${state.fileName}');
    print('  Size: ${(state.fullImageSizeBytes / 1024 / 1024).toStringAsFixed(2)} MB');

    state.isFullImageLoading = true;
    state.downloadProgress = 0.0;

    try {
      final fetcher = ditto.store.fetchAttachment(state.fullImageToken);
      final attachment = await fetcher.attachment.timeout(
        const Duration(seconds: 60),
      );

      state.isFullImageLoading = false;

      if (attachment != null) {
        state.fullImageData = attachment.getData();
        state.hasFullImage = true;
        state.downloadProgress = 1.0;
        print('  ✅ Full image downloaded: ${state.fullImageData!.length} bytes');
      } else {
        state.downloadError = 'Attachment not available';
        print('  ❌ Download failed: ${state.downloadError}');
      }
    } catch (e) {
      state.isFullImageLoading = false;
      state.downloadError = e.toString();
      print('  ❌ Download failed: $e');
    }
  }

  PhotoDownloadState? getPhotoState(String photoId) {
    return _downloads[photoId];
  }
}

class PhotoDownloadState {
  final String photoId;
  final String fileName;
  final DittoAttachmentToken thumbnailToken;
  final DittoAttachmentToken fullImageToken;
  final int fullImageSizeBytes;

  Uint8List? thumbnailData;
  Uint8List? fullImageData;

  bool isThumbnailLoading = false;
  bool isFullImageLoading = false;
  bool hasThumbnail = false;
  bool hasFullImage = false;
  double downloadProgress = 0.0;
  String? downloadError;

  PhotoDownloadState({
    required this.photoId,
    required this.fileName,
    required this.thumbnailToken,
    required this.fullImageToken,
    required this.fullImageSizeBytes,
  });

  String get fullImageSizeMB {
    return '${(fullImageSizeBytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  String get displayStatus {
    if (downloadError != null) return '❌ Error: $downloadError';
    if (isFullImageLoading) return '⏳ Downloading... ${(downloadProgress * 100).toInt()}%';
    if (hasFullImage) return '✅ Full image available';
    if (hasThumbnail) return '✅ Thumbnail (tap to download full)';
    if (isThumbnailLoading) return '⏳ Loading thumbnail...';
    return 'Not loaded';
  }
}

// ============================================================================
// PATTERN 5: Bandwidth Optimization
// ============================================================================

/// ✅ GOOD: Bandwidth-aware loading strategy
class BandwidthOptimizedLoader {
  final Ditto ditto;

  BandwidthOptimizedLoader(this.ditto);

  Future<void> loadPhotosForGallery(List<String> photoIds) async {
    print('📥 Loading photos with bandwidth optimization...');

    // ✅ STRATEGY: Thumbnails only for large galleries
    print('  Loading ${photoIds.length} photos (thumbnails only)');

    for (final photoId in photoIds) {
      await _loadThumbnailOnly(photoId);
    }

    print('✅ Gallery loaded (thumbnails only)');
    print('  Bandwidth saved by not loading full images');
    print('  Full images load on user demand');
  }

  Future<void> _loadThumbnailOnly(String photoId) async {
    final result = await ditto.store.execute(
      'SELECT * FROM photos WHERE _id = :photoId',
      arguments: {'photoId': photoId},
    );

    if (result.items.isEmpty) return;

    final doc = result.items.first.value;
    final thumbnailToken = doc['thumbnailToken'] as DittoAttachmentToken;
    final fileName = doc['fileName'] as String;

    final fetcher = ditto.store.fetchAttachment(thumbnailToken);
    final attachment = await fetcher.attachment;

    if (attachment != null) {
      final data = attachment.getData();
      print('  ✅ Thumbnail: $fileName (${(data.length / 1024).toStringAsFixed(2)} KB)');
    }
  }

  Future<void> preloadVisiblePhotos(List<String> visiblePhotoIds) async {
    print('📥 Preloading visible photos...');

    // ✅ Only load full images for photos in viewport
    for (final photoId in visiblePhotoIds) {
      await _loadFullImage(photoId);
    }

    print('✅ Visible photos preloaded');
  }

  Future<void> _loadFullImage(String photoId) async {
    final result = await ditto.store.execute(
      'SELECT * FROM photos WHERE _id = :photoId',
      arguments: {'photoId': photoId},
    );

    if (result.items.isEmpty) return;

    final doc = result.items.first.value;
    final fullImageToken = doc['fullImageToken'] as DittoAttachmentToken;
    final fileName = doc['fileName'] as String;

    final fetcher = ditto.store.fetchAttachment(fullImageToken);
    final attachment = await fetcher.attachment;

    if (attachment != null) {
      final data = attachment.getData();
      print('  ✅ Full image: $fileName (${(data.length / 1024 / 1024).toStringAsFixed(2)} MB)');
    }
  }
}

// ============================================================================
// Complete Example: Photo Gallery with Thumbnails
// ============================================================================

/// Production-ready photo gallery with thumbnail pattern
class ThumbnailPhotoGallery {
  final Ditto ditto;
  final Map<String, PhotoDownloadState> _photos = {};

  ThumbnailPhotoGallery(this.ditto);

  Future<void> initialize() async {
    print('🎨 Initializing photo gallery...');

    final result = await ditto.store.execute(
      'SELECT * FROM photos ORDER BY createdAt DESC LIMIT 50',
    );

    for (final item in result.items) {
      final doc = item.value;
      final state = PhotoDownloadState(
        photoId: doc['_id'] as String,
        fileName: doc['fileName'] as String,
        thumbnailToken: doc['thumbnailToken'] as DittoAttachmentToken,
        fullImageToken: doc['fullImageToken'] as DittoAttachmentToken,
        fullImageSizeBytes: (doc['fullImageMetadata'] as Map<String, dynamic>)['sizeBytes'] as int,
      );
      _photos[state.photoId] = state;
    }

    print('✅ Gallery initialized with ${_photos.length} photos');

    // Auto-load all thumbnails
    await _loadAllThumbnails();
  }

  Future<void> _loadAllThumbnails() async {
    print('📥 Loading all thumbnails...');

    for (final state in _photos.values) {
      final fetcher = ditto.store.fetchAttachment(state.thumbnailToken);
      final attachment = await fetcher.attachment;

      if (attachment != null) {
        state.thumbnailData = attachment.getData();
        state.hasThumbnail = true;
      }
    }

    print('✅ All thumbnails loaded');
  }

  Future<void> downloadFullImage(String photoId) async {
    final state = _photos[photoId];
    if (state == null || state.hasFullImage) return;

    print('📥 Downloading full image: ${state.fileName} (${state.fullImageSizeMB})');

    state.isFullImageLoading = true;

    final fetcher = ditto.store.fetchAttachment(state.fullImageToken);
    final attachment = await fetcher.attachment;

    state.isFullImageLoading = false;

    if (attachment != null) {
      state.fullImageData = attachment.getData();
      state.hasFullImage = true;
      print('  ✅ Downloaded: ${state.fileName}');
    }
  }

  List<PhotoDownloadState> get photos => _photos.values.toList();
}
