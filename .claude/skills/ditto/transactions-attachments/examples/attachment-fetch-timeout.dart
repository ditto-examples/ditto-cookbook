// ============================================================================
// Attachment Fetch Timeout Handling
// ============================================================================
//
// This example demonstrates proper timeout handling when fetching attachments
// in Ditto, preventing hung requests and providing good user experience.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Basic timeout with Future.timeout()
// 2. ✅ Retry logic with exponential backoff
// 3. ✅ Progress tracking and cancellation
// 4. ✅ Network condition awareness
// 5. ✅ Graceful degradation
// 6. ✅ User-facing error messages
// 7. ✅ Timeout configuration per file size
//
// WHY TIMEOUT HANDLING IS CRITICAL:
// - Attachments may be large (MBs to GBs)
// - Network conditions vary (WiFi, cellular, peer-to-peer)
// - Stalled fetches freeze UI
// - Users need feedback and control
//
// ============================================================================

import 'package:ditto/ditto.dart';
import 'dart:typed_data';
import 'dart:async';

// ============================================================================
// PATTERN 1: Basic Timeout with Future.timeout()
// ============================================================================

/// ✅ GOOD: Simple timeout wrapper
class BasicTimeoutFetcher {
  final Ditto ditto;

  BasicTimeoutFetcher(this.ditto);

  Future<Uint8List?> fetchAttachmentWithTimeout(
    DittoAttachmentToken token,
    String documentId, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    print('📥 Fetching attachment with ${timeout.inSeconds}s timeout...');

    try {
      final fetcher = ditto.store.fetchAttachment(token);

      // ✅ Basic timeout
      final attachment = await fetcher.attachment.timeout(
        timeout,
        onTimeout: () {
          print('  ⏱️ Fetch timeout after ${timeout.inSeconds}s');
          return null;
        },
      );

      if (attachment == null) {
        print('  ⚠️ Attachment not available');
        return null;
      }

      final data = attachment.getData();
      print('  ✅ Fetched: ${data.length} bytes');
      return data;

    } catch (e) {
      print('  ❌ Fetch failed: $e');
      return null;
    }
  }
}

// ============================================================================
// PATTERN 2: Retry Logic with Exponential Backoff
// ============================================================================

/// ✅ GOOD: Retry failed fetches with exponential backoff
class RetryableFetcher {
  final Ditto ditto;

  RetryableFetcher(this.ditto);

  Future<FetchResult> fetchWithRetry(
    DittoAttachmentToken token,
    String documentId, {
    int maxRetries = 3,
    Duration initialTimeout = const Duration(seconds: 30),
  }) async {
    print('📥 Fetching with retry (max $maxRetries attempts)...');

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      print('  Attempt $attempt/$maxRetries');

      // Exponential timeout increase
      final timeout = initialTimeout * attempt;

      try {
        final fetcher = ditto.store.fetchAttachment(token);

        final attachment = await fetcher.attachment.timeout(
          timeout,
          onTimeout: () {
            print('    ⏱️ Timeout after ${timeout.inSeconds}s');
            return null;
          },
        );

        if (attachment != null) {
          final data = attachment.getData();
          print('  ✅ Success on attempt $attempt: ${data.length} bytes');
          return FetchResult.success(data);
        }

        print('    ⚠️ Attachment not available, retrying...');

        // Wait before retry (exponential backoff)
        if (attempt < maxRetries) {
          final delay = Duration(seconds: 2 * attempt);
          print('    Waiting ${delay.inSeconds}s before retry...');
          await Future.delayed(delay);
        }

      } catch (e) {
        print('    ❌ Attempt $attempt failed: $e');

        if (attempt == maxRetries) {
          return FetchResult.error('Failed after $maxRetries attempts: $e');
        }

        // Wait before retry
        final delay = Duration(seconds: 2 * attempt);
        await Future.delayed(delay);
      }
    }

    return FetchResult.error('Failed after $maxRetries attempts');
  }
}

class FetchResult {
  final Uint8List? data;
  final String? error;
  final bool isSuccess;

  FetchResult._({this.data, this.error, required this.isSuccess});

