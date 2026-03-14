class OrderDetailItem {
  final int productId;
  final int qty;
  final double price;
  final List<OrderDetailModifier> modifiers;

  OrderDetailItem({
    required this.productId,
    required this.qty,
    required this.price,
    required this.modifiers,
  });

  factory OrderDetailItem.fromJson(Map<String, dynamic> json) {
    final mods = (json['modifiers'] as List<dynamic>? ?? [])
        .map((e) => OrderDetailModifier.fromJson(e as Map<String, dynamic>))
        .toList();
    return OrderDetailItem(
      productId: json['product_id'] as int,
      qty: json['qty'] as int,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      modifiers: mods,
    );
  }
}

class OrderDetailModifier {
  final int modifierId;
  final double price;

  OrderDetailModifier({required this.modifierId, required this.price});

  factory OrderDetailModifier.fromJson(Map<String, dynamic> json) {
    return OrderDetailModifier(
      modifierId: json['modifier_id'] as int,
      price: (json['price'] as num?)?.toDouble() ?? 0,
    );
  }
}

class OrderDetailResponse {
  final int id;
  final List<OrderDetailItem> items;

  OrderDetailResponse({required this.id, required this.items});

  factory OrderDetailResponse.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? [])
        .map((e) => OrderDetailItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return OrderDetailResponse(id: json['id'] as int, items: items);
  }
}
