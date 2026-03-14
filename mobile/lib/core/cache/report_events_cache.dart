import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ReportEventsCache {
  static const _key = 'report_events_v1';
  static const _maxEvents = 300;

  Future<List<Map<String, dynamic>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final data = jsonDecode(raw) as List<dynamic>;
    return data
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> appendEvent({
    required String module,
    required String action,
    required String actorType,
    String? actorLabel,
    String? target,
    String status = 'success',
    Map<String, dynamic>? details,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await load();
    items.insert(0, {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'created_at': DateTime.now().toIso8601String(),
      'module': module,
      'action': action,
      'actor_type': actorType,
      'actor_label': actorLabel,
      'target': target,
      'status': status,
      'details': details ?? <String, dynamic>{},
    });
    if (items.length > _maxEvents) {
      items.removeRange(_maxEvents, items.length);
    }
    await prefs.setString(_key, jsonEncode(items));
  }
}
