import { useEffect } from 'react';
import type { Ditto } from '@dittolive/ditto';
import { printTicket } from '../printing/printer';

// Prints a ticket for the orders that waiters send to this kitchen station.
export function useKitchenPrinter(ditto: Ditto, stationId: string): void {
  useEffect(() => {
    ditto.store.registerObserver(
      'SELECT * FROM orders WHERE stationId = :stationId AND status = :status ORDER BY createdAt, _id',
      async (result) => {
        for (const item of result.items) {
          await printTicket(item.value);
        }
      },
      { stationId, status: 'sent' },
    );
  }, [ditto, stationId]);
}
