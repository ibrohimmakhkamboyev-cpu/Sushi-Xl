import 'package:dio/dio.dart';

import '../../core/cache/report_events_cache.dart';
import '../models/user_models.dart';

class AuthRepository {
  final Dio _dio;
  AuthRepository(this._dio);

  Future<OtpRequestResponse> requestLoginCode({
    required String phone,
    required String fullName,
    String? preferredLang,
  }) async {
    final res = await _dio.post(
      '/auth/request-code',
      data: {
        'phone': phone,
        'full_name': fullName,
        'preferred_lang': preferredLang,
      },
      options: Options(
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    return OtpRequestResponse.fromJson(res.data as Map<String, dynamic>);
  }

  Future<LoginResponse> verifyLoginCode({
    required String phone,
    required String code,
    required String fullName,
    String? preferredLang,
  }) async {
    final res = await _dio.post(
      '/auth/verify-code',
      data: {
        'phone': phone,
        'code': code,
        'full_name': fullName,
        'preferred_lang': preferredLang,
      },
      options: Options(
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    final response = LoginResponse.fromJson(res.data as Map<String, dynamic>);
    await ReportEventsCache().appendEvent(
      module: 'auth',
      action: 'user_login_otp',
      actorType: 'user',
      actorLabel: response.phone,
      target: 'user:${response.userId}',
      details: {
        'full_name': response.fullName,
        'preferred_lang': response.preferredLang,
      },
    );
    return response;
  }

  Future<LoginResponse> login({required String phone, required String fullName, String? preferredLang}) async {
    final res = await _dio.post(
      '/auth/login',
      data: {
        'phone': phone,
        'full_name': fullName,
        'preferred_lang': preferredLang,
      },
      options: Options(sendTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 10)),
    );
    final response = LoginResponse.fromJson(res.data as Map<String, dynamic>);
    await ReportEventsCache().appendEvent(
      module: 'auth',
      action: 'user_login',
      actorType: 'user',
      actorLabel: response.phone,
      target: 'user:${response.userId}',
      details: {
        'full_name': response.fullName,
        'preferred_lang': response.preferredLang,
      },
    );
    return response;
  }

  Future<LoginResponse> updateProfile({
    required String phone,
    required String fullName,
    String? preferredLang,
  }) async {
    final res = await _dio.put(
      '/users/me',
      data: {
        'phone': phone,
        'full_name': fullName,
        'preferred_lang': preferredLang,
      },
      options: Options(
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    return LoginResponse.fromJson(res.data as Map<String, dynamic>);
  }
}
