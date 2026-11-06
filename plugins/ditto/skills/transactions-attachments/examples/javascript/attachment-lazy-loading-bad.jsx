// Ditto SDK 5.2 (JavaScript, @dittolive/ditto 5.2.0, React 19): Attachment loading anti-patterns
//
// Every function below runs. The problems appear at runtime.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ Treating the token as the file (subscriptions never download blobs)
// 2. ❌ Fetching every attachment as soon as documents sync (eager loading)
// 3. ❌ Starting a new fetch on every render
// 4. ❌ Never stopping fetchers when the component goes away
// 5. ❌ A fixed timeout around `await fetcher` that leaves the fetch running
// 6. ❌ Building attachment tokens by hand / base64 in a regular field
// See attachment-lazy-loading-good.jsx for the correct patterns.
//
// Guide: § Attachments in JavaScript, § Fetching Attachments

import { useEffect, useState } from 'react';

// ❌ BAD: A subscription delivers the document with its token
// ({ id, len, metadata }), not the bytes. This "image" is just an object.
export function TokenAsImage({ photo }) {
  return <img src={String(photo.image)} alt="" />;
}

// ❌ BAD: Every observer update starts a fetch for every photo, including
// photos the user never scrolls to. This downloads data the user may never
// look at, which is costly on slow transports such as Bluetooth LE.
export function fetchEverything(ditto) {
  return ditto.store.registerObserver('SELECT * FROM COLLECTION photos (image ATTACHMENT)', (result) => {
    for (const item of result.items) {
      // A new fetch per document per update; fetchers are never kept or stopped.
      ditto.store.fetchAttachment(item.value.image, () => {});
    }
  });
}

// ❌ BAD: The fetch starts during render, so every render starts another fetch
// for the same token, and nothing stops it when the component unmounts.
export function FetchInRender({ ditto, token }) {
  const [bytes, setBytes] = useState(null);
  ditto.store.fetchAttachment(token, async (event) => {
    if (event.type === 'Completed') setBytes(await event.attachment.data());
  });
  return <span>{bytes ? `${bytes.length} bytes` : 'Loading…'}</span>;
}

// ❌ BAD: The effect starts a fetch but returns no cleanup, so the download
// continues after the user leaves the screen.
export function NeverStopped({ ditto, token }) {
  const [done, setDone] = useState(false);
  useEffect(() => {
    ditto.store.fetchAttachment(token, (event) => {
      if (event.type === 'Completed') setDone(true);
    });
  }, [ditto, token]);
  return <span>{done ? 'Done' : 'Loading…'}</span>;
}

// ❌ BAD: A naive fixed timeout. It gives up on large downloads that are
// still making progress, and it never stops the fetcher, so the download
// continues in the background.
export async function loadWithFixedTimeout(ditto, token, ms = 5000) {
  const fetcher = ditto.store.fetchAttachment(token);
  return Promise.race([fetcher.attachment, new Promise((resolve) => setTimeout(() => resolve(null), ms))]);
}
// ✅ Fix: a stall timer that restarts on every progress event and stops the
// fetcher when it fires (see attachment-fetch-timeout.js).

// ❌ BAD: Two mistakes. The base64 string counts toward the document size
// limit (256 KiB soft, 5 MiB hard) and is re-sent with every change to the
// document, and the hand-built object is not an attachment: only the object
// that newAttachment returns creates one.
export async function inlineBase64(ditto, photoId, bytes) {
  await ditto.store.execute('INSERT INTO photos DOCUMENTS (:photo)', {
    photo: {
      _id: photoId,
      imageBase64: Buffer.from(bytes).toString('base64'),
      image: { id: 'made-up', len: bytes.length, metadata: {} },
    },
  });
}
// ✅ Fix: const attachment = await ditto.store.newAttachment(bytes, { name }), then
// INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo).
