import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/crypto_service.dart';

class LocalStore {
  static const _queueKey = 'freewave.encrypted_queue';
  static const _contactsKey = 'freewave.trusted_contacts';
  static const _displayNameKey = 'freewave.display_name';
  static const _seenIdsKey = 'freewave.seen_message_ids';

  Future<List<Map<String, dynamic>>> loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = prefs.getStringList(_queueKey) ?? [];
    return rows.map((row) => Map<String, dynamic>.from(jsonDecode(row) as Map)).toList();
  }

  Future<void> saveQueue(List<Map<String, dynamic>> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_queueKey, queue.map(jsonEncode).toList());
  }

  Future<List<TrustedContact>> loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_contactsKey) ?? [];
    return raw.map((e) => TrustedContact.fromJson(jsonDecode(e) as Map<String, dynamic>)).toList();
  }

  Future<void> saveContacts(List<TrustedContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_contactsKey, contacts.map((c) => jsonEncode(c.toJson())).toList());
  }


  Future<Set<String>> loadSeenIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_seenIdsKey) ?? []).toSet();
  }

  Future<void> saveSeenIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final values = ids.toList();
    if (values.length > 2000) {
      values.removeRange(0, values.length - 2000);
    }
    await prefs.setStringList(_seenIdsKey, values);
  }

  Future<String> loadDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_displayNameKey) ?? 'FreeWave user';
  }

  Future<void> saveDisplayName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, name);
  }
}
