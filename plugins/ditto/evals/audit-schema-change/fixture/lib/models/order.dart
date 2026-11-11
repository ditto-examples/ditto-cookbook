enum OrderStatus { open, paid, refunded }

class Order {
  Order({
    required this.id,
    required this.storeId,
    required this.tableNumber,
    required this.status,
    required this.items,
    required this.note,
  });

  final String id;
  final String storeId;
  final int tableNumber;
  final OrderStatus status;
  final List<Map<String, dynamic>> items;
  final String note;

  factory Order.fromDocument(Map<String, dynamic> doc) => Order(
        id: doc['_id'] as String,
        storeId: doc['storeId'] as String,
        tableNumber: doc['tableNumber'] as int,
        status: OrderStatus.values.byName(doc['status'] as String),
        items: ((doc['items'] as List?) ?? const []).cast<Map<String, dynamic>>(),
        note: doc['note'] as String? ?? '',
      );
}
