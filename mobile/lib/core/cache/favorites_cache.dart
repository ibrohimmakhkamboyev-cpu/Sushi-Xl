import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesCache {
  static const _keyPrefix = 'favorites_v2';

  String _key(String scope) => '$_keyPrefix::$scope';

  Future<void> save(List<int> ids, {required String scope}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(scope), jsonEncode(ids));
  }

  Future<List<int>> load({required String scope}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(scope));
    if (raw == null) return [];
    final data = jsonDecode(raw) as List<dynamic>;
    return data.map((e) => e as int).toList();
  }

  Future<void> clear({required String scope}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(scope));
  }
}
