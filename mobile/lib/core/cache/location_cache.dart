import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocationCache {
  static const _keyPrefix = 'delivery_location_v1';

  String _key(String scope) => '$_keyPrefix::$scope';

  Future<void> save({
    required String address,
    required double lat,
    required double lng,
    required String scope,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(scope),
      jsonEncode({'address': address, 'lat': lat, 'lng': lng}),
    );
  }

  Future<Map<String, dynamic>?> load({required String scope}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(scope));
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> clear({required String scope}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(scope));
  }
}
