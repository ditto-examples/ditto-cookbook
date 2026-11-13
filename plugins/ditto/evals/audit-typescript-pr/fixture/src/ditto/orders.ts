import type { Ditto } from '@dittolive/ditto';

export type OrderRow = {
  _id: string;
  tableId: string;
  status: string;
  note?: string;
  createdAt: string;
};

export async function listOrders(ditto: Ditto, status: string): Promise<OrderRow[]> {
  const result = await ditto.store.execute(
    'SELECT * FROM orders WHERE status = :status AND isDeleted != true ORDER BY createdAt DESC, _id',
    { status },
  );
  return result.items.map((item) => item.value as OrderRow);
}

export async function updateNote(ditto: Ditto, orderId: string, note: string): Promise<void> {
  if (orderId === '') throw new TypeError('Missing order ID');
  await ditto.store.execute('UPDATE orders SET note = :note WHERE _id = :id', { id: orderId, note });
}

// Archived orders stay in the store but are hidden from the lists.
export async function archiveOrder(ditto: Ditto, orderId: string): Promise<void> {
  if (orderId === '') throw new TypeError('Missing order ID');
  await ditto.store.execute('UPDATE orders SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id', {
    id: orderId,
    deletedAt: new Date(),
  });
}
