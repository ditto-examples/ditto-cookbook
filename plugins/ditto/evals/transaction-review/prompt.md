---
description: store.execute and a network call inside a transaction callback.
tags: [transactions-attachments, smoke]
max_turns: 12
allowed_tools: [Read, Glob, Grep, Skill]
---

Review this Flutter code that uses Ditto SDK 5.1:

```dart
Future<void> payOrder(Ditto ditto, String orderId) async {
  await ditto.store.transaction((tx) async {
    final order = await ditto.store.execute(
      'SELECT * FROM orders WHERE _id = :id', arguments: {'id': orderId});
    await http.post(Uri.parse('https://payments.example.com/charge'),
        body: {'orderId': orderId});
    await tx.execute("UPDATE orders SET status = 'paid' WHERE _id = :id",
        arguments: {'id': orderId});
  });
}
```
