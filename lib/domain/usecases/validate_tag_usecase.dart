import '../repositories/rfid_repository.dart';
import '../../data/repositories/rfid_repository_impl.dart';

class ValidateTagUseCase {
  final RfidRepository _repository;

  ValidateTagUseCase([RfidRepository? repository]) 
      : _repository = repository ?? RfidRepositoryImpl();

  Future<bool> execute(String hexCode) async {
    return await _repository.isTagValid(hexCode);
  }
}
