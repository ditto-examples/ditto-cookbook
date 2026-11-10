---
type: llm
---

PASS if the report identifies all four of these problems in the files under lib/: (1) `closeOrder` treats a conditional `UPDATE ... WHERE status = 'open'` as a lock ("exactly one till takes the payment"), although two tills that have not synced with each other both change the document and both succeed; (2) `nextOrderNumber` takes the number from `COUNT(*) + 1` over the local store, so two tills produce the same order number; (3) the subscription to orders filters by `status = 'open'`, a field that changes, while the sales observer reads paid orders, so the device holds only some of the paid orders (for example orders created and paid while the till was offline) and stale copies of orders that left the subscription and the total is computed from part of the data; (4) `sendToKitchen` tells the user that the kitchen has received the order right after a local write, although the write is only in the local store.
FAIL if any of the four is missing. Other findings in the report do not matter.
