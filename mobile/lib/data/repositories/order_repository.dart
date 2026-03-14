import 'package:dio/dio.dart';

import '../../core/cache/report_events_cache.dart';
import '../models/order_models.dart';

class OrderRepository {
  final Dio _dio;
  OrderRepository(this._dio);

  Future<OrderResponse> createOrder(CreateOrderRequest request) async {
    final res = await _dio.post('/orders', data: request.toJson());
    final created = OrderResponse.fromJson(res.data as Map<String, dynamic>);
    await ReportEventsCache().appendEvent(
      module: 'orders',
      action: 'order_created',
      actorType: 'user',
      actorLabel: 'user:${request.userId}',
      target: 'order:${created.id}',
      details: {
        'delivery_type': request.deliveryType,
        'payment_method': request.paymentMethod,
        'item_count': request.items.length,
        'status': created.status,
        'payment_status': created.paymentStatus,
      },
    );
    return created;
  }

  Future<OrderResponse> getOrder(int id) async {
    final res = await _dio.get('/orders/$id');
    final order = OrderResponse.fromJson(res.data as Map<String, dynamic>);
    await ReportEventsCache().appendEvent(
      module: 'orders',
      action: 'order_status_viewed',
      actorType: 'user',
      target: 'order:${order.id}',
      details: {
        'status': order.status,
        'payment_status': order.paymentStatus,
      },
    );
    return order;
  }
}
