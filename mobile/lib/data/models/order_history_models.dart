class OrderHistoryItem {
  final int id;
  final String status;
  final String paymentStatus;
  final String? posterOrderId;
  final String createdAt;

  OrderHistoryItem({
    required this.id,
    required this.status,
    required this.paymentStatus,
    this.posterOrderId,
    required this.createdAt,
  });

  factory OrderHistoryItem.fromJson(Map<String, dynamic> json) {
    return OrderHistoryItem(
      id: json['id'] as int,
      status: json['status'] as String? ?? 'pending',
      paymentStatus: json['payment_status'] as String? ?? 'unpaid',
      posterOrderId: json['poster_order_id'] as String?,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}
