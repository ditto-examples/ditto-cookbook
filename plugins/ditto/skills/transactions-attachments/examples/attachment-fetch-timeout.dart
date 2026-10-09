// Ditto SDK 5.1 (Flutter, ditto_live 5.1.0): Attachment fetch timeouts
//
// Guides: § Fetching Attachments
//         § Availability
//
// Ditto has no fetch timeout and no "not available" event. While no
// reachable peer can deliver the blob, the fetch simply makes no progress.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Stall timeout: restart a timer on every progress event
// 2. ✅ Stop the fetcher when the timer fires and report a retryable outcome
// 3. ✅ Never await fetcher.attachment after stop() (it never completes)
// 4. ✅ Longer stall timeouts for larger files
// 5. ✅ Retry on user request instead of failing permanently

import 'dart:async';
import 'dart:typed_data';

import 'package:ditto_live/ditto_live.dart';

// ============================================================================
// PATTERN 1-3: A fetch guarded by a stall timer
// ============================================================================

/// Outcome of a guarded fetch.
sealed class FetchOutcome {
  const FetchOutcome();
}

/// The bytes were downloaded.
final class FetchSucceeded extends FetchOutcome {
  const FetchSucceeded(this.bytes);
  final Uint8List bytes;
}

/// No progress within the stall timeout. A peer with the blob may connect
/// later, so offer a retry.
final class FetchStalled extends FetchOutcome {
  const FetchStalled();
}

/// The attachment was deleted while it was being fetched.
final class FetchDeleted extends FetchOutcome {
  const FetchDeleted();
}

/// The fetch was cancelled by the caller.
final class FetchCancelled extends FetchOutcome {
  const FetchCancelled();
}

/// ✅ GOOD: Wraps one fetch. The future returned by [start] always
/// completes, including after a stall or cancellation, because it does not
/// depend on `fetcher.attachment`.
class GuardedAttachmentFetch {
  GuardedAttachmentFetch(
    this.ditto,
    this.token, {
    this.stallTimeout = const Duration(seconds: 30),
    this.onProgress,
  });

  final Ditto ditto;
  final Map<String, dynamic> token;
  final Duration stallTimeout;
  final void Function(int downloadedBytes, int totalBytes)? onProgress;

  AttachmentFetcher? _fetcher;
  Timer? _stallTimer;
  Completer<FetchOutcome>? _outcome;

  Future<FetchOutcome> start() {
    cancel(); // At most one fetch per instance.
    final outcome = Completer<FetchOutcome>();
    _outcome = outcome;
    _restartStallTimer();
    _fetcher = ditto.store.fetchAttachment(token, (event) async {
      switch (event) {
        case AttachmentFetchEventProgress(:final downloadedBytes, :final totalBytes):
          _restartStallTimer(); // Progress resets the stall timer.
          onProgress?.call(downloadedBytes, totalBytes);
        case AttachmentFetchEventCompleted(:final attachment):
          _stallTimer?.cancel();
          try {
            _finish(FetchSucceeded(await attachment.data));
          } catch (error, stackTrace) {
            if (!outcome.isCompleted) outcome.completeError(error, stackTrace);
          }
        case AttachmentFetchEventDeleted():
          _stallTimer?.cancel();
          _finish(const FetchDeleted());
        default: // AttachmentFetchEvent is not sealed.
          break;
      }
    });
    return outcome.future;
  }

  /// Stops an in-flight fetch. Safe to call at any time.
  void cancel() {
    _stallTimer?.cancel();
    _fetcher?.stop(); // Not required after completion, but harmless.
    _finish(const FetchCancelled());
  }

  void _restartStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = Timer(stallTimeout, () {
      _fetcher?.stop();
      _finish(const FetchStalled());
    });
  }

  void _finish(FetchOutcome result) {
    final outcome = _outcome;
    if (outcome != null && !outcome.isCompleted) outcome.complete(result);
  }
}

// ============================================================================
// PATTERN 4: Stall timeout by expected size
// ============================================================================

/// ✅ GOOD: The token's `len` is known before the download starts, so larger
/// files can get a longer stall timeout. The thresholds are app decisions.
Duration stallTimeoutFor(Map<String, dynamic> token) {
  final len = token['len'];
  if (len is int && len > 5 * 1024 * 1024) return const Duration(minutes: 2);
  return const Duration(seconds: 30);
}

// ============================================================================
// PATTERN 5: Retry on user request
// ============================================================================

/// ✅ GOOD: A stalled fetch is not an error. Keep the token, show the
/// metadata, and let the user retry.
Future<Uint8List?> loadWithRetry(
  Ditto ditto,
  Map<String, dynamic> token, {
  required Future<bool> Function() askUserToRetry,
}) async {
  while (true) {
    final fetch = GuardedAttachmentFetch(
      ditto,
      token,
      stallTimeout: stallTimeoutFor(token),
    );
    switch (await fetch.start()) {
      case FetchSucceeded(:final bytes):
        return bytes;
      case FetchStalled():
        if (!await askUserToRetry()) return null;
      case FetchDeleted():
      case FetchCancelled():
        return null;
    }
  }
}
