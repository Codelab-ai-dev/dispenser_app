import '../repositories/rfid_repository.dart';
import '../../data/repositories/rfid_repository_impl.dart';

class DeleteTagUseCase {
  final RfidRepository _repository;

  DeleteTagUseCase([RfidRepository? repository]) 
      : _repository = repository ?? RfidRepositoryImpl();

  Future<void> execute(String id) async {
    await _repository.deleteTag(id);
  }
}
