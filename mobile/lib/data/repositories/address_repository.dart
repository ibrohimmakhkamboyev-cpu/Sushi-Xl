import 'package:dio/dio.dart';

import '../../core/cache/report_events_cache.dart';
import '../models/address_models.dart';

class AddressRepository {
  final Dio _dio;
  AddressRepository(this._dio);

  Future<List<AddressModel>> listAddresses(int userId) async {
    final res = await _dio.get('/addresses', queryParameters: {'user_id': userId});
    final data = res.data as List<dynamic>;
    final items = data.map((e) => AddressModel.fromJson(e as Map<String, dynamic>)).toList();
    await ReportEventsCache().appendEvent(
      module: 'addresses',
      action: 'address_list_opened',
      actorType: 'user',
      actorLabel: 'user:$userId',
      target: 'user:$userId',
      details: {'count': items.length},
    );
    return items;
  }

  Future<AddressModel> createAddress(AddressIn address) async {
    final res = await _dio.post('/addresses', data: address.toJson());
    final created = AddressModel.fromJson(res.data as Map<String, dynamic>);
    await ReportEventsCache().appendEvent(
      module: 'addresses',
      action: 'address_created',
      actorType: 'user',
      actorLabel: 'user:${created.userId}',
      target: 'address:${created.id}',
      details: {
        'label': created.label,
        'address_line': created.addressLine,
      },
    );
    return created;
  }
}
