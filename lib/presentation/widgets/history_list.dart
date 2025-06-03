import 'package:flutter/material.dart';
import '../../data/models/dispense_record.dart';
import 'record_detail_dialog.dart';

class HistoryList extends StatelessWidget {
  final List<DispenseRecord> historial;
  final VoidCallback onClearHistory;

  const HistoryList({
    Key? key,
    required this.historial,
    required this.onClearHistory,
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Historial de Despachos",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (historial.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: onClearHistory,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text("Limpiar"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: historial.isEmpty
              ? const Center(
                  child: Text(
                    "No hay registros en el historial",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: historial.length,
                  itemBuilder: (context, index) {
                    final item = historial[historial.length - 1 - index]; // Mostrar más reciente primero
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: Text(
                            "#${item.id}",
                            style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Row(
                          children: [
                            const Icon(Icons.water_drop, color: Colors.blue, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              "${item.litros.toStringAsFixed(2)} L @ ${item.flujo.toStringAsFixed(2)} L/min",
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            Text(formatearFecha(item.timestamp)),
                            if (item.tagId != null) ...[  // Solo mostrar si hay un tagId
                              const SizedBox(width: 8),
                              const Icon(Icons.nfc, size: 12, color: Colors.green),
                              const SizedBox(width: 2),
                              Text(
                                item.tagId!.toUpperCase(),
                                style: const TextStyle(fontSize: 10, color: Colors.green, fontFamily: "monospace"),
                              ),
                            ],
                          ],
                        ),
                        trailing: const Icon(Icons.info_outline),
                        onTap: () => showDialog(
                          context: context,
                          builder: (context) => RecordDetailDialog(record: item),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