  factory FetchResult.success(Uint8List data) =>
      FetchResult._(data: data, isSuccess: true);

  factory FetchResult.error(String message) =>
      FetchResult._(error: message, isSuccess: false);
}

// ============================================================================
// PATTERN 3: Progress Tracking and Cancellation
// ============================================================================

/// ✅ GOOD: Track progress and allow cancellation
class CancellableFetcher {
  final Ditto ditto;
  DittoAttachmentFetcher? _currentFetcher;
  bool _isCancelled = false;

  CancellableFetcher(this.ditto);

  Future<FetchProgressResult> fetchWithProgress(
    DittoAttachmentToken token,
    String documentId,
    void Function(double progress) onProgress, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    print('📥 Fetching with progress tracking...');

    _isCancelled = false;

    try {
      _currentFetcher = ditto.store.fetchAttachment(token);

      // Simulate progress tracking (actual progress depends on SDK capabilities)
      _trackProgress(onProgress, timeout);

      final attachment = await _currentFetcher!.attachment.timeout(
        timeout,
        onTimeout: () {
          print('  ⏱️ Timeout after ${timeout.inSeconds}s');
          return null;
        },
      );

      if (_isCancelled) {
        print('  🚫 Fetch cancelled by user');
        return FetchProgressResult.cancelled();
      }

      if (attachment == null) {
        return FetchProgressResult.notFound();
      }

      final data = attachment.getData();
      print('  ✅ Fetch complete: ${data.length} bytes');
      return FetchProgressResult.success(data);

    } catch (e) {
      if (_isCancelled) {
        return FetchProgressResult.cancelled();
      }
      print('  ❌ Fetch failed: $e');
      return FetchProgressResult.error(e.toString());
    } finally {
      _currentFetcher = null;
    }
  }

  void _trackProgress(void Function(double) onProgress, Duration timeout) {
    final startTime = DateTime.now();
    final timeoutMs = timeout.inMilliseconds;

    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_isCancelled || _currentFetcher == null) {
        timer.cancel();
        return;
      }

      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      final progress = (elapsed / timeoutMs).clamp(0.0, 0.99);
      onProgress(progress);

      if (elapsed >= timeoutMs) {
        timer.cancel();
      }
    });
  }

  void cancel() {
    print('🚫 Cancelling fetch...');
    _isCancelled = true;
    _currentFetcher?.cancel();
    _currentFetcher = null;
  }
}

class FetchProgressResult {
  final Uint8List? data;
  final String? error;
  final bool isSuccess;
  final bool isCancelled;

  FetchProgressResult._({
    this.data,
    this.error,
    required this.isSuccess,
    this.isCancelled = false,
  });

  factory FetchProgressResult.success(Uint8List data) =>
      FetchProgressResult._(data: data, isSuccess: true);

  factory FetchProgressResult.notFound() =>
      FetchProgressResult._(isSuccess: false, error: 'Attachment not found');

  factory FetchProgressResult.error(String message) =>
      FetchProgressResult._(isSuccess: false, error: message);

  factory FetchProgressResult.cancelled() =>
      FetchProgressResult._(isSuccess: false, isCancelled: true);
}

// ============================================================================
// PATTERN 4: Network Condition Awareness
// ============================================================================

/// ✅ GOOD: Adjust timeout based on network conditions
class NetworkAwareFetcher {
  final Ditto ditto;

  NetworkAwareFetcher(this.ditto);

  Future<Uint8List?> fetchWithNetworkAwareness(
    DittoAttachmentToken token,
    int expectedSizeBytes,
    NetworkCondition networkCondition,
  ) async {
    print('📥 Fetching with network awareness...');
    print('  Expected size: ${(expectedSizeBytes / 1024 / 1024).toStringAsFixed(2)} MB');
    print('  Network: ${networkCondition.name}');

    // Calculate appropriate timeout based on network speed
    final timeout = _calculateTimeout(expectedSizeBytes, networkCondition);
    print('  Timeout: ${timeout.inSeconds}s');

    try {
      final fetcher = ditto.store.fetchAttachment(token);

      final attachment = await fetcher.attachment.timeout(
        timeout,
        onTimeout: () {
          print('  ⏱️ Timeout (network too slow for file size)');
          return null;
        },
      );

      if (attachment == null) {
        print('  ⚠️ Attachment not available');
        return null;
      }

      final data = attachment.getData();
      print('  ✅ Fetched: ${data.length} bytes');
      return data;

    } catch (e) {
      print('  ❌ Fetch failed: $e');
      return null;
    }
  }

