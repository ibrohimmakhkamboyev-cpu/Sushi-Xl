import 'package:dio/dio.dart';

import '../config.dart';

class YandexGeocodeItem {
  final double lat;
  final double lng;
  final String address;

  const YandexGeocodeItem({
    required this.lat,
    required this.lng,
    required this.address,
  });
}

class YandexHttpGeocoder {
  YandexHttpGeocoder({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 12),
                headers: const {
                  'User-Agent': 'SushiXL/1.0 (mobile app)',
                },
              ),
            );

  final Dio _dio;

  Future<List<YandexGeocodeItem>> forward(
    String query, {
    int maxResults = 8,
    bool restrictToUzbekistan = false,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    return _request(
      geocode: normalized,
      maxResults: maxResults,
      restrictToUzbekistan: restrictToUzbekistan,
    );
  }

  Future<List<YandexGeocodeItem>> reverse(
    double lat,
    double lng, {
    int maxResults = 5,
  }) async {
    return _request(
      geocode: '$lng,$lat',
      maxResults: maxResults,
      restrictToUzbekistan: false,
    );
  }

  Future<List<YandexGeocodeItem>> _request({
    required String geocode,
    required int maxResults,
    required bool restrictToUzbekistan,
  }) async {
    final key = yandexGeocoderApiKey.trim();
    if (key.isEmpty) return const [];
    try {
      final res = await _dio.get(
        'https://geocode-maps.yandex.ru/1.x/',
        queryParameters: {
          'apikey': key,
          'geocode': geocode,
          'format': 'json',
          'results': maxResults,
          'lang': 'ru_RU',
          if (restrictToUzbekistan) 'bbox': '55.8,36.8~73.5,45.8',
          if (restrictToUzbekistan) 'rspn': 1,
        },
      );
      return _parseResponse(res.data);
    } catch (_) {
      return const [];
    }
  }

  List<YandexGeocodeItem> _parseResponse(dynamic raw) {
    if (raw is! Map) return const [];
    final response = raw['response'];
    if (response is! Map) return const [];
    final collection = response['GeoObjectCollection'];
    if (collection is! Map) return const [];
    final members = collection['featureMember'];
    if (members is! List) return const [];

    final out = <YandexGeocodeItem>[];
    for (final member in members) {
      if (member is! Map) continue;
      final geo = member['GeoObject'];
      if (geo is! Map) continue;
      final point = geo['Point'];
      if (point is! Map) continue;
      final pos = (point['pos'] as String? ?? '').trim();
      if (pos.isEmpty) continue;
      final chunks = pos.split(RegExp(r'\s+'));
      if (chunks.length != 2) continue;
      final lng = double.tryParse(chunks[0]);
      final lat = double.tryParse(chunks[1]);
      if (lat == null || lng == null) continue;
      out.add(
        YandexGeocodeItem(
          lat: lat,
          lng: lng,
          address: _extractAddress(geo),
        ),
      );
    }
    return out;
  }

  String _extractAddress(Map geo) {
    final metaProperty = geo['metaDataProperty'];
    if (metaProperty is Map) {
      final geocoderMetaData = metaProperty['GeocoderMetaData'];
      if (geocoderMetaData is Map) {
        final address = geocoderMetaData['Address'];
        if (address is Map) {
          final formatted = (address['formatted'] as String? ?? '').trim();
          if (formatted.isNotEmpty) return formatted;
        }
        final text = (geocoderMetaData['text'] as String? ?? '').trim();
        if (text.isNotEmpty) return text;
      }
    }
    final name = (geo['name'] as String? ?? '').trim();
    final description = (geo['description'] as String? ?? '').trim();
    if (name.isNotEmpty && description.isNotEmpty) return '$name, $description';
    if (name.isNotEmpty) return name;
    if (description.isNotEmpty) return description;
    return '';
  }
}
