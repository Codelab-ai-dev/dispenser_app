import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para TextInputFormatter
import 'package:flutter_application_2/data/datasources/ble_service.dart'; // Importar BleService
import 'package:flutter_application_2/data/models/dispense_record.dart'; // Importar DispenseRecord para eventType
import 'package:flutter_application_2/data/repositories/dispense_repository_impl.dart'; // Corregido
import 'package:flutter_application_2/domain/usecases/get_history_usecase.dart'; // Importar GetHistoryUseCase
import 'package:flutter_application_2/domain/usecases/save_record_usecase.dart'; // Importar SaveRecordUseCase
import 'dart:async'; // For StreamSubscription

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _pplController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final BleService _bleService = BleService.instance; // Usar instancia Singleton

  // Repositorio y UseCases para el historial
  final DispenseRepositoryImpl _repository = DispenseRepositoryImpl(); // Corregido: Inicialización directa
  late final GetHistoryUseCase _getHistoryUseCase;
  late final SaveRecordUseCase _saveRecordUseCase;
  int _lastRecordId = 0;

  // Para calibración automática
  final _autoCalLitrosController = TextEditingController();
  bool _isAutoCalibrating = false; // Estado para controlar la UI de calibración automática
  StreamSubscription<Map<String, dynamic>>? _calibrationStatusSubscription;
  StreamSubscription? _bleDataSubscription; // Para recibir datos de litros durante calibración
  double _currentLitros = 0.0; // Para mostrar litros actuales durante calibración


  @override
  void initState() {
    super.initState();
    print('[SettingsPage] initState called.');
    print('[SettingsPage] Initial BleService connection status: ${_bleService.isConnected}');
    // _repository ya está inicializado arriba
    _getHistoryUseCase = GetHistoryUseCase(_repository);
    _saveRecordUseCase = SaveRecordUseCase(_repository);
    _loadLastRecordId();
    
    // Suscribirse al stream de datos BLE para monitorear litros durante calibración
    _bleDataSubscription = _bleService.dataStream.listen(_processLitrosData);
  }

  Future<void> _loadLastRecordId() async {
    final history = await _getHistoryUseCase.execute();
    if (history.isNotEmpty) {
      setState(() {
        _lastRecordId = history.map((r) => r.id).reduce((max, current) => current > max ? current : max);
      });
    } else {
      setState(() {
        _lastRecordId = 0;
      });
    }
  }

  // Procesar datos BLE para extraer litros durante calibración
  void _processLitrosData(String data) {
    if (!_isAutoCalibrating) return; // Solo procesar datos durante calibración
    
    try {
      // Usar regex para extraer litros incluso de mensajes JSON truncados
      final litrosRegex = RegExp(r'"litros":([0-9.]+)');
      final litrosMatch = litrosRegex.firstMatch(data);
      
      if (litrosMatch != null) {
        final litrosValue = double.tryParse(litrosMatch.group(1) ?? '0.0') ?? 0.0;
        
        if (mounted) {
          setState(() {
            _currentLitros = litrosValue;
          });
        }
      }
    } catch (e) {
      print('Error al procesar datos de litros: $e');
    }
  }
  
  @override
  void dispose() {
    _pplController.dispose();
    _autoCalLitrosController.dispose(); // Dispose del nuevo controller
    _calibrationStatusSubscription?.cancel();
    _bleDataSubscription?.cancel(); // Cancelar suscripción a datos BLE
    super.dispose();
  }

  // --- Calibración Automática --- 
  Future<void> _startAutoCalibration() async {
    print('[SettingsPage] Attempting _startAutoCalibration. Current BleService connection: ${_bleService.isConnected}');
    if (!_bleService.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay ningún equipo conectado para iniciar calibración automática.'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    if (_formKey.currentState!.validate()) {
      final double? litrosRef = double.tryParse(_autoCalLitrosController.text);
      if (litrosRef != null && litrosRef > 0) {
        setState(() {
          _isAutoCalibrating = true;
        });
        try {
          await _bleService.startAutoCalibration(litrosRef);
          print('Comando Iniciar Calibración Automática enviado: $litrosRef litros');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Calibración automática iniciada. Dispense $litrosRef L y confirme.')),
            );
          }

          // Subscribe to calibration status updates
          _calibrationStatusSubscription?.cancel(); // Cancel previous one if any
          _calibrationStatusSubscription = _bleService.calibrationStatusStream.listen(_handleCalibrationStatusUpdate);

        } catch (e) {
          print('Error al iniciar calibración automática: $e');
          setState(() {
            _isAutoCalibrating = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error al iniciar calibración: $e'), backgroundColor: Colors.red),
            );
          }
        }
      }
    }
  }

  void _handleCalibrationStatusUpdate(Map<String, dynamic> event) {
    if (!mounted) return;

    setState(() {
      _isAutoCalibrating = false;
    });

    if (event['status'] == 'success') {
      final newPpl = event['new_ppl'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Calibración automática exitosa. Nuevo PPL: $newPpl')),
      );
      _autoCalLitrosController.clear();
      // Record is saved by HomePage upon receiving the BLE message.
    } else if (event['status'] == 'failure') {
      final error = event['error'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error en calibración automática: $error'), backgroundColor: Colors.red),
      );
    }

    // Clean up subscription
    _calibrationStatusSubscription?.cancel();
    _calibrationStatusSubscription = null;
  }

  Future<void> _confirmAutoCalibrationVolume() async {
    print('[SettingsPage] Attempting _confirmAutoCalibrationVolume. Current BleService connection: ${_bleService.isConnected}');
    if (!_bleService.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay ningún equipo conectado para confirmar volumen.'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    // setState(() { _isAutoCalibrating = false; }); // Se cambiará al recibir respuesta del ESP32
    try {
      await _bleService.confirmAutoCalibrationVolume();
      print('Comando Confirmar Volumen Dispensado enviado');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Confirmación enviada. Esperando resultado del ESP32...')),
        );
      }
      // Aquí se esperaría una respuesta del ESP32 con el nuevo PPL o error
    } catch (e) {
      print('Error al confirmar volumen de calibración: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al confirmar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _cancelAutoCalibration() {
    setState(() {
      _isAutoCalibrating = false;
      _autoCalLitrosController.clear();
    });
    // Enviar comando de cancelación al ESP32
    _calibrationStatusSubscription?.cancel(); // Cancel stream subscription
    _calibrationStatusSubscription = null;
    _bleService.cancelAutoCalibration().catchError((e) {
      print('Error al enviar comando de cancelar calibración: $e');
      // Opcional: Mostrar un SnackBar si falla el envío de la cancelación
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al notificar cancelación al dispositivo: $e'), backgroundColor: Colors.orange),
        );
      }
    }); 
    print('Calibración automática cancelada por el usuario.');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Calibración automática cancelada.')),
    );
  }

  Future<void> _applyManualPpl() async {
    print('[SettingsPage] Attempting _applyManualPpl. Current BleService connection: ${_bleService.isConnected}');
    if (!_bleService.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay ningún equipo conectado para aplicar PPL manual.'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    if (_formKey.currentState!.validate()) {
      final int? ppl = int.tryParse(_pplController.text);
      if (ppl != null && ppl > 0) {
        try {
          // Enviar PPL al ESP32
          await _bleService.sendPplValue(ppl);
          print('Comando PPL enviado al ESP32: $ppl');

          // Guardar en historial
          _lastRecordId++;
          final calibrationRecord = DispenseRecord(
            id: _lastRecordId,
            timestamp: DateTime.now(),
            litros: ppl.toDouble(), // Guardar el valor PPL como 'litros' para referencia
            flujo: 0.0,
            eventType: DispenseRecord.eventTypeManualCalibration,
            tagId: null,
          );
          await _saveRecordUseCase.execute(calibrationRecord);
          print('Registro de calibración manual guardado: ${calibrationRecord.toJson()}');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('PPL ($ppl) enviado y calibración registrada.')),
            );
            _pplController.clear(); // Limpiar campo después de aplicar
          }
        } catch (e) {
          print('Error al aplicar PPL manual: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error al aplicar PPL: $e'), backgroundColor: Colors.red),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Valor de PPL inválido.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración y Calibración'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: <Widget>[
              Text(
                'Calibración Manual de PPL',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _pplController,
                enabled: !_isAutoCalibrating, // Disable if auto-calibrating
                decoration: const InputDecoration(
                  labelText: 'Pulsos Por Litro (PPL)',
                  hintText: 'Ej: 450',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor ingrese un valor para PPL';
                  }
                  final int? ppl = int.tryParse(value);
                  if (ppl == null || ppl <= 0) {
                    return 'PPL debe ser un número entero positivo';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isAutoCalibrating ? null : _applyManualPpl, // Disable if auto-calibrating
                child: const Text('Aplicar PPL Manualmente'),
              ),
              const Divider(height: 40, thickness: 1),
              // Aquí irán las opciones de calibración automática
              Text(
                'Calibración Automática',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _autoCalLitrosController,
                enabled: !_isAutoCalibrating, // Disable if auto-calibrating
                decoration: const InputDecoration(
                  labelText: 'Litros de Referencia para Calibrar',
                  hintText: 'Ej: 1.0',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')) // Permitir decimales
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor ingrese los litros de referencia.';
                  }
                  final litros = double.tryParse(value);
                  if (litros == null || litros <= 0) {
                    return 'Por favor ingrese un valor positivo para los litros.';
                  }
                  return null;
                },
                readOnly: _isAutoCalibrating, // No editable durante la calibración
              ),
              const SizedBox(height: 16),
              if (!_isAutoCalibrating)
                ElevatedButton(
                  onPressed: _isAutoCalibrating ? null : _startAutoCalibration, // Disable if auto-calibrating
                  child: const Text('Iniciar Calibración Automática'),
                )
              else
                Column(
                  children: [
                    const Text('Dispensando el volumen de referencia... Una vez completado, presione confirmar.', textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _confirmAutoCalibrationVolume, // Nueva función
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      child: const Text('Confirmar Volumen Dispensado'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _cancelAutoCalibration, // Nueva función
                      child: const Text('Cancelar Calibración', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              // Podríamos añadir aquí un espacio para mostrar el PPL actual o el resultado de la calibración
            ],
          ),
        ),
      ),
    );
  }
}
