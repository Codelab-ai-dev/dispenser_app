import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/dispense_record.dart';

class LocalStorage {
  static const String _historyKey = 'historialDespachos';

  Future<List<DispenseRecord>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_historyKey);
    if (stored != null) {
      final List<dynamic> jsonList = jsonDecode(stored);
      return jsonList.map((json) => DispenseRecord.fromJson(json)).toList();
    }
    return [];
  }

  Future<void> saveRecord(DispenseRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_historyKey);
    List<Map<String, dynamic>> historyList = [];

    if (stored != null) {
      historyList = List<Map<String, dynamic>>.from(jsonDecode(stored));
    }

    historyList.add(record.toJson());
    await prefs.setString(_historyKey, jsonEncode(historyList));
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
}
