// SDK Version: All
// Platform: All
// Last Updated: 2025-12-19
//
// ============================================================================
// Attachment Lazy-Loading Anti-Patterns
// ============================================================================
//
// This example demonstrates common mistakes when handling attachments in Ditto,
// which lead to missing data, poor UX, and application crashes.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ Missing fetchAttachment() call
// 2. ❌ Attempting to display token directly
// 3. ❌ No error handling for fetch failures
// 4. ❌ Missing metadata storage
// 5. ❌ Synchronous fetch assumption
// 6. ❌ No loading state management
// 7. ❌ Retaining attachment fetchers
//
// WHY THESE ARE PROBLEMS:
// - Attachments NOT auto-synced with subscriptions
// - Token is not image data
// - Network failures cause crashes
// - Poor user experience
//
// SOLUTION: See attachment-lazy-loading-good.dart for correct patterns
//
// ============================================================================

import 'package:ditto/ditto.dart';
import 'dart:typed_data';

// ============================================================================
// ANTI-PATTERN 1: Missing fetchAttachment() Call
// ============================================================================

/// ❌ BAD: Assuming attachment is automatically available
class AutoSyncAssumptionBad {
  final Ditto ditto;

  AutoSyncAssumptionBad(this.ditto);

  Future<void> displayPhoto(String photoId) async {
    print('❌ Attempting to display photo without fetching...');

    // Query document
    final result = await ditto.store.execute(
      'SELECT * FROM photos WHERE _id = :photoId',
      arguments: {'photoId': photoId},
    );

    if (result.items.isEmpty) {
      print('Photo not found');
      return;
    }

    final doc = result.items.first.value;
    final imageToken = doc['imageToken'] as DittoAttachmentToken;

    // ❌ BAD: No fetchAttachment() call!
    // Subscription synced the document, but NOT the attachment
    // The token exists, but the actual image data is not downloaded

    print('  ❌ Have token, but no image data!');
    print('  Token: ${imageToken.toString()}');

    // 🚨 PROBLEMS:
    // - Image file not downloaded
    // - Cannot display image to user
    // - Silent failure (no error, just missing image)
    // - User sees broken image placeholder
  }
}

/// ✅ GOOD: Explicit fetchAttachment() call
class ExplicitFetchGood {
  final Ditto ditto;

  ExplicitFetchGood(this.ditto);

  Future<Uint8List?> displayPhoto(String photoId) async {
    final result = await ditto.store.execute(
      'SELECT * FROM photos WHERE _id = :photoId',
      arguments: {'photoId': photoId},
    );

    if (result.items.isEmpty) return null;

    final doc = result.items.first.value;
    final imageToken = doc['imageToken'] as DittoAttachmentToken;

    // ✅ GOOD: Explicit fetch required
    final fetcher = ditto.store.fetchAttachment(imageToken);
    final attachment = await fetcher.attachment;

    if (attachment == null) {
      print('Attachment not available');
      return null;
    }

    final data = attachment.getData();
    print('✅ Image fetched: ${data.length} bytes');
    return data;
  }
}

// ============================================================================
// ANTI-PATTERN 2: Attempting to Display Token Directly
// ============================================================================

/// ❌ BAD: Treating token as image data
class TokenAsDataBad {
  final Ditto ditto;

  TokenAsDataBad(this.ditto);

  Future<void> loadPhotoList() async {
    print('❌ Loading photos with token confusion...');

    final result = await ditto.store.execute(
      'SELECT * FROM photos ORDER BY createdAt DESC',
    );

    for (final item in result.items) {
      final doc = item.value;
      final photoId = doc['_id'] as String;
      final imageToken = doc['imageToken'] as DittoAttachmentToken;

      // ❌ BAD: Attempting to use token as image
      print('  Photo: $photoId');
      print('  ❌ Token: ${imageToken.toString()}');
      print('  ❌ Trying to display token (will fail)');

      // Developer might try:
      // Image.memory(imageToken as Uint8List) // ❌ Type error!
      // or
      // displayImage(imageToken.toString()) // ❌ Shows token ID, not image

      // 🚨 PROBLEMS:
      // - Token is metadata, NOT image bytes
      // - Cannot render token as image
      // - Type errors or display errors
      // - Broken UI
    }
  }
}

