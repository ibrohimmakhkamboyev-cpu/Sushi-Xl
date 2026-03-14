import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class UserRegistryEntry {
  final String phone;
  final String name;
  final String gender;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;

  const UserRegistryEntry({
    required this.phone,
    required this.name,
    required this.gender,
    required this.firstSeenAt,
    required this.lastSeenAt,
  });

  UserRegistryEntry copyWith({
    String? phone,
    String? name,
    String? gender,
    DateTime? firstSeenAt,
    DateTime? lastSeenAt,
  }) {
    return UserRegistryEntry(
      phone: phone ?? this.phone,
      name: name ?? this.name,
      gender: gender ?? this.gender,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'phone': phone,
        'name': name,
        'gender': gender,
        'first_seen_at': firstSeenAt.toIso8601String(),
        'last_seen_at': lastSeenAt.toIso8601String(),
      };

  factory UserRegistryEntry.fromJson(Map<String, dynamic> json) => UserRegistryEntry(
        phone: json['phone'] as String? ?? '',
        name: json['name'] as String? ?? '',
        gender: json['gender'] as String? ?? 'unknown',
        firstSeenAt: DateTime.tryParse(json['first_seen_at'] as String? ?? '') ?? DateTime.now(),
        lastSeenAt: DateTime.tryParse(json['last_seen_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class UserRegistryCache {
  static const _key = 'user_registry_v1';

  Future<List<UserRegistryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return <UserRegistryEntry>[];
    final data = jsonDecode(raw) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(UserRegistryEntry.fromJson)
        .where((e) => e.phone.isNotEmpty)
        .toList();
  }

  Future<void> save(List<UserRegistryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(entries.map((e) => e.toJson()).toList());
    await prefs.setString(_key, raw);
  }

  Future<void> upsert({
    required String phone,
    required String name,
    required String gender,
    DateTime? seenAt,
  }) async {
    final normalizedPhone = phone.trim();
    if (normalizedPhone.isEmpty) return;
    final at = seenAt ?? DateTime.now();
    final entries = await load();
    final index = entries.indexWhere((e) => e.phone == normalizedPhone);
    if (index == -1) {
      entries.add(
        UserRegistryEntry(
          phone: normalizedPhone,
          name: name.trim(),
          gender: gender.trim().isEmpty ? 'unknown' : gender.trim(),
          firstSeenAt: at,
          lastSeenAt: at,
        ),
      );
    } else {
      entries[index] = entries[index].copyWith(
        name: name.trim().isEmpty ? entries[index].name : name.trim(),
        gender: gender.trim().isEmpty ? entries[index].gender : gender.trim(),
        lastSeenAt: at,
      );
    }
    await save(entries);
  }
}
