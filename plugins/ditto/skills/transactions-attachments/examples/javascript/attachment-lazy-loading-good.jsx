// Ditto SDK 5.2 (JavaScript, @dittolive/ditto 5.2.0, React 19): Lazy attachment loading
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Subscriptions sync tokens only; blobs are fetched explicitly
// 2. ✅ Fetch lazily: only rows that are rendered fetch their attachment
// 3. ✅ One AttachmentFetcher per component, stopped in the effect's cleanup
// 4. ✅ Progress, completion, and deletion events
// 5. ✅ Stall timeout with a retry button (Ditto has no fetch timeout)
// 6. ✅ Show token metadata (name, size) before the download starts
//
// fetchAttachment(token, onEvent) returns an AttachmentFetcher at once. Events:
// { type: 'Progress', downloadedBytes, totalBytes } (numbers or bigints),
// { type: 'Completed', attachment } (read the bytes with await
// attachment.data()), and { type: 'Deleted' }. In a browser the bytes are shown
// through an object URL; in React Native, write them to a file with
// attachment.copyToPath() and show its file:// URI instead.
//
// Guide: § Attachments in JavaScript, § Fetching Attachments

import { useEffect, useState } from 'react';

// Returns the attachment token stored in `field`, or null if absent. A token
// is an object with id, len, and metadata.
export function attachmentToken(document, field) {
  const token = document[field];
  return token && typeof token === 'object' && typeof token.id === 'string' ? token : null;
}

// PATTERN 1: Lazy, cancellable image component.

// ✅ GOOD: Fetches its attachment only when it is mounted, restarts a stall
// timer on every progress event, offers a retry when the timer fires, and
// stops the fetcher when it unmounts or receives another token.
export function AttachmentImage({ ditto, token, stallTimeoutMs = 30_000 }) {
  const [state, setState] = useState({ url: null, progress: null, failed: false });
  const [attempt, setAttempt] = useState(0); // Incremented by the retry button.

  useEffect(() => {
    let current = true; // False after cleanup: ignore events of a replaced fetch.
    let url = null;
    let stallTimer = null;
    setState({ url: null, progress: null, failed: false });

    const fail = () => {
      fetcher.stop();
      if (current) setState((s) => ({ ...s, failed: true }));
    };
    // Ditto has no fetch timeout: no event simply means no peer is delivering the blob.
    const restartStallTimer = () => {
      clearTimeout(stallTimer);
      stallTimer = setTimeout(fail, stallTimeoutMs);
    };

    const fetcher = ditto.store.fetchAttachment(token, async (event) => {
      if (!current) return;
      if (event.type === 'Progress') {
        restartStallTimer(); // Progress resets the stall timer.
        const total = Number(event.totalBytes);
        if (total > 0) setState((s) => ({ ...s, progress: Number(event.downloadedBytes) / total }));
      } else if (event.type === 'Completed') {
        clearTimeout(stallTimer);
        try {
          const bytes = await event.attachment.data();
          if (!current) return; // The token can change while the bytes are read.
          url = URL.createObjectURL(new Blob([bytes], { type: token.metadata?.mimeType }));
          setState({ url, progress: 1, failed: false });
        } catch {
          if (current) setState((s) => ({ ...s, failed: true }));
        }
      } else if (event.type === 'Deleted') {
        clearTimeout(stallTimer);
        setState((s) => ({ ...s, failed: true }));
      }
    });
    restartStallTimer();

    return () => {
      current = false;
      clearTimeout(stallTimer);
      fetcher.stop(); // Cancel the download if the component goes away first.
      if (url) URL.revokeObjectURL(url);
    };
  }, [ditto, token.id, stallTimeoutMs, attempt]); // eslint-disable-line react-hooks/exhaustive-deps

  if (state.url) return <img src={state.url} alt={token.metadata?.name ?? ''} />;
  if (state.failed) {
    return (
      <button type="button" onClick={() => setAttempt((n) => n + 1)}>
        Retry
      </button>
    );
  }
  return <progress value={state.progress ?? undefined} max={1} />;
}

// PATTERN 2: A list that fetches only rendered rows.

// ✅ GOOD: The observer delivers documents with their tokens. Each rendered row
// mounts its own AttachmentImage, so only shown photos are fetched (render a
// window of rows, or page the list, for long collections). Metadata syncs with
// the token, so it is shown before any fetch.
export function PhotoGallery({ ditto, albumId }) {
  const [photos, setPhotos] = useState([]);

  useEffect(() => {
    const observer = ditto.store.registerObserver(
      'SELECT * FROM COLLECTION photos (image ATTACHMENT) WHERE albumId = :albumId ORDER BY createdAt DESC, _id LIMIT 50',
      (result) => setPhotos(result.items.map((item) => item.value)),
      { albumId },
    );
    return () => observer.cancel();
  }, [ditto, albumId]);

  return (
    <ul>
      {photos.map((photo) => {
        const token = attachmentToken(photo, 'image');
        return (
          // A stable key keeps one component (and one fetcher) per photo across updates.
          <li key={photo._id}>
            <span>
              {token?.metadata?.name ?? photo._id} ({Number(token?.len ?? 0)} bytes)
            </span>
            {token && <AttachmentImage key={token.id} ditto={ditto} token={token} />}
          </li>
        );
      })}
    </ul>
  );
}
