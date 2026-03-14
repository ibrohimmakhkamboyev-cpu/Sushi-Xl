import 'package:dio/dio.dart';

import '../../core/cache/report_events_cache.dart';
import '../models/order_history_models.dart';
import '../models/order_detail_models.dart';

class OrderHistoryRepository {
  final Dio _dio;
  OrderHistoryRepository(this._dio);

  Future<List<OrderHistoryItem>> list(int userId) async {
    final res = await _dio.get('/order-history', queryParameters: {'user_id': userId});
    final data = res.data as List<dynamic>;
    final items = data.map((e) => OrderHistoryItem.fromJson(e as Map<String, dynamic>)).toList();
    await ReportEventsCache().appendEvent(
      module: 'orders',
      action: 'order_history_opened',
      actorType: 'user',
      actorLabel: 'user:$userId',
      target: 'user:$userId',
      details: {'count': items.length},
    );
    return items;
  }

  Future<OrderDetailResponse> detail(int orderId) async {
    final res = await _dio.get('/order-history/$orderId');
    final detail = OrderDetailResponse.fromJson(res.data as Map<String, dynamic>);
    await ReportEventsCache().appendEvent(
      module: 'orders',
      action: 'order_detail_opened',
      actorType: 'user',
      target: 'order:$orderId',
      details: {'item_count': detail.items.length},
    );
    return detail;
  }
}
