import type { Ditto } from '@dittolive/ditto';
import type { OrderRow } from './orders';

// Orders of one table, for the table detail screen.
export async function ordersForTable(ditto: Ditto, tableId: string): Promise<OrderRow[]> {
  const result = await ditto.store.execute(
    `SELECT * FROM orders WHERE tableId = '${tableId}' ORDER BY createdAt DESC, _id`,
  );
  return result.items.map((item) => item.value as OrderRow);
}
