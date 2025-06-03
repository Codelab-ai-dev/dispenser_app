import 'package:flutter/material.dart';
import '../../data/models/dispense_record.dart';
import '../../domain/usecases/get_history_usecase.dart';
import '../../domain/usecases/clear_history_usecase.dart';
import '../../data/repositories/dispense_repository_impl.dart';
import 'package:go_router/go_router.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _repository = DispenseRepositoryImpl();
  late GetHistoryUseCase _getHistoryUseCase;
  late ClearHistoryUseCase _clearHistoryUseCase;
  
  List<DispenseRecord> historial = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _getHistoryUseCase = GetHistoryUseCase(_repository);
    _clearHistoryUseCase = ClearHistoryUseCase(_repository);
    _loadHistorial();
  }

  Future<void> _loadHistorial() async {
    setState(() {
      isLoading = true;
    });
    
    final records = await _getHistoryUseCase.execute();
    
    setState(() {
      historial = records;
      isLoading = false;
    });
  }

  Future<void> _clearHistory() async {
    await _clearHistoryUseCase.execute();
    _loadHistorial();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Despachos'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistorial,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : historial.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.history, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'No hay registros en el historial',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Volver al Dispensador'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${historial.length} registros',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Limpiar Historial'),
                                  content: const Text('¿Estás seguro de que deseas eliminar todos los registros del historial?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Cancelar'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _clearHistory();
                                      },
                                      child: const Text('Eliminar'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Limpiar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
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
                                  Text(_formatearFecha(item.timestamp)),
                                  if (item.tagId != null) ...[
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
                                builder: (context) => _buildDetailDialog(item),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.pop(),
        child: const Icon(Icons.arrow_back),
        tooltip: 'Volver al Dispensador',
      ),
    );
  }

  String _formatearFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    final anio = fecha.year;
    final hora = fecha.hour.toString().padLeft(2, '0');
    final minutos = fecha.minute.toString().padLeft(2, '0');
    final segundos = fecha.second.toString().padLeft(2, '0');
    
    return "$dia/$mes/$anio $hora:$minutos:$segundos";
  }

  Widget _buildDetailDialog(DispenseRecord record) {
    final fechaFormateada = _formatearFecha(record.timestamp);
    
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
