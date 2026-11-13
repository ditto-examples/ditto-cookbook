import React from 'react';
import { Button, FlatList, Text, View } from 'react-native';
import type { Ditto } from '@dittolive/ditto';
import { archiveNotice } from '../ditto/notices';
import { useNotices } from '../hooks/useNotices';

export function NoticesScreen({ ditto, boardId, onError }: { ditto: Ditto; boardId: string; onError: (error: unknown) => void }) {
  const notices = useNotices(ditto, boardId);
  if (notices === null) return <Text>Loading…</Text>;
  return (
    <FlatList
      data={notices}
      keyExtractor={(notice) => notice.id}
      renderItem={({ item }) => (
        <View>
          <Text>{item.title}</Text>
          <Text>{item.body}</Text>
          <Button title="Archive" onPress={() => archiveNotice(ditto, item.id).catch(onError)} />
        </View>
      )}
    />
  );
}
