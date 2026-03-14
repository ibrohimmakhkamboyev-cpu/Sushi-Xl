import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CartCache {
  static const _baseKey = 'cart_cache_v1';

  String _keyForScope(String scope) => '$_baseKey::$scope';

  Future<void> save(Map<String, dynamic> json, {required String scope}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyForScope(scope), jsonEncode(json));
  }

  Future<Map<String, dynamic>?> load({required String scope}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyForScope(scope));
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> clear({required String scope}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyForScope(scope));
  }
}
