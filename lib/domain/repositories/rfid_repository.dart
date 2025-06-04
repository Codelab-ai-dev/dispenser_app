import '../../data/models/rfid_tag.dart';

abstract class RfidRepository {
  Future<List<RfidTag>> getAllTags();
  Future<void> saveTag(RfidTag tag);
  Future<void> deleteTag(String id);
  Future<void> updateTag(RfidTag tag);
  Future<bool> isTagValid(String hexCode);
  Future<RfidTag?> getFullTagByPartialId(String partialHexCode);
}
