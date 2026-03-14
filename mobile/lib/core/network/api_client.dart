import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ApiClient {
  ApiClient({String? baseUrl}) {
    const envBaseUrl = String.fromEnvironment('API_BASE_URL');
    final defaultBase = _defaultBaseUrl();
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? (envBaseUrl.isNotEmpty ? envBaseUrl : defaultBase),
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
  }

  late final Dio _dio;

  Dio get client => _dio;

  String _defaultBaseUrl() {
    if (kIsWeb) return '/api/v1';
    if (kReleaseMode) return 'https://api.example.com/api/v1';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8010/api/v1';
    }
    return 'http://127.0.0.1:8010/api/v1';
  }
}
