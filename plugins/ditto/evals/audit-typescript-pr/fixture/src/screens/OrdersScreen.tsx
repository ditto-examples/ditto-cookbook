import React from 'react';
import { Button, FlatList, Text, View } from 'react-native';
import type { Ditto } from '@dittolive/ditto';
import { useDittoQuery } from '../hooks/useDittoQuery';
import { archiveOrder, type OrderRow } from '../ditto/orders';

export function OrdersScreen({ ditto }: { ditto: Ditto }) {
  const orders = useDittoQuery<OrderRow>(
    ditto,
    'SELECT * FROM orders WHERE status = :status AND isDeleted != true ORDER BY createdAt DESC, _id',
    { status: 'open' },
  );
  if (orders === null) return <Text>Loading…</Text>;
  return (
    <FlatList
      data={orders}
      keyExtractor={(order) => order._id}
      renderItem={({ item }) => (
        <View>
          <Text>Table {item.tableId}</Text>
          {item.note ? <Text>{item.note}</Text> : null}
          <Button title="Archive" onPress={() => void archiveOrder(ditto, item._id)} />
        </View>
      )}
    />
  );
}
