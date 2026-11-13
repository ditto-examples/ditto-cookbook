import React from 'react';
import { FlatList, Text } from 'react-native';
import type { Ditto } from '@dittolive/ditto';
import { useDittoQuery } from '../hooks/useDittoQuery';
import { useKitchenPrinter } from '../hooks/useKitchenPrinter';
import type { OrderRow } from '../ditto/orders';

export function KitchenScreen({ ditto, stationId }: { ditto: Ditto; stationId: string }) {
  useKitchenPrinter(ditto, stationId);
  const orders = useDittoQuery<OrderRow>(
    ditto,
    'SELECT * FROM orders WHERE stationId = :stationId AND status = :status ORDER BY createdAt, _id',
    { stationId, status: 'sent' },
  );
  if (orders === null) return <Text>Loading…</Text>;
  return (
    <FlatList
      data={orders}
      keyExtractor={(order) => order._id}
      renderItem={({ item }) => <Text>Table {item.tableId}</Text>}
    />
  );
}