  Duration _calculateTimeout(int sizeBytes, NetworkCondition condition) {
    // Estimated download speeds (bytes per second)
    final speedBytesPerSec = switch (condition) {
      NetworkCondition.wifi => 5 * 1024 * 1024, // 5 MB/s
      NetworkCondition.cellular4G => 2 * 1024 * 1024, // 2 MB/s
      NetworkCondition.cellular3G => 500 * 1024, // 500 KB/s
      NetworkCondition.p2p => 1 * 1024 * 1024, // 1 MB/s (varies widely)
      NetworkCondition.slow => 100 * 1024, // 100 KB/s
    };

    // Calculate expected time + buffer (2x for safety)
    final estimatedSeconds = (sizeBytes / speedBytesPerSec) * 2;
    final timeoutSeconds = estimatedSeconds.ceil().clamp(10, 300); // 10s - 5min

    return Duration(seconds: timeoutSeconds);
  }
}

enum NetworkCondition {
  wifi,
  cellular4G,
  cellular3G,
  p2p,
  slow,
}

// ============================================================================
// PATTERN 5: Graceful Degradation
// ============================================================================

/// ✅ GOOD: Fall back to thumbnail if full image times out
class GracefulDegradationFetcher {
  final Ditto ditto;

  GracefulDegradationFetcher(this.ditto);

  Future<ImageFetchResult> fetchImageWithFallback(String photoId) async {
    print('📥 Fetching image with graceful degradation...');

    // Query photo document
    final result = await ditto.store.execute(
      'SELECT * FROM photos WHERE _id = :photoId',
      arguments: {'photoId': photoId},
    );

    if (result.items.isEmpty) {
      return ImageFetchResult.error('Photo not found');
    }

    final doc = result.items.first.value;
    final fullImageToken = doc['fullImageToken'] as DittoAttachmentToken;
    final thumbnailToken = doc['thumbnailToken'] as DittoAttachmentToken?;

    // Try full image first
    print('  Attempting full image (30s timeout)...');
    final fullImage = await _fetchWithTimeout(
      fullImageToken,
      const Duration(seconds: 30),
    );

    if (fullImage != null) {
      print('  ✅ Full image fetched');
      return ImageFetchResult.fullImage(fullImage);
    }

    // ✅ GRACEFUL DEGRADATION: Fall back to thumbnail
    if (thumbnailToken != null) {
      print('  ⚠️ Full image timeout, falling back to thumbnail...');
      final thumbnail = await _fetchWithTimeout(
        thumbnailToken,
        const Duration(seconds: 10),
      );

      if (thumbnail != null) {
        print('  ✅ Thumbnail fetched (degraded quality)');
        return ImageFetchResult.thumbnail(thumbnail);
      }
    }

    print('  ❌ Both full image and thumbnail failed');
    return ImageFetchResult.error('Image not available');
  }

  Future<Uint8List?> _fetchWithTimeout(
    DittoAttachmentToken token,
    Duration timeout,
  ) async {
    try {
      final fetcher = ditto.store.fetchAttachment(token);
      final attachment = await fetcher.attachment.timeout(timeout);
      return attachment?.getData();
    } catch (e) {
      return null;
    }
  }
}

class ImageFetchResult {
  final Uint8List? data;
  final ImageQuality quality;
  final String? error;

  ImageFetchResult._({this.data, required this.quality, this.error});

  factory ImageFetchResult.fullImage(Uint8List data) =>
      ImageFetchResult._(data: data, quality: ImageQuality.full);

  factory ImageFetchResult.thumbnail(Uint8List data) =>
      ImageFetchResult._(data: data, quality: ImageQuality.thumbnail);

  factory ImageFetchResult.error(String message) =>
      ImageFetchResult._(quality: ImageQuality.none, error: message);

