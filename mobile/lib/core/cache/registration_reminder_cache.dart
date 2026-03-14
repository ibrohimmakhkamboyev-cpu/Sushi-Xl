import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class RegistrationReminderCache {
  static const _disabledKey = 'registration_reminder_disabled_v1';
  static const _nextAtKey = 'registration_reminder_next_at_ms_v1';

  Future<void> disableForever() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_disabledKey, true);
    await prefs.remove(_nextAtKey);
  }

  Future<bool> shouldShowNow() async {
    final prefs = await SharedPreferences.getInstance();
    final disabled = prefs.getBool(_disabledKey) ?? false;
    if (disabled) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    final nextAt = prefs.getInt(_nextAtKey);

    if (nextAt == null || now >= nextAt) {
      await _scheduleNext(prefs, now);
      return true;
    }
    return false;
  }

  Future<void> _scheduleNext(
      SharedPreferences prefs, int fromMillisEpoch) async {
    final minutes = 15 + Random().nextInt(6); // 15..20
    final next = DateTime.fromMillisecondsSinceEpoch(fromMillisEpoch).add(
      Duration(minutes: minutes),
    );
    await prefs.setInt(_nextAtKey, next.millisecondsSinceEpoch);
  }
}
