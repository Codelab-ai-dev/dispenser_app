import 'package:flutter/material.dart';
import '../../data/models/dispense_record.dart';

class RecordDetailDialog extends StatelessWidget {
  final DispenseRecord record;

  const RecordDetailDialog({
    Key? key,
    required this.record,
  }) : super(key: key);

  String formatearFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    final anio = fecha.year;
    final hora = fecha.hour.toString().padLeft(2, '0');
    final minutos = fecha.minute.toString().padLeft(2, '0');
    final segundos = fecha.second.toString().padLeft(2, '0');
    
    return "$dia/$mes/$anio $hora:$minutos:$segundos";
  }

  @override
  Widget build(BuildContext context) {
    final fechaFormateada = formatearFecha(record.timestamp);
    
    return AlertDialog(
      title: Row(
        children: [
          const Text('Detalle de Registro', style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '#${record.id}',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade800),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Row(
            children: [
              const Icon(Icons.calendar_today, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Fecha y Hora: $fechaFormateada",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.water_drop, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                "Litros Acumulados: ${record.litros.toStringAsFixed(2)} L",
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.speed, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                "Flujo: ${record.flujo.toStringAsFixed(2)} L/min",
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
          if (record.tagId != null) ...[  // Solo mostrar si hay un tagId
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.nfc, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Tag RFID:",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        record.tagId!,
                        style: const TextStyle(fontSize: 16, fontFamily: "monospace"),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const Divider(),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "ID de Transacción:",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      "#${record.id}",
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Timestamp:",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      record.timestamp.toIso8601String(),
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