  bool get isSuccess => data != null;
  bool get isThumbnail => quality == ImageQuality.thumbnail;
}

enum ImageQuality { full, thumbnail, none }

// ============================================================================
// PATTERN 6: User-Facing Error Messages
// ============================================================================

/// ✅ GOOD: Provide helpful error messages to users
class UserFriendlyFetcher {
  final Ditto ditto;

  UserFriendlyFetcher(this.ditto);

  Future<UserFacingResult> fetchWithUserFeedback(
    DittoAttachmentToken token,
    String fileName,
    int sizeBytes,
  ) async {
    print('📥 Fetching: $fileName (${(sizeBytes / 1024 / 1024).toStringAsFixed(2)} MB)');

    try {
      final fetcher = ditto.store.fetchAttachment(token);

      final attachment = await fetcher.attachment.timeout(
        const Duration(seconds: 60),
      );

      if (attachment == null) {
        return UserFacingResult.error(
          'The file "$fileName" is not available. '
          'It may not have been uploaded yet, or may be too far away to reach.',
        );
      }

      final data = attachment.getData();
      print('  ✅ Fetched successfully');
      return UserFacingResult.success(data);

    } on TimeoutException {
      // ✅ User-friendly timeout message
      return UserFacingResult.error(
        'The file "$fileName" is taking too long to download. '
        'Please check your connection and try again.',
      );
    } catch (e) {
      // ✅ Generic error message
      return UserFacingResult.error(
        'Unable to download "$fileName". '
        'Please try again later.',
      );
    }
  }
}

class UserFacingResult {
  final Uint8List? data;
  final String? errorMessage;
  final bool isSuccess;

  UserFacingResult._({this.data, this.errorMessage, required this.isSuccess});

  factory UserFacingResult.success(Uint8List data) =>
      UserFacingResult._(data: data, isSuccess: true);

  factory UserFacingResult.error(String message) =>
      UserFacingResult._(errorMessage: message, isSuccess: false);
}

// ============================================================================
// PATTERN 7: Timeout Configuration Per File Size
// ============================================================================

/// ✅ GOOD: Dynamic timeout based on file size
class SizeBasedTimeoutFetcher {
  final Ditto ditto;

  SizeBasedTimeoutFetcher(this.ditto);

  Future<Uint8List?> fetchWithSizeBasedTimeout(
    DittoAttachmentToken token,
    int sizeBytes,
  ) async {
    final timeout = _calculateTimeoutForSize(sizeBytes);

    print('📥 Fetching ${(sizeBytes / 1024 / 1024).toStringAsFixed(2)} MB file...');
    print('  Timeout: ${timeout.inSeconds}s');

    try {
      final fetcher = ditto.store.fetchAttachment(token);

      final attachment = await fetcher.attachment.timeout(timeout);

      if (attachment == null) {
        print('  ⚠️ Attachment not available');
        return null;
      }

      final data = attachment.getData();
      print('  ✅ Fetched: ${data.length} bytes');
      return data;

    } on TimeoutException {
      print('  ⏱️ Timeout after ${timeout.inSeconds}s');
      return null;
    } catch (e) {
      print('  ❌ Fetch failed: $e');
      return null;
    }
  }

  Duration _calculateTimeoutForSize(int sizeBytes) {
    // Size-based timeout calculation
    // Assume ~1 MB/s download speed + buffer

    final sizeMB = sizeBytes / (1024 * 1024);

    if (sizeMB < 1) {
      return const Duration(seconds: 10); // Small files: 10s
    } else if (sizeMB < 10) {
      return Duration(seconds: 30 + (sizeMB * 5).toInt()); // 1-10 MB: 30-80s
    } else if (sizeMB < 100) {
      return Duration(seconds: 120 + (sizeMB * 2).toInt()); // 10-100 MB: 2-4 min
    } else {
      return const Duration(minutes: 10); // Large files: 10 min max
    }
  }
}

// ============================================================================
// Complete Example: Production-Ready Fetch with All Patterns
// ============================================================================

/// Production-ready attachment fetcher with comprehensive timeout handling
class ProductionAttachmentFetcher {
  final Ditto ditto;