// ============================================================================
// ANTI-PATTERN 3: No Error Handling for Fetch Failures
// ============================================================================

/// ❌ BAD: No error handling when fetching attachment
class NoErrorHandlingBad {
  final Ditto ditto;

  NoErrorHandlingBad(this.ditto);

  Future<Uint8List> fetchPhoto(DittoAttachmentToken token) async {
    print('❌ Fetching attachment without error handling...');

    // ❌ BAD: No try-catch
    final fetcher = ditto.store.fetchAttachment(token);
    final attachment = await fetcher.attachment;

    // ❌ BAD: No null check
    final data = attachment!.getData(); // Crashes if attachment is null!

    // 🚨 PROBLEMS:
    // - Network failures cause crash
    // - Missing attachments cause crash
    // - Timeout issues unhandled
    // - No user feedback
    // - Application unusable

    return data;
  }
}

/// ✅ GOOD: Robust error handling
class ErrorHandlingGood {
  final Ditto ditto;

  ErrorHandlingGood(this.ditto);

  Future<Uint8List?> fetchPhoto(DittoAttachmentToken token) async {
    try {
      final fetcher = ditto.store.fetchAttachment(token);

      final attachment = await fetcher.attachment.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          print('⏱️ Attachment fetch timeout');
          return null;
        },
      );

      if (attachment == null) {
        print('⚠️ Attachment not available');
        return null;
      }

      final data = attachment.getData();
      print('✅ Attachment fetched: ${data.length} bytes');
      return data;
    } catch (e) {
      print('❌ Fetch failed: $e');
      return null;
    }
  }
}

// ============================================================================
// ANTI-PATTERN 4: Missing Metadata Storage
// ============================================================================

/// ❌ BAD: Not storing attachment metadata
class NoMetadataBad {
  final Ditto ditto;

  NoMetadataBad(this.ditto);

  Future<void> uploadPhoto(DittoAttachment attachment) async {
    print('❌ Uploading photo without metadata...');

    // ❌ BAD: Only storing token
    await ditto.store.execute(
      'INSERT INTO photos (_id, imageToken) VALUES (:id, :token)',
      arguments: {
        'id': 'photo_${DateTime.now().millisecondsSinceEpoch}',
        'token': attachment,
      },
    );

    print('  ❌ No metadata stored');

    // 🚨 PROBLEMS:
    // - Cannot display file size before fetch
    // - Cannot show dimensions before fetch
    // - Cannot filter by file type
    // - Poor user experience (no info while loading)
    // - Cannot decide whether to auto-fetch or wait for user action
  }
}

/// ✅ GOOD: Store comprehensive metadata
class MetadataGood {
  final Ditto ditto;

  MetadataGood(this.ditto);

  Future<void> uploadPhoto(
    DittoAttachment attachment,
    String fileName,
    int sizeBytes,
    int width,
    int height,
  ) async {
    // ✅ GOOD: Store metadata alongside token
    await ditto.store.execute(
      '''INSERT INTO photos (
        _id, imageToken, fileName, sizeBytes, width, height, mimeType, createdAt
      ) VALUES (
        :id, :token, :fileName, :sizeBytes, :width, :height, :mimeType, :createdAt
      )''',
      arguments: {
        'id': 'photo_${DateTime.now().millisecondsSinceEpoch}',
        'token': attachment,
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        'width': width,
        'height': height,
        'mimeType': 'image/jpeg',
        'createdAt': DateTime.now().toIso8601String(),
      },
    );

    print('✅ Photo uploaded with metadata');
    print('  File: $fileName');
    print('  Size: ${(sizeBytes / 1024 / 1024).toStringAsFixed(2)} MB');
    print('  Dimensions: ${width}x$height');
  }
}

// ============================================================================
// ANTI-PATTERN 5: Synchronous Fetch Assumption
// ============================================================================

