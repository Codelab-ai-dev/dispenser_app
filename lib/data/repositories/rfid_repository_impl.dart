import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/repositories/rfid_repository.dart';
import '../models/rfid_tag.dart';
import 'package:uuid/uuid.dart';

class RfidRepositoryImpl implements RfidRepository {
  static const String _tagsKey = 'rfidTags';
  final Uuid _uuid = const Uuid();

  @override
  Future<List<RfidTag>> getAllTags() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_tagsKey);
    if (stored != null) {
      final List<dynamic> jsonList = jsonDecode(stored);
      return jsonList.map((json) => RfidTag.fromJson(json)).toList();
    }
    return [];
  }

  @override
  Future<void> saveTag(RfidTag tag) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_tagsKey);
    List<Map<String, dynamic>> tagsList = [];

    if (stored != null) {
      tagsList = List<Map<String, dynamic>>.from(jsonDecode(stored));
    }

    // Si el tag no tiene ID, generamos uno
    final tagToSave = tag.id.isEmpty 
        ? tag.copyWith(id: _uuid.v4()) 
        : tag;

    tagsList.add(tagToSave.toJson());
    await prefs.setString(_tagsKey, jsonEncode(tagsList));
  }

  @override
  Future<void> deleteTag(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_tagsKey);
    if (stored != null) {
      final List<dynamic> jsonList = jsonDecode(stored);
      final List<Map<String, dynamic>> tagsList = List<Map<String, dynamic>>.from(jsonList);
      
      tagsList.removeWhere((tag) => tag['id'] == id);
      await prefs.setString(_tagsKey, jsonEncode(tagsList));
    }
  }

  @override
  Future<void> updateTag(RfidTag tag) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_tagsKey);
    if (stored != null) {
      final List<dynamic> jsonList = jsonDecode(stored);
      final List<Map<String, dynamic>> tagsList = List<Map<String, dynamic>>.from(jsonList);
      
      final index = tagsList.indexWhere((t) => t['id'] == tag.id);
      if (index != -1) {
        tagsList[index] = tag.toJson();
        await prefs.setString(_tagsKey, jsonEncode(tagsList));
      }
    }
  }

  @override
  Future<bool> isTagValid(String hexCode) async {
    final tags = await getAllTags();
    return tags.any((tag) => 
      tag.hexCode.toLowerCase().contains(hexCode.toLowerCase()) && tag.isActive);
  }
  
  @override
  Future<RfidTag?> getFullTagByPartialId(String partialHexCode) async {
    final tags = await getAllTags();
    try {
      return tags.firstWhere(
        (tag) => tag.hexCode.toLowerCase().contains(partialHexCode.toLowerCase()) && tag.isActive
      );
    } catch (e) {
      return null;
    }
  }
}
