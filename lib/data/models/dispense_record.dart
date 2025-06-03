class DispenseRecord {
  final int id; // ID incremental para cada transacción
  final DateTime timestamp;
  final double litros;
  final double flujo;
  final String? tagId; // ID del tag RFID usado para el despacho

  DispenseRecord({
    required this.id,
    required this.timestamp,
    required this.litros,
    required this.flujo,
    this.tagId, // Opcional para mantener compatibilidad con registros existentes
  });

  // Convertir de JSON a objeto DispenseRecord
  factory DispenseRecord.fromJson(Map<String, dynamic> json) {
    return DispenseRecord(
      id: json['id'] ?? 0, // Si no existe, usar 0 como valor predeterminado
      timestamp: DateTime.parse(json['timestamp']),
      litros: double.parse(json['litros'].toString()),
      flujo: double.parse(json['flujo'].toString()),
      tagId: json['tagId'], // Puede ser null si no existe
    );
  }

  // Convertir de objeto DispenseRecord a JSON
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'litros': litros,
      'flujo': flujo,
    };
    
    // Solo incluir tagId si no es nulo
    if (tagId != null) {
      data['tagId'] = tagId;
    }
    
    return data;
  }
}
