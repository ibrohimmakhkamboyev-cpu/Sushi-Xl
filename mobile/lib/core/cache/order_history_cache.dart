import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class OrderHistoryCache {
  static const _baseKey = 'order_history_v1';

  String _keyForScope(String scope) => '$_baseKey::$scope';

  Future<void> save(List<Map<String, dynamic>> rows,
      {required String scope}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyForScope(scope), jsonEncode(rows));
  }

  Future<List<Map<String, dynamic>>> load({required String scope}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyForScope(scope));
    if (raw == null) return const <Map<String, dynamic>>[];
    final data = jsonDecode(raw) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<void> clear({required String scope}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyForScope(scope));
  }
}