  ProductionAttachmentFetcher(this.ditto);

  Future<ProductionFetchResult> fetch({
    required DittoAttachmentToken token,
    required String fileName,
    required int sizeBytes,
    NetworkCondition network = NetworkCondition.wifi,
    int maxRetries = 2,
    void Function(double progress)? onProgress,
    bool allowGracefulDegradation = false,
    DittoAttachmentToken? fallbackToken,
  }) async {
    print('📥 Production fetch: $fileName');
    print('  Size: ${(sizeBytes / 1024 / 1024).toStringAsFixed(2)} MB');
    print('  Network: ${network.name}');
    print('  Max retries: $maxRetries');

    final timeout = _calculateTimeout(sizeBytes, network);
    print('  Timeout: ${timeout.inSeconds}s');

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      print('  Attempt $attempt/$maxRetries');

      try {
        final fetcher = ditto.store.fetchAttachment(token);

        // Track progress if callback provided
        if (onProgress != null) {
          _simulateProgress(onProgress, timeout);
        }

        final attachment = await fetcher.attachment.timeout(timeout);

        if (attachment != null) {
          final data = attachment.getData();
          print('  ✅ Success: ${data.length} bytes');
          return ProductionFetchResult.success(data, isFallback: false);
        }

        print('    ⚠️ Attachment not available');

        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 2 * attempt));
        }

      } on TimeoutException {
        print('    ⏱️ Timeout after ${timeout.inSeconds}s');

        if (attempt == maxRetries && allowGracefulDegradation && fallbackToken != null) {
          print('  Attempting fallback...');
          return await _fetchFallback(fallbackToken, fileName);
        }

        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 2 * attempt));
        }

      } catch (e) {
        print('    ❌ Error: $e');

        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 2 * attempt));
        }
      }
    }

    return ProductionFetchResult.error(
      'Unable to download "$fileName" after $maxRetries attempts.',
    );
  }

  Future<ProductionFetchResult> _fetchFallback(
    DittoAttachmentToken fallbackToken,
    String fileName,
  ) async {
    try {
      final fetcher = ditto.store.fetchAttachment(fallbackToken);
      final attachment = await fetcher.attachment.timeout(
        const Duration(seconds: 15),
      );

      if (attachment != null) {
        final data = attachment.getData();
        print('  ✅ Fallback success: ${data.length} bytes');
        return ProductionFetchResult.success(data, isFallback: true);
      }
    } catch (e) {
      print('  ❌ Fallback failed: $e');
    }

    return ProductionFetchResult.error(
      'Unable to download "$fileName".',
    );
  }

  Duration _calculateTimeout(int sizeBytes, NetworkCondition network) {
    final speedBytesPerSec = switch (network) {
      NetworkCondition.wifi => 5 * 1024 * 1024,
      NetworkCondition.cellular4G => 2 * 1024 * 1024,
      NetworkCondition.cellular3G => 500 * 1024,
      NetworkCondition.p2p => 1 * 1024 * 1024,
      NetworkCondition.slow => 100 * 1024,
    };

    final estimatedSeconds = (sizeBytes / speedBytesPerSec) * 2;
    return Duration(seconds: estimatedSeconds.ceil().clamp(15, 300));
  }

  void _simulateProgress(void Function(double) onProgress, Duration timeout) {
    final startTime = DateTime.now();
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final elapsed = DateTime.now().difference(startTime);
      final progress = (elapsed.inMilliseconds / timeout.inMilliseconds).clamp(0.0, 0.99);
      onProgress(progress);

      if (elapsed >= timeout) {
        timer.cancel();
      }
    });
  }
}

class ProductionFetchResult {
  final Uint8List? data;
  final String? error;
  final bool isSuccess;
  final bool isFallback;

  ProductionFetchResult._({
    this.data,
    this.error,
    required this.isSuccess,
    this.isFallback = false,
  });

  factory ProductionFetchResult.success(Uint8List data, {required bool isFallback}) =>
      ProductionFetchResult._(data: data, isSuccess: true, isFallback: isFallback);

  factory ProductionFetchResult.error(String message) =>
      ProductionFetchResult._(error: message, isSuccess: false);
}
