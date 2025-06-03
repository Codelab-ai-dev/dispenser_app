import '../repositories/dispense_repository.dart';

class ClearHistoryUseCase {
  final DispenseRepository _repository;

  ClearHistoryUseCase(this._repository);

  Future<void> execute() async {
    await _repository.clearHistory();
  }
}
