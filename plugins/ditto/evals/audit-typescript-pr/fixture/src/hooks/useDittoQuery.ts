import { useEffect, useState } from 'react';
import type { Ditto } from '@dittolive/ditto';

// One observer per component; plain rows in state; cancelled on unmount.
export function useDittoQuery<T>(ditto: Ditto, query: string, args: Record<string, unknown> = {}): T[] | null {
  const argsKey = JSON.stringify(args);
  const [rows, setRows] = useState<T[] | null>(null);

  useEffect(() => {
    const observer = ditto.store.registerObserver(
      query,
      (result) => setRows(result.items.map((item) => item.value as T)),
      JSON.parse(argsKey),
    );
    return () => observer.cancel();
  }, [ditto, query, argsKey]);

  return rows;
}
