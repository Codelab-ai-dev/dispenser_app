import 'package:flutter_application_2/data/models/rfid_tag.dart';
import 'package:flutter_application_2/data/repositories/rfid_repository_impl.dart';
import 'package:flutter_application_2/domain/repositories/rfid_repository.dart';

class GetFullTagByPartialIdUseCase {
  final RfidRepository _repository;

  GetFullTagByPartialIdUseCase([RfidRepository? repository]) 
      : _repository = repository ?? RfidRepositoryImpl();

  Future<RfidTag?> execute(String partialHexCode) async {
    return await _repository.getFullTagByPartialId(partialHexCode);
  }
}
