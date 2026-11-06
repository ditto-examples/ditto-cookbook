// Ditto SDK 5.2 (JavaScript, @dittolive/ditto 5.2.0, React 19): Thumbnail pattern
//
// Lists of photos should not download full-size images. Store a small
// thumbnail attachment next to the full-size one, fetch only thumbnails in
// list rows, and fetch the full-size image when the user opens the photo.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Insert a thumbnail attachment and a full-size attachment together
// 2. ✅ List rows fetch only thumbnails (lazily, one fetcher per row)
// 3. ✅ The full-size image is fetched when the user opens the photo, with a
//    longer stall timeout for the larger file
//
// Why: every device that subscribes to `photos` receives both tokens, but a
// blob is transferred only when a device fetches it.
//
// Guide: § Attachments in JavaScript, § Thumbnail Pattern

import { useEffect, useState } from 'react';

// ISO-8601 UTC timestamp with exactly millisecond precision.
export const utcTimestamp = (time = new Date()) => time.toISOString();

// PATTERN 1: Store both attachments.

// ✅ GOOD: The app downscales the image beforehand and passes the thumbnail
// bytes in (a Uint8Array). Browsers accept only bytes for newAttachment.
export async function savePhotoWithThumbnail(ditto, { photoId, thumbnailBytes, fullSize }) {
  const thumbnail = await ditto.store.newAttachment(thumbnailBytes, { kind: 'thumbnail', mimeType: 'image/jpeg' });
  // fullSize is a file path (Node.js, React Native) or a Uint8Array.
  const image = await ditto.store.newAttachment(fullSize, { kind: 'full', mimeType: 'image/jpeg' });
  await ditto.store.execute(
    'INSERT INTO COLLECTION photos (thumbnail ATTACHMENT, image ATTACHMENT) DOCUMENTS (:photo)',
    { photo: { _id: photoId, thumbnail, image, createdAt: utcTimestamp() } },
  );
}

// PATTERN 2 and 3: Thumbnails in the list, full size on demand.

// ✅ GOOD: Rows fetch only thumbnails; the full-size image is fetched when the
// row is opened. The key of the token id gives a new token a new component and
// a new fetch.
export function PhotoRow({ ditto, photo }) {
  const [open, setOpen] = useState(false);
  const thumbnail = photo.thumbnail?.id ? photo.thumbnail : null;
  const fullSize = photo.image?.id ? photo.image : null;
  return (
    <li>
      {thumbnail ? <LazyAttachmentImage key={thumbnail.id} ditto={ditto} token={thumbnail} stallTimeoutMs={30_000} /> : <span>No image</span>}
      <button type="button" disabled={!fullSize} onClick={() => setOpen(true)}>
        {photo._id}
      </button>
      {open && fullSize && (
        <dialog open>
          {/* Larger files need a longer stall timeout. */}
          <LazyAttachmentImage key={fullSize.id} ditto={ditto} token={fullSize} stallTimeoutMs={120_000} />
          <button type="button" onClick={() => setOpen(false)}>
            Close
          </button>
        </dialog>
      )}
    </li>
  );
}

// A compact lazy image: fetches when mounted, resets a stall timer on progress,
// and stops the fetcher when unmounted. See attachment-lazy-loading-good.jsx
// for a version with progress and retry.
export function LazyAttachmentImage({ ditto, token, stallTimeoutMs }) {
  const [url, setUrl] = useState(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let current = true;
    let objectUrl = null;
    let timer = null;
    const restart = () => {
      clearTimeout(timer);
      timer = setTimeout(() => {
        fetcher.stop();
        if (current) setFailed(true);
      }, stallTimeoutMs);
    };
    const fetcher = ditto.store.fetchAttachment(token, async (event) => {
      if (!current) return;
      if (event.type === 'Progress') restart();
      if (event.type === 'Completed') {
        clearTimeout(timer);
        const bytes = await event.attachment.data();
        if (!current) return;
        objectUrl = URL.createObjectURL(new Blob([bytes], { type: token.metadata?.mimeType }));
        setUrl(objectUrl);
      }
      if (event.type === 'Deleted') setFailed(true);
    });
    restart();
    return () => {
      current = false;
      clearTimeout(timer);
      fetcher.stop();
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [ditto, token, stallTimeoutMs]);

  if (url) return <img src={url} alt={token.metadata?.kind ?? ''} />;
  return <span>{failed ? 'Not available' : 'Loading…'}</span>;
}
