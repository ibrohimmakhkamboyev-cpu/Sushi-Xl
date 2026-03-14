class OrderItemModifierIn {
  final int modifierId;
  final double price;

  OrderItemModifierIn({required this.modifierId, required this.price});

  Map<String, dynamic> toJson() => {
        'modifier_id': modifierId,
        'price': price,
      };
}

class OrderItemIn {
  final int productId;
  final int qty;
  final double price;
  final double? oldPrice;
  final String? title;
  final String? notes;
  final List<OrderItemModifierIn> modifiers;

  OrderItemIn({
    required this.productId,
    required this.qty,
    required this.price,
    this.oldPrice,
    this.title,
    this.notes,
    required this.modifiers,
  });

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'qty': qty,
        'price': price,
        'old_price': oldPrice,
        'title': title,
        'notes': notes,
        'modifiers': modifiers.map((e) => e.toJson()).toList(),
      };
}

class CreateOrderRequest {
  final int userId;
  final List<OrderItemIn> items;
  final String deliveryType;
  final int? addressId;
  final String? scheduledAt;
  final String? notes;
  final String paymentMethod;

  CreateOrderRequest({
    required this.userId,
    required this.items,
    required this.deliveryType,
    this.addressId,
    this.scheduledAt,
    this.notes,
    required this.paymentMethod,
  });

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'items': items.map((e) => e.toJson()).toList(),
        'delivery_type': deliveryType,
        'address_id': addressId,
        'scheduled_at': scheduledAt,
        'notes': notes,
        'payment_method': paymentMethod,
      };
}

class OrderResponse {
  final int id;
  final String status;
  final String paymentStatus;
  final String? posterOrderId;

  OrderResponse({
    required this.id,
    required this.status,
    required this.paymentStatus,
    this.posterOrderId,
  });

  factory OrderResponse.fromJson(Map<String, dynamic> json) {
    return OrderResponse(
      id: json['id'] as int,
      status: json['status'] as String? ?? 'pending',
      paymentStatus: json['payment_status'] as String? ?? 'unpaid',
      posterOrderId: json['poster_order_id'] as String?,
    );
  }
}
