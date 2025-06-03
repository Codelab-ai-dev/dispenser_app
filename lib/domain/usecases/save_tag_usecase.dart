import '../repositories/rfid_repository.dart';
import '../../data/models/rfid_tag.dart';
import '../../data/repositories/rfid_repository_impl.dart';

class SaveTagUseCase {
  final RfidRepository _repository;

  SaveTagUseCase([RfidRepository? repository]) 
      : _repository = repository ?? RfidRepositoryImpl();

  Future<void> execute(RfidTag tag) async {
    await _repository.saveTag(tag);
  }
}