/// ❌ BAD: Expecting attachment to be immediately available
class SyncFetchAssumptionBad {
  final Ditto ditto;

  SyncFetchAssumptionBad(this.ditto);

  Future<void> displayPhotoGallery() async {
    print('❌ Loading gallery with sync assumption...');

    final result = await ditto.store.execute(
      'SELECT * FROM photos ORDER BY createdAt DESC LIMIT 20',
    );

    print('Found ${result.items.length} photos');

    // ❌ BAD: Trying to fetch all attachments immediately
    for (final item in result.items) {
      final doc = item.value;
      final photoId = doc['_id'] as String;
      final token = doc['imageToken'] as DittoAttachmentToken;

      // ❌ BAD: Expecting instant availability
      final fetcher = ditto.store.fetchAttachment(token);
      final attachment = await fetcher.attachment;

      if (attachment == null) {
        print('  ❌ Photo $photoId: Not available (unexpected!)');
        // Developer assumes this never happens
      }
    }

    // 🚨 PROBLEMS:
    // - Attachments may not be downloaded yet
    // - Large attachments take time to fetch
    // - Network conditions affect availability
    // - No progressive loading
    // - Poor user experience (long wait)
  }
}

/// ✅ GOOD: Progressive loading with metadata
class ProgressiveLoadingGood {
  final Ditto ditto;

  ProgressiveLoadingGood(this.ditto);

  Future<void> displayPhotoGallery() async {
    print('📋 Loading gallery metadata...');

    final result = await ditto.store.execute(
      'SELECT * FROM photos ORDER BY createdAt DESC LIMIT 20',
    );

    // ✅ Display metadata immediately
    for (final item in result.items) {
      final doc = item.value;
      final photoId = doc['_id'] as String;
      final fileName = doc['fileName'] as String;
      final sizeBytes = doc['sizeBytes'] as int;

      print('  Photo: $fileName (${(sizeBytes / 1024 / 1024).toStringAsFixed(2)} MB)');
    }

    print('✅ Metadata displayed, images load on demand');
  }

  Future<Uint8List?> loadPhotoOnDemand(String photoId) async {
    print('📥 Loading photo on demand: $photoId');

    final result = await ditto.store.execute(
      'SELECT * FROM photos WHERE _id = :photoId',
      arguments: {'photoId': photoId},
    );

    if (result.items.isEmpty) return null;

    final doc = result.items.first.value;
    final token = doc['imageToken'] as DittoAttachmentToken;

    // ✅ Fetch only when user scrolls to image
    final fetcher = ditto.store.fetchAttachment(token);
    final attachment = await fetcher.attachment;

    if (attachment == null) return null;

    final data = attachment.getData();
    print('  ✅ Photo loaded: ${data.length} bytes');
    return data;
  }
}

// ============================================================================
// ANTI-PATTERN 6: No Loading State Management
// ============================================================================

/// ❌ BAD: No loading indicators
class NoLoadingStateBad {
  final Ditto ditto;
  Uint8List? imageData;

  NoLoadingStateBad(this.ditto);

  Future<void> loadPhoto(String photoId) async {
    print('❌ Loading photo without loading state...');

    // ❌ BAD: No loading indicator
    // User sees nothing until fetch completes

    final result = await ditto.store.execute(
      'SELECT * FROM photos WHERE _id = :photoId',
      arguments: {'photoId': photoId},
    );

    if (result.items.isEmpty) return;

    final doc = result.items.first.value;
    final token = doc['imageToken'] as DittoAttachmentToken;

    // ❌ BAD: Long fetch with no user feedback
    final fetcher = ditto.store.fetchAttachment(token);
    final attachment = await fetcher.attachment; // May take 10+ seconds!

    if (attachment != null) {
      imageData = attachment.getData();
      print('  ❌ Image suddenly appears (no loading indicator)');
    }

    // 🚨 PROBLEMS:
    // - User doesn't know if app is working
    // - Appears frozen during fetch
    // - No way to cancel
    // - Poor user experience
  }
}

