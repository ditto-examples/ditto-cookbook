// Ditto SDK 5.1 (Flutter, ditto_live 5.1.0): Attachment loading anti-patterns
//
// Guide: § Fetching Attachments
//
// Every function below compiles. The problems appear at runtime.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ Treating the token as the file (subscriptions never download blobs)
// 2. ❌ Fetching every attachment as soon as documents sync (eager loading)
// 3. ❌ Starting a new fetch on every rebuild / observer update
// 4. ❌ Never stopping fetchers when the UI goes away
// 5. ❌ Awaiting fetcher.attachment after stop() (never completes)
// 6. ❌ Building attachment tokens by hand / base64 in a regular field
//
// See attachment-lazy-loading-good.dart for the correct patterns.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';

// ============================================================================
// ANTI-PATTERN 1: Treating the token as the file
// ============================================================================

/// ❌ BAD: A subscription delivers the document with its token
/// (`{id, len, metadata}`), not the bytes. This "image" is just a map.
Future<String> tokenIsNotData(Ditto ditto, String photoId) async {
  final result = await ditto.store.execute(
    'SELECT * FROM photos WHERE _id = :id',
    arguments: {'id': photoId},
  );
  final token = result.items.first.value['image'];
  return jsonEncode(token); // Not image data: call fetchAttachment instead.
}

// ============================================================================
// ANTI-PATTERN 2: Eager fetching of everything that syncs
// ============================================================================

/// ❌ BAD: Every observer update starts a fetch for every photo, including
/// photos the user never scrolls to. This downloads data the user may never
/// look at, which is costly on slow transports such as Bluetooth LE.
class EagerPhotoCache {
  EagerPhotoCache(this.ditto);

  final Ditto ditto;
  final Map<String, Uint8List> bytesById = {};
  StoreObserver? _observer;
  StreamSubscription<QueryResult>? _changes;

  void start() {
    final observer = ditto.store.registerObserver('SELECT * FROM photos');
    _observer = observer;
    _changes = observer.changes.listen((result) {
      for (final item in result.items) {
        final token = item.value['image'];
        if (token is! Map<String, dynamic>) continue;
        // A new fetch per document per update; fetchers are never kept or
        // stopped.
        ditto.store.fetchAttachment(token, (event) async {
          if (event is AttachmentFetchEventCompleted) {
            bytesById['${item.value['_id']}'] = await event.attachment.data;
          }
        });
      }
    });
  }

  void stop() {
    _changes?.cancel();
    _observer?.cancel();
  }
}

// ============================================================================
// ANTI-PATTERN 3 and 4: Fetch in build(), never stopped
// ============================================================================

/// ❌ BAD: build() runs on every rebuild, so each rebuild starts another
/// fetch for the same token. Nothing calls stop() when the widget is
/// disposed, so downloads continue after the user leaves the screen.
class FetchInBuild extends StatefulWidget {
  const FetchInBuild({super.key, required this.ditto, required this.token});

  final Ditto ditto;
  final Map<String, dynamic> token;

  @override
  State<FetchInBuild> createState() => _FetchInBuildState();
}

class _FetchInBuildState extends State<FetchInBuild> {
  Uint8List? _bytes;

  @override
  Widget build(BuildContext context) {
    widget.ditto.store.fetchAttachment(widget.token, (event) async {
      if (event is AttachmentFetchEventCompleted) {
        final bytes = await event.attachment.data;
        setState(() => _bytes = bytes); // Also crashes after dispose().
      }
    });
    final bytes = _bytes;
    return bytes == null
        ? const CircularProgressIndicator()
        : Image.memory(bytes);
  }
}

// ✅ Fix: start the fetch in initState(), keep the AttachmentFetcher, check
// `mounted`, and call stop() in dispose(). Use a stable key per document in
// lists so the same widget (and fetcher) survives observer updates.

// ============================================================================
// ANTI-PATTERN 5: Awaiting fetcher.attachment after stop()
// ============================================================================

/// ❌ BAD: A naive timeout. After stop(), `fetcher.attachment` never
/// completes, so a later `await fetcher.attachment` waits forever. Also,
/// a fixed timeout fails large downloads that are still making progress.
Future<Uint8List?> naiveTimeout(Ditto ditto, Map<String, dynamic> token) async {
  final fetcher = ditto.store.fetchAttachment(token, (_) {});
  try {
    final attachment = await fetcher.attachment.timeout(
      const Duration(seconds: 10),
    );
    return attachment?.data;
  } on TimeoutException {
    fetcher.stop();
    final attachment = await fetcher.attachment; // Never completes.
    return attachment?.data;
  }
}

// ✅ Fix: a stall timer that restarts on every progress event
// (see attachment-fetch-timeout.dart).

// ============================================================================
// ANTI-PATTERN 6: Hand-built tokens and inline base64 files
// ============================================================================

/// ❌ BAD: Two mistakes.
/// - The base64 string counts toward the document size limit (256 KiB soft,
///   5 MiB hard) and is re-sent with every change to the document.
/// - The hand-built map is not an attachment; only the `Attachment` object
///   returned by newAttachment creates one.
Future<void> inlineAndFakeToken(Ditto ditto, String photoId, Uint8List bytes) async {
  await ditto.store.execute(
    'INSERT INTO photos DOCUMENTS (:photo)',
    arguments: {
      'photo': {
        '_id': photoId,
        'imageBase64': base64Encode(bytes),
        'image': {'id': 'made-up', 'len': bytes.length, 'metadata': {}},
      },
    },
  );
}

// ✅ Fix: `await ditto.store.newAttachment(bytes, AttachmentMetadata({...}))`
// and `INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)`.
