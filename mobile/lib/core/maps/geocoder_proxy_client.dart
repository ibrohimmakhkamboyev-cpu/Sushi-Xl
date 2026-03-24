import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'yandex_http_geocoder.dart';

class ProxyPlace {
  final double lat;
  final double lon;
  final String placeName;
  final String formattedAddress;
  final String precision;
  final String kind;

  const ProxyPlace({
    required this.lat,
    required this.lon,
    required this.placeName,
    required this.formattedAddress,
    this.precision = '',
    this.kind = '',
  });

  String get shortLabel => placeName;
  String get fullAddress => formattedAddress;

  String combinedAddress() {
    final short = placeName.trim();
    final long = formattedAddress.trim();
    if (short.isEmpty) return long;
    if (long.isEmpty) return short;
    if (long.toLowerCase().startsWith(short.toLowerCase())) return long;
    return '$short, $long';
  }
}

class GeocoderProxyClient {
  GeocoderProxyClient({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _baseUri = _buildBaseUri(baseUrl),
        _fallbackGeocoder = YandexHttpGeocoder();

  final http.Client _client;
  final Uri? _baseUri;
  final YandexHttpGeocoder _fallbackGeocoder;

  Future<List<ProxyPlace>> geocode({
    required String text,
    String lang = 'ru_RU',
    int results = 5,
  }) async {
    final normalized = _normalizeQuery(text);
    if (normalized.isEmpty) return const [];
    final resolvedLang = _normalizeLang(lang);
    final body = await _getProxyJson(
      path: '/api/geocode',
      queryParameters: {
        'text': normalized,
        'lang': resolvedLang,
        'results': results.toString(),
      },
    );
    final proxied = _parseProxyResults(body, results: results);
    final preferredProxy = _preferUzbekistanResults(proxied, results: results);
    if (preferredProxy.isNotEmpty) return preferredProxy;

    final collected = <ProxyPlace>[];
    final seen = <String>{};
    for (final candidateLang in _languageChain(resolvedLang)) {
      for (final query in _fallbackQueries(normalized)) {
        final fallback = await _fallbackGeocoder.forward(
          query,
          maxResults: results,
          restrictToUzbekistan: true,
          lang: candidateLang,
        );
        for (final item in fallback) {
          final place = _placeFromAddress(
            lat: item.lat,
            lon: item.lng,
            address: item.address,
          );
          if (!_isUzbekistanPlace(place)) continue;
          final key = _dedupeKey(place);
          if (seen.add(key)) {
            collected.add(place);
          }
          if (collected.length >= results) {
            return collected;
          }
        }
      }
    }
    return collected;
  }

  Future<ProxyPlace?> reverse({
    required double lat,
    required double lon,
    String lang = 'ru_RU',
  }) async {
    if (!_validLatLon(lat, lon)) return null;
    final resolvedLang = _normalizeLang(lang);
    final body = await _getProxyJson(
      path: '/api/reverse',
      queryParameters: {
        'lat': lat.toString(),
        'lon': lon.toString(),
        'lang': resolvedLang,
      },
    );
    if (body is Map) {
      final parsed = _parsePlaceFromMap(body.cast<String, dynamic>());
      if (parsed != null) return parsed;
    }
    for (final candidateLang in _languageChain(resolvedLang)) {
      final fallback = await _fallbackGeocoder.reverse(
        lat,
        lon,
        maxResults: 1,
        lang: candidateLang,
      );
      if (fallback.isEmpty) continue;
      final item = fallback.first;
      return _placeFromAddress(
        lat: item.lat,
        lon: item.lng,
        address: item.address,
      );
    }
    return null;
  }

  Future<dynamic> _getProxyJson({
    required String path,
    required Map<String, String> queryParameters,
  }) async {
    final baseUri = _baseUri;
    if (baseUri == null) return null;
    final uri = baseUri.replace(
      path: _joinPath(baseUri.path, path),
      queryParameters: queryParameters,
    );
    return _getJson(uri);
  }

  Future<dynamic> _getJson(Uri uri) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _client.get(
          uri,
          headers: const {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 12));

        if (response.statusCode == 404) return const {'error': 'NOT_FOUND'};
        if (response.statusCode == 429 || response.statusCode >= 500) {
          if (attempt < 2) {
            await Future<void>.delayed(
              Duration(milliseconds: 300 * (attempt + 1)),
            );
            continue;
          }
          return null;
        }
        if (response.statusCode != 200) return null;
        return jsonDecode(response.body);
      } catch (_) {
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 300 * (attempt + 1)),
          );
          continue;
        }
        return null;
      }
    }
    return null;
  }

  ProxyPlace? _parsePlaceFromMap(Map<String, dynamic> data) {
    final lat = (data['lat'] as num?)?.toDouble();
    final lon = (data['lon'] as num?)?.toDouble();
    final placeName = '${data['shortLabel'] ?? data['placeName'] ?? ''}'.trim();
    final formattedAddress =
        '${data['fullAddress'] ?? data['formattedAddress'] ?? ''}'.trim();
    final precision = '${data['precision'] ?? ''}'.trim();
    final kind = '${data['kind'] ?? ''}'.trim();

    if (lat == null || lon == null) return null;
    if (!_validLatLon(lat, lon)) return null;
    if (placeName.isEmpty && formattedAddress.isEmpty) return null;
    return ProxyPlace(
      lat: lat,
      lon: lon,
      placeName: placeName.isEmpty ? formattedAddress : placeName,
      formattedAddress: formattedAddress.isEmpty ? placeName : formattedAddress,
      precision: precision,
      kind: kind,
    );
  }

  List<ProxyPlace> _parseProxyResults(
    dynamic body, {
    required int results,
  }) {
    if (body is! Map) return const [];
    final rows = body['results'];
    if (rows is! List) return const [];

    final out = <ProxyPlace>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final parsed = _parsePlaceFromMap(row.cast<String, dynamic>());
      if (parsed != null) out.add(parsed);
      if (out.length >= results) break;
    }
    return out;
  }

  ProxyPlace _placeFromAddress({
    required double lat,
    required double lon,
    required String address,
  }) {
    final formatted = address.trim();
    final parts = formatted
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final placeName = parts.isNotEmpty ? parts.last : formatted;
    return ProxyPlace(
      lat: lat,
      lon: lon,
      placeName: placeName.isEmpty ? formatted : placeName,
      formattedAddress: formatted,
    );
  }

  List<ProxyPlace> _preferUzbekistanResults(
    List<ProxyPlace> items, {
    required int results,
  }) {
    if (items.isEmpty) return const [];
    final seen = <String>{};
    final filtered = <ProxyPlace>[];
    for (final item in items) {
      if (!_isUzbekistanPlace(item)) continue;
      final key = _dedupeKey(item);
      if (seen.add(key)) {
        filtered.add(item);
      }
      if (filtered.length >= results) break;
    }
    return filtered;
  }

  List<String> _fallbackQueries(String normalized) {
    final out = <String>[];

    void add(String value) {
      final candidate = value.trim();
      if (candidate.isEmpty || out.contains(candidate)) return;
      out.add(candidate);
    }

    add(normalized);

    final stripped = _stripLeadingAddressType(normalized);
    if (stripped != normalized) add(stripped);

    final mentionsCountry = _queryMentionsUzbekistan(normalized);
    final mentionsCity = _queryMentionsTashkent(normalized);
    if (mentionsCountry && mentionsCity) return out;

    final seeds = List<String>.from(out);
    for (final seed in seeds) {
      if (!mentionsCity && !mentionsCountry) {
        add('$seed, Toshkent, O\'zbekiston');
        add('$seed, Tashkent, Uzbekistan');
        add('$seed, Ташкент, Узбекистан');
      } else if (!mentionsCity) {
        add('$seed, Toshkent');
        add('$seed, Tashkent');
        add('$seed, Ташкент');
      } else if (!mentionsCountry) {
        add('$seed, O\'zbekiston');
        add('$seed, Uzbekistan');
        add('$seed, Узбекистан');
      }
    }
    return out;
  }

  bool _queryMentionsUzbekistan(String query) {
    final value = query.toLowerCase();
    return value.contains('uzbek') ||
        value.contains('uzbekiston') ||
        value.contains('uzb') ||
        value.contains('o`zbek') ||
        value.contains("o'zbek") ||
        value.contains('o‘zbek') ||
        value.contains('узбек') ||
        value.contains('ўзбек');
  }

  bool _queryMentionsTashkent(String query) {
    final value = query.toLowerCase();
    return value.contains('toshkent') ||
        value.contains('tashkent') ||
        value.contains('ташкент') ||
        value.contains('тошкент');
  }

  bool _isUzbekistanPlace(ProxyPlace place) {
    if (_isWithinUzbekistanBounds(place.lat, place.lon)) return true;
    final text =
        '${place.placeName} ${place.formattedAddress}'.toLowerCase().trim();
    return text.contains('uzbekistan') ||
        text.contains('uzbekiston') ||
        text.contains('o`zbekiston') ||
        text.contains('o‘zbekiston') ||
        text.contains('узбекистан') ||
        text.contains('tashkent') ||
        text.contains('toshkent') ||
        text.contains('ташкент');
  }

  bool _isWithinUzbekistanBounds(double lat, double lon) {
    return lat >= 36.8 && lat <= 45.8 && lon >= 55.8 && lon <= 73.5;
  }

  String _dedupeKey(ProxyPlace place) {
    final lat = place.lat.toStringAsFixed(5);
    final lon = place.lon.toStringAsFixed(5);
    final address = place.formattedAddress.trim().toLowerCase();
    return '$lat|$lon|$address';
  }

  String _normalizeQuery(String text) {
    var normalized = text.trim();
    if (normalized.isEmpty) return '';
    normalized = normalized
        .replaceAll(RegExp(r"[ʻʼ‘’`´]"), "'")
        .replaceAll(RegExp(r'\s+'), ' ');
    normalized = normalized.replaceFirstMapped(
      RegExp(r'^(улица|ул\.?)(?=[A-Za-zА-Яа-яЁё0-9])', caseSensitive: false),
      (match) => '${match.group(0)} ',
    );
    normalized = normalized.replaceFirstMapped(
      RegExp(
        r"^(ko'chasi|kochasi|ko‘chasi|kuchasi)(?=[A-Za-zА-Яа-яЁё0-9])",
        caseSensitive: false,
      ),
      (match) => '${match.group(0)} ',
    );
    return normalized;
  }

  bool _validLatLon(double lat, double lon) {
    return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
  }

  String _joinPath(String basePath, String nextPath) {
    final b = basePath.trim();
    final n = nextPath.trim();
    if (b.isEmpty || b == '/') return n;
    if (b.endsWith('/')) return '${b.substring(0, b.length - 1)}$n';
    return '$b$n';
  }

  static Uri? _buildBaseUri(String? baseUrl) {
    final configured = (baseUrl ?? geocoderProxyBaseUrl).trim();
    if (configured.isNotEmpty) {
      return Uri.tryParse(configured);
    }
    if (kReleaseMode) return null;

    final fallback = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'http://10.0.2.2:8000',
      _ => 'http://127.0.0.1:8000',
    };
    return Uri.parse(fallback);
  }

  String _normalizeLang(String lang) {
    final value = lang.trim().toLowerCase();
    if (value.startsWith('uz')) return 'uz_UZ';
    if (value.startsWith('en')) return 'en_US';
    return 'ru_RU';
  }

  List<String> _languageChain(String lang) {
    final preferred = _normalizeLang(lang);
    switch (preferred) {
      case 'uz_UZ':
        return const ['uz_UZ', 'ru_RU', 'en_US'];
      case 'en_US':
        return const ['en_US', 'uz_UZ', 'ru_RU'];
      default:
        return const ['ru_RU', 'uz_UZ', 'en_US'];
    }
  }

  String _stripLeadingAddressType(String query) {
    return query
        .replaceFirst(
          RegExp(
            r"^(улица|ул\.?|street|st\.?|ko'chasi|kochasi|ko‘chasi|kuchasi)\s+",
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  void dispose() {
    _client.close();
  }
}
