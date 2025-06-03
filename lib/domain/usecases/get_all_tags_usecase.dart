import '../repositories/rfid_repository.dart';
import '../../data/models/rfid_tag.dart';
import '../../data/repositories/rfid_repository_impl.dart';

class GetAllTagsUseCase {
  final RfidRepository _repository;

  GetAllTagsUseCase([RfidRepository? repository]) 
      : _repository = repository ?? RfidRepositoryImpl();

  Future<List<RfidTag>> execute() async {
    return await _repository.getAllTags();
  }
}
