// Ditto SDK 5.1 (Flutter, ditto_live 5.1.0): Thumbnail pattern
//
// Guide: .claude/guides/best-practices/ditto.md#thumbnail-pattern
//
// Lists of photos should not download full-size images. Store a small
// preview next to the full-size attachment and fetch the full-size file only
// when the user opens it.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Insert a thumbnail attachment and a full-size attachment together
// 2. ✅ List rows fetch only thumbnails (lazily, one fetcher per row)
// 3. ✅ The full-size image is fetched when the user opens the photo,
//       with a longer stall timeout
//
// Why: every device that subscribes to `photos` receives both tokens, but
// downloads only the thumbnails that are actually displayed. Full-size blobs
// cross the network only for the photos users open, which matters most on
// slow peer-to-peer transports such as Bluetooth LE.
//
// Preview options:
// - Small attachment (this file): keeps documents small; needs a fetch.
// - Tiny inline value (for example, base64): arrives with the document but
//   counts toward the 256 KiB soft limit and is re-sent with the document.

import 'dart:async';
import 'dart:typed_data';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';

// ============================================================================
// PATTERN 1: Store both attachments
// ============================================================================

/// ✅ GOOD: The app downscales the image beforehand (for example, with an
/// image-processing package) and passes the thumbnail bytes in.
Future<void> savePhotoWithThumbnail(
  Ditto ditto, {
  required String photoId,
  required Uint8List thumbnailBytes,
  required String fullSizePath,
}) async {
  final thumbnail = await ditto.store.newAttachment(
    thumbnailBytes,
    AttachmentMetadata({'kind': 'thumbnail', 'mimeType': 'image/jpeg'}),
  );
  final fullSize = await ditto.store.newAttachment(
    fullSizePath,
    AttachmentMetadata({'kind': 'full', 'mimeType': 'image/jpeg'}),
  );

  await ditto.store.execute(
    'INSERT INTO COLLECTION photos (thumbnail ATTACHMENT, image ATTACHMENT) DOCUMENTS (:photo)',
    arguments: {
      'photo': {
        '_id': photoId,
        'thumbnail': thumbnail,
        'image': fullSize,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    },
  );
}

// ============================================================================
// PATTERN 2 and 3: Thumbnails in the list, full size on demand
// ============================================================================

/// ✅ GOOD: Rows fetch only thumbnails; the full-size image is fetched when
/// the row is opened.
class PhotoRow extends StatelessWidget {
  const PhotoRow({super.key, required this.ditto, required this.photo});

  final Ditto ditto;
  final Map<String, dynamic> photo;

  @override
  Widget build(BuildContext context) {
    final thumbnail = photo['thumbnail'];
    final fullSize = photo['image'];
    return ListTile(
      leading: SizedBox.square(
        dimension: 56,
        child: thumbnail is Map<String, dynamic>
            ? LazyAttachmentImage(
                key: ValueKey(thumbnail['id']),
                ditto: ditto,
                token: thumbnail,
              )
            : const Icon(Icons.image_not_supported),
      ),
      title: Text('${photo['_id']}'),
      onTap: fullSize is Map<String, dynamic>
          ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(),
                    // Larger files need a longer stall timeout.
                    body: LazyAttachmentImage(
                      key: ValueKey(fullSize['id']),
                      ditto: ditto,
                      token: fullSize,
                      stallTimeout: const Duration(minutes: 2),
                    ),
                  ),
                ),
              )
          : null,
    );
  }
}

/// A compact lazy image: fetches in initState, resets a stall timer on
/// progress, and stops the fetcher in dispose. Callers give it a
/// ValueKey of the token id, so a new token creates a new State and a new
/// fetch instead of reusing the old one. See
/// attachment-lazy-loading-good.dart for a version with progress and retry.
class LazyAttachmentImage extends StatefulWidget {
  const LazyAttachmentImage({
    super.key,
    required this.ditto,
    required this.token,
    this.stallTimeout = const Duration(seconds: 30),
  });

  final Ditto ditto;
  final Map<String, dynamic> token;
  final Duration stallTimeout;

  @override
  State<LazyAttachmentImage> createState() => _LazyAttachmentImageState();
}

class _LazyAttachmentImageState extends State<LazyAttachmentImage> {
  AttachmentFetcher? _fetcher;
  Timer? _stallTimer;
  Uint8List? _bytes;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _restartStallTimer();
    _fetcher = widget.ditto.store.fetchAttachment(widget.token, (event) async {
      switch (event) {
        case AttachmentFetchEventProgress():
          _restartStallTimer();
        case AttachmentFetchEventCompleted(:final attachment):
          _stallTimer?.cancel();
          final bytes = await attachment.data;
          if (mounted) setState(() => _bytes = bytes);
        case AttachmentFetchEventDeleted():
          _stallTimer?.cancel();
          if (mounted) setState(() => _unavailable = true);
        default: // AttachmentFetchEvent is not sealed.
          break;
      }
    });
  }

  void _restartStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = Timer(widget.stallTimeout, () {
      _fetcher?.stop();
      if (mounted) setState(() => _unavailable = true);
    });
  }

  @override
  void dispose() {
    _stallTimer?.cancel();
    _fetcher?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover);
    if (_unavailable) return const Icon(Icons.cloud_off);
    return const Center(child: CircularProgressIndicator());
  }
}
