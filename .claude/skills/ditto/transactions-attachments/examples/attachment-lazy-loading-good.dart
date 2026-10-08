// Ditto SDK 5.1 (Flutter, ditto_live 5.1.0): Lazy attachment loading
//
// Guide: .claude/guides/best-practices/ditto.md#fetching-attachments
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Subscriptions sync tokens only; blobs are fetched explicitly
// 2. ✅ Fetch lazily: only rows that ListView.builder actually builds fetch
// 3. ✅ One AttachmentFetcher per widget, stopped in dispose()
// 4. ✅ Progress, completion, deletion, and a default branch in the switch
// 5. ✅ Stall timeout with a retry button (Ditto has no fetch timeout)
// 6. ✅ Show token metadata (name, size) before the download starts

import 'dart:async';
import 'dart:typed_data';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';

// ============================================================================
// Reading the token from a document
// ============================================================================

/// Returns the attachment token stored in [field], or null if absent.
Map<String, dynamic>? attachmentToken(Map<String, dynamic> doc, String field) {
  final token = doc[field];
  return token is Map<String, dynamic> ? token : null;
}

// ============================================================================
// PATTERN 1: Lazy, cancellable image widget
// ============================================================================

/// ✅ GOOD: Fetches its attachment only when built, and cancels the fetch
/// when it is disposed first.
class AttachmentImage extends StatefulWidget {
  const AttachmentImage({
    super.key,
    required this.ditto,
    required this.token,
    this.stallTimeout = const Duration(seconds: 30),
  });

  final Ditto ditto;

  /// The attachment token read from a document field.
  final Map<String, dynamic> token;

  /// How long to wait without any progress before giving up.
  final Duration stallTimeout;

  @override
  State<AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<AttachmentImage> {
  AttachmentFetcher? _fetcher;
  Timer? _stallTimer;
  Uint8List? _bytes;
  double? _progress;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _startFetch(); // Runs only when the widget is actually built.
  }

  void _startFetch() {
    _fetcher?.stop();
    _failed = false;
    _progress = null;
    _restartStallTimer();
    _fetcher = widget.ditto.store.fetchAttachment(widget.token, _onFetchEvent);
  }

  void _restartStallTimer() {
    _stallTimer?.cancel();
    // No event simply means no reachable peer is delivering the blob.
    _stallTimer = Timer(widget.stallTimeout, () {
      _fetcher?.stop();
      if (mounted) setState(() => _failed = true);
    });
  }

  Future<void> _onFetchEvent(AttachmentFetchEvent event) async {
    switch (event) {
      case AttachmentFetchEventProgress(:final downloadedBytes, :final totalBytes):
        _restartStallTimer(); // Progress resets the stall timer.
        if (mounted && totalBytes > 0) {
          setState(() => _progress = downloadedBytes / totalBytes);
        }
      case AttachmentFetchEventCompleted(:final attachment):
        _stallTimer?.cancel();
        try {
          final bytes = await attachment.data;
          if (mounted) setState(() => _bytes = bytes);
        } catch (error) {
          if (mounted) setState(() => _failed = true);
        }
      case AttachmentFetchEventDeleted():
        _stallTimer?.cancel();
        if (mounted) setState(() => _failed = true);
      default: // AttachmentFetchEvent is not sealed.
        break;
    }
  }

  @override
  void dispose() {
    _stallTimer?.cancel();
    _fetcher?.stop(); // Cancel the download if the widget goes away first.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover);
    if (_failed) {
      return IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: 'Retry',
        onPressed: () => setState(_startFetch),
      );
    }
    return Center(child: CircularProgressIndicator(value: _progress));
  }
}

// ============================================================================
// PATTERN 2: A list that fetches only visible rows
// ============================================================================

/// ✅ GOOD: The observer delivers documents (with tokens). Each visible row
/// creates its own AttachmentImage, so off-screen photos are never fetched.
class PhotoGallery extends StatefulWidget {
  const PhotoGallery({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<PhotoGallery> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Map<String, dynamic>> _photos = const [];

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM photos ORDER BY createdAt DESC',
    );
    _changes = _observer.changes.listen((result) {
      setState(() {
        _photos = result.items.map((item) => item.value).toList();
      });
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _photos.length,
      itemBuilder: (context, index) {
        final photo = _photos[index];
        final token = attachmentToken(photo, 'image');
        return ListTile(
          // A stable key keeps one widget (and one fetcher) per photo across
          // observer updates.
          key: ValueKey(photo['_id']),
          leading: SizedBox.square(
            dimension: 56,
            child: token == null
                ? const Icon(Icons.image_not_supported)
                : AttachmentImage(ditto: widget.ditto, token: token),
          ),
          title: Text(_displayName(token) ?? '${photo['_id']}'),
          subtitle: Text(_displaySize(token)),
        );
      },
    );
  }

  /// Metadata syncs with the token, so it is available before any fetch.
  String? _displayName(Map<String, dynamic>? token) {
    final metadata = token?['metadata'];
    return metadata is Map ? metadata['name'] as String? : null;
  }

  String _displaySize(Map<String, dynamic>? token) {
    final len = token?['len'];
    return len is int ? '${(len / 1024).toStringAsFixed(1)} KiB' : '';
  }
}
