import '../../data/models/dispense_record.dart';
import '../repositories/dispense_repository.dart';

class SaveRecordUseCase {
  final DispenseRepository _repository;

  SaveRecordUseCase(this._repository);

  Future<void> execute(DispenseRecord record) async {
    await _repository.saveRecord(record);
  }
}
