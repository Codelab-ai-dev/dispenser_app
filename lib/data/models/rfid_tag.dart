class RfidTag {
  final String id;
  final String hexCode;
  final String description;
  final bool isActive;

  RfidTag({
    required this.id,
    required this.hexCode,
    required this.description,
    this.isActive = true,
  });

  // Convertir de JSON a objeto RfidTag
  factory RfidTag.fromJson(Map<String, dynamic> json) {
    return RfidTag(
      id: json['id'],
      hexCode: json['hexCode'],
      description: json['description'],
      isActive: json['isActive'] ?? true,
    );
  }

  // Convertir de objeto RfidTag a JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'hexCode': hexCode,
      'description': description,
      'isActive': isActive,
    };
  }

  // Crear una copia del objeto con cambios
  RfidTag copyWith({
    String? id,
    String? hexCode,
    String? description,
    bool? isActive,
  }) {
    return RfidTag(
      id: id ?? this.id,
      hexCode: hexCode ?? this.hexCode,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
    );
  }
}
