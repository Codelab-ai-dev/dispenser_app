import '../../data/models/dispense_record.dart';
import '../repositories/dispense_repository.dart';

class GetHistoryUseCase {
  final DispenseRepository _repository;

  GetHistoryUseCase(this._repository);

  Future<List<DispenseRecord>> execute() async {
    return await _repository.getHistory();
  }
}
