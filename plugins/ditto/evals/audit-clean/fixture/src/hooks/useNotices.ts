import { useEffect, useState } from 'react';
import type { Ditto } from '@dittolive/ditto';
import { noticeFromValue, type Notice } from '../ditto/notices';

// The board's notices, newest first; one observer per component, cancelled on unmount.
export function useNotices(ditto: Ditto, boardId: string): Notice[] | null {
  const [notices, setNotices] = useState<Notice[] | null>(null);

  useEffect(() => {
    const observer = ditto.store.registerObserver(
      'SELECT * FROM notices WHERE boardId = :boardId AND coalesce(isDeleted, false) = false ORDER BY createdAt DESC, _id',
      (result) => {
        setNotices(result.items.map((item) => noticeFromValue(item.value)));
      },
      { boardId },
    );
    return () => observer.cancel();
  }, [ditto, boardId]);

  return notices;
}
