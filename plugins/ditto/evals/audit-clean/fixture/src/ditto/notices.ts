import type { Ditto } from '@dittolive/ditto';
import { newId, utcTimestamp } from './ids';

export type Notice = {
  id: string;
  boardId: string;
  title: string;
  body: string;
  createdAt: string;
};

const MAX_TITLE_LENGTH = 200;
const MAX_BODY_LENGTH = 5000;

function requireText(value: string, maxLength: number, name: string): void {
  if (typeof value !== 'string' || value.trim() === '' || value.length > maxLength) {
    throw new TypeError(`Invalid ${name}`);
  }
}

// Converts a row to a plain object; fields that an older document lacks get defaults.
export function noticeFromValue(value: Record<string, unknown>): Notice {
  return {
    id: String(value._id),
    boardId: typeof value.boardId === 'string' ? value.boardId : '',
    title: typeof value.title === 'string' ? value.title : '',
    body: typeof value.body === 'string' ? value.body : '',
    createdAt: typeof value.createdAt === 'string' ? value.createdAt : '',
  };
}

export async function createNotice(ditto: Ditto, boardId: string, title: string, body: string): Promise<string> {
  requireText(boardId, 100, 'board');
  requireText(title, MAX_TITLE_LENGTH, 'title');
  requireText(body, MAX_BODY_LENGTH, 'body');
  const id = newId();
  await ditto.store.execute('INSERT INTO notices DOCUMENTS (:notice)', {
    notice: { _id: id, boardId, title, body, createdAt: utcTimestamp() },
  });
  return id;
}

// Writes only the field that the author changed.
export async function updateNoticeBody(ditto: Ditto, noticeId: string, body: string): Promise<void> {
  requireText(noticeId, 100, 'notice ID');
  requireText(body, MAX_BODY_LENGTH, 'body');
  await ditto.store.execute('UPDATE notices SET body = :body WHERE _id = :id', { id: noticeId, body });
}

// Soft delete: the flag and the time in one UPDATE, so the server's retention job can find it.
export async function archiveNotice(ditto: Ditto, noticeId: string): Promise<void> {
  requireText(noticeId, 100, 'notice ID');
  await ditto.store.execute('UPDATE notices SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id', {
    id: noticeId,
    deletedAt: utcTimestamp(),
  });
}

// The notices that the user pinned, in one query.
export async function noticesByIds(ditto: Ditto, ids: string[]): Promise<Notice[]> {
  if (ids.length === 0) return [];
  const result = await ditto.store.execute(
    'SELECT * FROM notices WHERE _id IN :ids AND coalesce(isDeleted, false) = false ORDER BY createdAt DESC, _id',
    { ids },
  );
  return result.items.map((item) => noticeFromValue(item.value));
}
