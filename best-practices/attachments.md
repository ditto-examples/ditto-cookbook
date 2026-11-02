# Attachments

Use attachments for binary data such as photos, signatures, PDFs, and audio. Documents themselves are limited in size (see [Document Size Limits](data-modeling.md#document-size-limits)), and every change to a document is synced to every subscriber; large binary values do not belong in documents.

## Attachment Architecture

An attachment has two parts that sync differently:

| Part | Where it lives | How it syncs |
|---|---|---|
| **Token** (`{id, len, metadata}`) | In a document field (the `ATTACHMENT` type) | Like any other document data, through subscriptions |
| **Blob** (the bytes) | In a separate blob store on each device (object storage on Ditto Server) | Only when a device explicitly **fetches** it, with a separate, resumable transfer protocol |

Key properties:

- **Subscriptions never download blobs.** A device that receives a document gets only the token. It must call `fetchAttachment` to download the bytes.
- **Content-addressed:** The attachment `id` is a cryptographic hash of the contents. Identical blobs are stored once, and several documents can reference the same blob.
- **Resumable:** If a transfer is interrupted, progress is not lost; the transfer resumes when connectivity returns or when another peer that has the blob is available.
- **Metadata** is a map of string values (file name, MIME type, dimensions) that syncs with the token, so you can show information about an attachment before fetching it.

## Creating and Inserting Attachments

Create the attachment with `ditto.store.newAttachment(pathOrBytes, [metadata])`, then store the returned `Attachment` object in a document field. Declare the field as `ATTACHMENT` in the statement:

```dart
import 'dart:typed_data';

// ✅ GOOD: Create an attachment from a file and insert it with a declared ATTACHMENT field.
Future<void> savePhoto(Ditto ditto, String photoId, String filePath) async {
  // The file is copied into Ditto's blob store; the original can be deleted afterwards.
  final Attachment attachment = await ditto.store.newAttachment(
    filePath,
    AttachmentMetadata({'name': 'receipt.jpg', 'mimeType': 'image/jpeg'}), // String values only.
  );

  await ditto.store.execute(
    'INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)',
    arguments: {
      'photo': {
        '_id': photoId,
        'image': attachment,
        'createdAt': utcTimestamp(), // Defined in the Timestamps section.
      },
    },
  );
}

// ✅ GOOD: Create an attachment from bytes (the only option on the Web).
Future<Attachment> attachmentFromBytes(Ditto ditto, Uint8List bytes, String name) {
  return ditto.store.newAttachment(bytes, AttachmentMetadata({'name': name}));
}
```

| `newAttachment` detail | Behavior |
|---|---|
| First argument | A file path (`String`) or the raw bytes (`Uint8List`) |
| File paths | The file is copied into Ditto's store. Pass an absolute path (for example, one built from `path_provider`). Not supported in web browsers (throws). |
| Metadata | Optional positional `AttachmentMetadata(Map<String, String>)`; values must be strings |
| Result | An `Attachment` with `id`, `len`, `metadata`, `data` (a `Future<Uint8List>`) and `copyToPath(destination)` (native platforms only) |

**✅ DO:**
- Declare attachment fields in the statement: `INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)`; the `COLLECTION` keyword is required when you declare types.
- Pass the `Attachment` object as part of a parameter; never build tokens by hand.
- Create the attachment **before** starting a transaction that stores it (see [Transactions](transactions.md)).

**❌ DON'T:**
- Store base64-encoded files in regular document fields; they count toward the document size limit and are re-sent with the document.
- Put non-string values into `AttachmentMetadata`.

**Why declare the type:** With the default `DQL_STRICT_MODE = false`, an attachment inserted without the declaration is still stored as an attachment. With strict mode enabled, the declaration is required: fields written as `ATTACHMENT` are not visible to queries that do not declare them, and statements that do not declare the field, including `UNSET`, leave the attachment value unchanged without an error (see [Strict Mode](data-modeling.md#strict-mode)). Declaring the type works in both modes.

## Fetching Attachments

Read the token from the document, then call `ditto.store.fetchAttachment(token, onFetchEvent)`. It returns an `AttachmentFetcher` immediately and reports progress through events:

| Event | Delivered | Contents |
|---|---|---|
| `AttachmentFetchEventProgress` | Zero or more times; a fast fetch can report none (see [Fast fetches can complete without progress events](../knowledge/observations/attachment-behavior.md#fast-fetches-can-complete-without-progress-events)) | `downloadedBytes`, `totalBytes` |
| `AttachmentFetchEventCompleted` | At most once | `attachment` (read the bytes with `await attachment.data`) |
| `AttachmentFetchEventDeleted` | At most once (instead of Completed) | The attachment was deleted while being fetched. According to the 5.2.0 release notes, a fetch of an attachment that no document references anymore now ends with this event instead of retrying forever, but we did not observe it on SDK 5.1.0 or 5.2.0: when the referencing document was deleted while no peer could deliver the blob, or after the only holder had collected the blob, the fetch stayed pending without any event. Keep a stall timeout on both releases |

| `AttachmentFetcher` member | Meaning |
|---|---|
| `stop()` | Cancels an in-flight fetch. Not required after completion; a completed fetcher stops itself. |
| `isStopped` | `true` after `stop()` or after the fetch completed |
| `attachment` | A `Future<Attachment?>` that completes with the attachment, or with an error if it was deleted. It never completes after `stop()`, so do not await it once you have stopped the fetcher. |

`AttachmentFetchEvent` is not a sealed class, so add a `default` branch to `switch` statements. `ditto.store.attachmentFetchers` lists the fetchers that are still active. Attachments that are already in the local blob store (for example, ones the device created) complete right away, typically without progress events.

```dart
import 'dart:async';
import 'dart:typed_data';

// ✅ GOOD: Lazy, cancellable attachment loading with a stall timeout.
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
  int _fetchGeneration = 0; // Identifies the current fetch.

  @override
  void initState() {
    super.initState();
    _startFetch(); // Fetch only when the widget is actually built (lazy loading).
  }

  void _startFetch() {
    _fetcher?.stop();
    _failed = false;
    _progress = null;
    _restartStallTimer();
    final generation = ++_fetchGeneration;
    _fetcher = widget.ditto.store.fetchAttachment(
      widget.token,
      (event) => _onFetchEvent(event, generation),
    );
  }

  // False for events of a replaced fetch (token change, retry) or a disposed widget.
  bool _isCurrent(int generation) => mounted && generation == _fetchGeneration;

  void _restartStallTimer() {
    _stallTimer?.cancel();
    // Ditto has no fetch timeout: no event simply means no peer is delivering the blob.
    _stallTimer = Timer(widget.stallTimeout, () {
      _fetcher?.stop();
      if (mounted) setState(() => _failed = true);
    });
  }

  Future<void> _onFetchEvent(AttachmentFetchEvent event, int generation) async {
    if (!_isCurrent(generation)) return;
    switch (event) {
      case AttachmentFetchEventProgress(:final downloadedBytes, :final totalBytes):
        _restartStallTimer(); // Progress resets the stall timer.
        if (totalBytes > 0) {
          setState(() => _progress = downloadedBytes / totalBytes);
        }
      case AttachmentFetchEventCompleted(:final attachment):
        _stallTimer?.cancel();
        try {
          final bytes = await attachment.data;
          // Check again: the token can change while the bytes are read.
          if (_isCurrent(generation)) setState(() => _bytes = bytes);
        } catch (error) {
          if (_isCurrent(generation)) setState(() => _failed = true);
        }
      case AttachmentFetchEventDeleted():
        _stallTimer?.cancel();
        setState(() => _failed = true);
      default: // AttachmentFetchEvent is not sealed.
        break;
    }
  }

  @override
  void didUpdateWidget(AttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Flutter can reuse this State for a different token (list updates, replaced photos).
    if (oldWidget.token['id'] != widget.token['id']) {
      _bytes = null;
      _startFetch();
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
```

```dart
// Reading the token from a document.
Map<String, dynamic>? imageToken(Map<String, dynamic> photo) {
  final token = photo['image'];
  return token is Map<String, dynamic> ? token : null;
}
```

**✅ DO:**
- Fetch attachments **lazily**, when the widget that shows them is built (for example, inside a row of `ListView.builder`, which only builds visible rows).
- Keep the `AttachmentFetcher` until the fetch completes, and call `stop()` when the user navigates away first.
- Implement your own timeout: restart a timer on every progress event, and stop the fetcher and offer a retry when it fires.
- Show `len` and metadata from the token (size, file name) before the download starts.

**❌ DON'T:**
- Fetch every attachment of every document as soon as it syncs; this downloads data the user may never look at.
- Start a new fetch for the same token on every rebuild or observer update; keep one fetcher per token.
- Treat a fetch that has not made progress as an error immediately; peers that have the blob may connect later.
- Start a fetch again because the connection dropped. In our testing, a fetch that lost its connection halfway stayed pending without an error and completed shortly after sync resumed, transferring only the rest (see [An interrupted fetch resumes, and identical content is not downloaded again](../knowledge/observations/attachment-behavior.md#an-interrupted-fetch-resumes-and-identical-content-is-not-downloaded-again)). Use the stall timeout for fetches that make no progress at all.

Because the attachment ID is a hash of the content, a device that already holds the same bytes does not download them again: in our testing, a later fetch of another device's attachment with the same bytes completed without any transfer (see [An interrupted fetch resumes, and identical content is not downloaded again](../knowledge/observations/attachment-behavior.md#an-interrupted-fetch-resumes-and-identical-content-is-not-downloaded-again)).

## Attachments Are Immutable

Once created, an attachment's contents never change. To "edit" a file, create a new attachment and replace the token in the document. The old blob is removed by garbage collection once no document on the device references it, on the device that replaced it and on the devices that had fetched it. In our testing with the JavaScript SDK, an `Attachment` object that the app still held in memory also kept its blob from being collected, so do not cache `Attachment` objects longer than you need them; without such objects, unreferenced blobs were collected within about 10 minutes while Ditto stayed open, and at once when the store was opened again (see [Unreferenced blobs are collected after about 10 minutes](../knowledge/observations/attachment-behavior.md#unreferenced-blobs-are-collected-after-about-10-minutes)).

Deleting a document does not remove its blob from other devices at once. In our testing, a device that still had the token fetched the attachment completely from a peer that had deleted the document but had not yet collected the blob (see [A fetch waits while no device holds the blob, and a device that deleted the document still serves it](../knowledge/observations/attachment-behavior.md#a-fetch-waits-while-no-device-holds-the-blob-and-a-device-that-deleted-the-document-still-serves-it)). Do not rely on a deletion to make a sensitive file unavailable right away.

```dart
// ✅ GOOD: Replace an attachment by creating a new one and updating the token field.
Future<void> replacePhoto(Ditto ditto, String photoId, String newFilePath) async {
  final attachment = await ditto.store.newAttachment(
    newFilePath,
    AttachmentMetadata({'name': 'receipt-v2.jpg', 'mimeType': 'image/jpeg'}),
  );
  await ditto.store.execute(
    'UPDATE COLLECTION photos (image ATTACHMENT) SET image = :image WHERE _id = :id',
    arguments: {'id': photoId, 'image': attachment},
  );
}

// ✅ GOOD: Remove the reference; the blob becomes eligible for garbage collection.
Future<void> removePhoto(Ditto ditto, String photoId) async {
  await ditto.store.execute(
    'UPDATE COLLECTION photos (image ATTACHMENT) UNSET image WHERE _id = :id',
    arguments: {'id': photoId},
  );
}
```

**Deleting and garbage collection:**
- Attachments cannot be deleted directly. Remove the token from the document (`UPDATE ... UNSET`, or set a new token), delete the document with `DELETE` (for every peer), or evict the whole document from this device with `EVICT`.
- On Small Peers, blobs that are no longer referenced are garbage-collected automatically every 10 minutes. Garbage collection runs only on Small Peers, not on Ditto Server.

## Thumbnail Pattern

Lists of photos should not download full-size images. Store a small preview next to the full-size attachment and fetch the full-size file only when the user opens it.

| Preview option | Pros | Cons |
|---|---|---|
| Small **attachment** (for example, a downscaled JPEG) | Keeps documents small; only fetched where shown | Needs an explicit fetch, like any attachment |
| Small inline value in the document (for example, a tiny base64 preview) | Arrives with the document; no fetch needed | Counts toward the document size limit (256 KiB soft limit) and is re-sent with the document; keep it very small |

```dart
import 'dart:typed_data';

// ✅ GOOD: Insert a thumbnail attachment and a full-size attachment together.
Future<void> savePhotoWithThumbnail(
  Ditto ditto, {
  required String photoId,
  required Uint8List thumbnailBytes, // Downscaled by your app beforehand.
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
        'createdAt': utcTimestamp(), // Defined in the Timestamps section.
      },
    },
  );
}
```

```dart
// ✅ GOOD: Rows fetch only thumbnails; the full-size image is fetched when opened.
class PhotoRow extends StatelessWidget {
  const PhotoRow({super.key, required this.photo, required this.attachmentImage});

  final Map<String, dynamic> photo;

  /// Builds a lazily fetched image, for example:
  /// `(token, timeout) => AttachmentImage(ditto: ditto, token: token, stallTimeout: timeout)`.
  final Widget Function(Map<String, dynamic> token, Duration stallTimeout) attachmentImage;

  @override
  Widget build(BuildContext context) {
    final thumbnail = photo['thumbnail'];
    final fullSize = photo['image'];
    return ListTile(
      leading: SizedBox.square(
        dimension: 56,
        child: thumbnail is Map<String, dynamic>
            ? attachmentImage(thumbnail, const Duration(seconds: 30))
            : const Icon(Icons.image_not_supported),
      ),
      title: Text('${photo['_id']}'),
      onTap: fullSize is Map<String, dynamic>
          ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(),
                  // Larger files need a longer stall timeout.
                  body: attachmentImage(fullSize, const Duration(minutes: 2)),
                ),
              ))
          : null,
    );
  }
}
```

**Why:** Every device that subscribes to `photos` receives both tokens, but downloads only the thumbnails that are actually displayed. Full-size blobs cross the network only for the photos users open, which matters most on slow peer-to-peer transports such as Bluetooth LE.

## Availability

An attachment can only be fetched while a peer that **holds the blob** is reachable. Documents and blobs travel separately, so a device can have a token for an attachment that no reachable peer can deliver at the moment.

- A blob exists on a device only if that device created it or fetched it. Ditto's [attachment documentation](https://docs.ditto.live/sdk/latest/crud/working-with-attachments) notes that Ditto Server can hold a document with an attachment token but not the blob, for example when Small Peers replicate the document among themselves without fetching the attachment.
- An interrupted transfer resumes from where it stopped, from the same peer or from another peer that has the blob.
- The fetch API has no "not available" event: while no peer can deliver the blob, the fetch simply makes no progress. Handle this with a timeout and a retry in the UI (see the `AttachmentImage` example).
- Do not design workflows that depend on a particular relay behavior for blobs across multiple hops; if a blob must be widely available (for example, a product image), make sure a well-connected device or Ditto Server fetches it. In our testing with three devices in a line (A–B–C), C could not fetch a blob that only A held until B had fetched the blob itself, even though B subscribed to the documents (see [Attachments relay only through devices that fetched them](../knowledge/observations/attachment-behavior.md#attachments-relay-only-through-devices-that-fetched-them)).

**✅ DO:**
- Show a placeholder with the attachment's metadata while the blob is unavailable.
- Let devices that act as hubs, or a backend connected to Ditto Server, fetch attachments that many devices will need.

**❌ DON'T:**
- Assume that receiving a document means its attachment can be downloaded right away.
- Delete the original file on the creating device before `newAttachment` has completed; after that, Ditto works from its own copy.

## Size Guidance

| Item | Guidance |
|---|---|
| Individual attachment | No fixed maximum in the SDK; practical limits are device storage and network bandwidth |
| Blob storage | Stored outside the document database; does not count toward the per-device key-value storage guidance (about 2 GB; see [Key Characteristics](../knowledge/understanding-ditto.md#key-characteristics)) |
| Uploads through the HTTP API | A separate 1 MB request body limit applies (can be raised on request) |
| Documents | 256 KiB soft limit (warning) and 5 MiB hard limit (writes that exceed it fail); see [Document Size Limits](data-modeling.md#document-size-limits) |
| Transfer progress | Reported only through fetch events; `system:data_sync_info` does not include attachments. A fast fetch can complete without any progress event, so make progress displays work without one |

**✅ DO:**
- Store images, documents, audio, and other binary files as attachments rather than inside documents.
- Compress and downscale media on the creating device before calling `newAttachment`.
- Consider the slowest transport your users rely on (Bluetooth LE is much slower than Wi-Fi) when deciding what to fetch automatically and what to fetch on demand.

**❌ DON'T:**
- Fetch large attachments automatically on devices that may only be connected over Bluetooth LE. A transfer shares the link with document sync, and other changes wait behind the data already sent: in our testing over a link limited to 1 MB/s, a 5 MB attachment delayed small documents by 1 to 3 seconds, in both directions, and at 20 KB/s, other changes waited up to 25 seconds behind a 500 KB transfer (see [A large attachment holds up documents on a slow link](../knowledge/observations/attachment-behavior.md#a-large-attachment-holds-up-documents-on-a-slow-link) and [Slow links keep the connection and the presence entry](../knowledge/observations/connections-and-presence.md#slow-links-keep-the-connection-and-the-presence-entry)). Fetch large files when the user opens them on devices that also need orders or notifications quickly.
- Keep many versions of large files alive by referencing old tokens from history documents unless you need them; every referenced blob stays on the device.