/// ✅ GOOD: Proper loading state management
class LoadingStateGood {
  final Ditto ditto;
  Uint8List? imageData;
  bool isLoading = false;
  String? loadError;

  LoadingStateGood(this.ditto);

  Future<void> loadPhoto(String photoId) async {
    print('📥 Loading photo with state management...');

    // ✅ Set loading state
    isLoading = true;
    imageData = null;
    loadError = null;

    print('  ⏳ Loading...');

    try {
      final result = await ditto.store.execute(
        'SELECT * FROM photos WHERE _id = :photoId',
        arguments: {'photoId': photoId},
      );

      if (result.items.isEmpty) {
        throw Exception('Photo not found');
      }

      final doc = result.items.first.value;
      final token = doc['imageToken'] as DittoAttachmentToken;

      // ✅ Fetch with timeout
      final fetcher = ditto.store.fetchAttachment(token);
      final attachment = await fetcher.attachment.timeout(
        const Duration(seconds: 30),
        onTimeout: () => null,
      );

      if (attachment == null) {
        throw Exception('Attachment not available');
      }

      imageData = attachment.getData();
      print('  ✅ Photo loaded successfully');
    } catch (e) {
      loadError = e.toString();
      print('  ❌ Failed to load: $loadError');
    } finally {
      isLoading = false;
    }
  }

  String getDisplayStatus() {
    if (isLoading) return '⏳ Loading...';
    if (loadError != null) return '❌ Error: $loadError';
    if (imageData != null) return '✅ Loaded (${imageData!.length} bytes)';
    return 'Not loaded';
  }
}

// ============================================================================
// ANTI-PATTERN 7: Retaining Attachment Fetchers
// ============================================================================

/// ❌ BAD: Storing fetchers causes memory leaks
class RetainedFetchersBad {
  final Ditto ditto;
  final List<DittoAttachmentFetcher> _fetchers = []; // ❌ Memory leak!

  RetainedFetchersBad(this.ditto);

  Future<void> loadPhotos(List<String> photoIds) async {
    print('❌ Loading photos with retained fetchers...');

    for (final photoId in photoIds) {
      final result = await ditto.store.execute(
        'SELECT * FROM photos WHERE _id = :photoId',
        arguments: {'photoId': photoId},
      );

      if (result.items.isEmpty) continue;

      final doc = result.items.first.value;
      final token = doc['imageToken'] as DittoAttachmentToken;

      // ❌ BAD: Storing fetcher reference
      final fetcher = ditto.store.fetchAttachment(token);
      _fetchers.add(fetcher); // ❌ Never cleaned up!

      fetcher.attachment.then((attachment) {
        if (attachment != null) {
          final data = attachment.getData();
          print('  Photo loaded: ${data.length} bytes');
        }
      });
    }

    print('  ❌ ${_fetchers.length} fetchers retained (memory leak)');

    // 🚨 PROBLEMS:
    // - Fetchers consume memory
    // - Never released
    // - Memory usage grows unbounded
    // - App performance degrades
  }
}

/// ✅ GOOD: Temporary fetchers, no retention
class NoRetentionGood {
  final Ditto ditto;

  NoRetentionGood(this.ditto);

  Future<void> loadPhotos(List<String> photoIds) async {
    print('✅ Loading photos without retention...');

    for (final photoId in photoIds) {
      await _loadPhoto(photoId);
    }

    print('✅ All photos loaded, no memory leaks');
  }

  Future<void> _loadPhoto(String photoId) async {
    final result = await ditto.store.execute(
      'SELECT * FROM photos WHERE _id = :photoId',
      arguments: {'photoId': photoId},
    );

    if (result.items.isEmpty) return;

    final doc = result.items.first.value;
    final token = doc['imageToken'] as DittoAttachmentToken;

    // ✅ Temporary fetcher (local variable)
    final fetcher = ditto.store.fetchAttachment(token);

    try {
      final attachment = await fetcher.attachment;
      if (attachment != null) {
        final data = attachment.getData();
        print('  ✅ Photo loaded: ${data.length} bytes');
      }
    } finally {
      // Fetcher automatically released when function returns
    }
  }
}
