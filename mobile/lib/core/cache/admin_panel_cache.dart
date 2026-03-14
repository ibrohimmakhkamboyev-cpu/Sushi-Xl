import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AdminPanelCache {
  static const _menuOverrideKey = 'admin_menu_override_v1';
  static const _adsKey = 'admin_ads_override_v1';
  static const _supportConfigKey = 'admin_support_config_v1';
  static const _supportInboxKey = 'admin_support_inbox_v1';

  Future<void> saveMenuOverride(Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_menuOverrideKey, jsonEncode(json));
  }

  Future<Map<String, dynamic>?> loadMenuOverride() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_menuOverrideKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> clearMenuOverride() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_menuOverrideKey);
  }

  Future<void> saveAds(List<Map<String, dynamic>> ads) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_adsKey, jsonEncode(ads));
  }

  Future<List<Map<String, dynamic>>> loadAds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_adsKey);
    if (raw == null) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<void> saveSupportConfig(Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_supportConfigKey, jsonEncode(json));
  }

  Future<Map<String, dynamic>?> loadSupportConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_supportConfigKey);
    if (raw == null) return null;
    return (jsonDecode(raw) as Map).cast<String, dynamic>();
  }

  Future<void> saveSupportInbox(Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_supportInboxKey, jsonEncode(json));
  }

  Future<Map<String, dynamic>?> loadSupportInbox() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_supportInboxKey);
    if (raw == null) return null;
    return (jsonDecode(raw) as Map).cast<String, dynamic>();
  }
}
