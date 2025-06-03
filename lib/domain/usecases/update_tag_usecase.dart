import '../repositories/rfid_repository.dart';
import '../../data/models/rfid_tag.dart';
import '../../data/repositories/rfid_repository_impl.dart';

class UpdateTagUseCase {
  final RfidRepository _repository;

  UpdateTagUseCase([RfidRepository? repository]) 
      : _repository = repository ?? RfidRepositoryImpl();

  Future<void> execute(RfidTag tag) async {
    await _repository.updateTag(tag);
  }
}
