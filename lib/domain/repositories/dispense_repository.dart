import '../../data/models/dispense_record.dart';

abstract class DispenseRepository {
  Future<List<DispenseRecord>> getHistory();
  Future<void> saveRecord(DispenseRecord record);
  Future<void> clearHistory();
}
