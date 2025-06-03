import '../../domain/repositories/dispense_repository.dart';
import '../datasources/local_storage.dart';
import '../models/dispense_record.dart';

class DispenseRepositoryImpl implements DispenseRepository {
  final LocalStorage _localStorage = LocalStorage();

  @override
  Future<List<DispenseRecord>> getHistory() async {
    return await _localStorage.getHistory();
  }

  @override
  Future<void> saveRecord(DispenseRecord record) async {
    await _localStorage.saveRecord(record);
  }

  @override
  Future<void> clearHistory() async {
    await _localStorage.clearHistory();
  }
}
