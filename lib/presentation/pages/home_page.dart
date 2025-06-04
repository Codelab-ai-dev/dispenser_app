import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../../data/datasources/ble_service.dart';
import '../../data/models/dispense_record.dart';
import '../../data/repositories/dispense_repository_impl.dart';
import '../../domain/usecases/get_history_usecase.dart';
import '../../domain/usecases/save_record_usecase.dart';
import '../../domain/usecases/validate_tag_usecase.dart';
import '../../domain/usecases/get_full_tag_by_partial_id_usecase.dart';
import '../pages/rfid_management_page.dart';
import '../widgets/device_list.dart';
import '../widgets/dispense_display.dart';
import 'package:go_router/go_router.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final BleService _bleService = BleService.instance;
  final DispenseRepositoryImpl _repository = DispenseRepositoryImpl();
  late GetHistoryUseCase _getHistoryUseCase;
  late SaveRecordUseCase _saveRecordUseCase;
  late ValidateTagUseCase _validateTagUseCase;
  late GetFullTagByPartialIdUseCase _getFullTagByPartialIdUseCase;

  List<DiscoveredDevice> devices = [];
  List<DispenseRecord> historial = [];
  double litros = 0.0;
  double flujo = 0.0;
  String receivedData = "";
  bool _ignorarProximasLecturas = false;
  String? lastValidatedTagId; // Último tag RFID validado
  int lastRecordId = 0; // Último ID de registro usado
  double? presetLitros; // Preset de litros configurado
  bool presetActivo = false; // Indica si hay un preset activo
  String rfidValidationMessage = 'Acerca un tag RFID para autorizar.'; // Mensaje de estado RFID

  @override
  void initState() {
    super.initState();
    _getHistoryUseCase = GetHistoryUseCase(_repository);
    _saveRecordUseCase = SaveRecordUseCase(_repository);
    _validateTagUseCase = ValidateTagUseCase();
    _getFullTagByPartialIdUseCase = GetFullTagByPartialIdUseCase();

    _loadHistorial();
    _bleService.requestPermissions();

    // Suscribirse a cambios en el estado de conexión BLE
    _bleService.connectionStatusStream.listen((connected) {
      if (mounted) {
        setState(() {});

        if (!connected && _bleService.connectedDevice != null) {
          // Mostrar mensaje de reconexión
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Conexión BLE perdida. Intentando reconectar...'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        } else if (connected) {
          // Mostrar mensaje de conexión exitosa
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Conexión BLE establecida'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  Future<void> _loadHistorial() async {
    final records = await _getHistoryUseCase.execute();
    setState(() {
      historial = records;

      // Encontrar el último ID utilizado para continuar la secuencia
      if (records.isNotEmpty) {
        // Buscar el ID más alto en los registros existentes
        int maxId = 0;
        for (final record in records) {
          if (record.id > maxId) {
            maxId = record.id;
          }
        }
        lastRecordId = maxId;
        // print('🔢 Último ID de registro cargado: $lastRecordId');
      }
    });
  }

  void startScan() {
    setState(() => devices = []);
    _bleService.scanForDevices().listen((device) {
      setState(() {
        if (!devices.any((d) => d.id == device.id)) {
          devices.add(device);
        }
      });
    });
  }

  // Helper method to safely parse numeric values
  double _parseNumeric(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) {
      if (value.isInfinite || value.isNaN) {
        // print("⚠️ _parseNumeric: num isInfinite or isNaN: $value");
        return 0.0;
      }
      return value.toDouble();
    }
    if (value is String) {
      String cleanedValue = value.trim().toLowerCase();
      if (cleanedValue == 'inf' || cleanedValue == 'infinity' || cleanedValue == '-inf' || cleanedValue == '-infinity' || cleanedValue == 'nan') {
        // print("⚠️ _parseNumeric: String represents infinity or NaN: $value");
        return 0.0; 
      }
      double? parsed = double.tryParse(cleanedValue);
      if (parsed == null || parsed.isInfinite || parsed.isNaN) {
        // print("⚠️ _parseNumeric: double.tryParse failed or result isInfinite/isNaN for: $cleanedValue (original: $value)");
        return 0.0;
      }
      return parsed;
    }
    // print("⚠️ _parseNumeric: Unhandled type for value: $value, type: ${value.runtimeType}");
    return 0.0;
  }

  // Helper method to robustly extract RFID UIDs
  String? _extractUidRobustly(String rawData) {
  print("[DEBUG HomePage] _extractUidRobustly received rawData: '$rawData'");
    if (rawData.isEmpty) return null;
    // Prioritize JSON-like structures first
    final RegExp jsonUidRegex = RegExp(
      r'"(?:uid|tag_id|rfid|rfid_tag|tagId|verify_uid|card_id|cardId)"\s*:\s*"([0-9A-Fa-f\s]+)"',
      caseSensitive: false,
    );
    var match = jsonUidRegex.firstMatch(rawData);
    if (match != null && match.groupCount >= 1) {
      String? potentialUid = match.group(1)?.replaceAll(' ', '').toUpperCase();
      // Basic validation for UID length (e.g., 4 to 20 hex characters)
      if (potentialUid != null && potentialUid.isNotEmpty && potentialUid.length >= 4 && potentialUid.length <= 20) {
        print("[DEBUG HomePage] _extractUidRobustly (JSON pattern) returning: '$potentialUid'");
        return potentialUid;
      }
    }

    // Broader regex for UIDs that might be prefixed or just hex strings
    final RegExp generalUidRegex = RegExp(
      r'(?:UID:|TAG:|ID:|RFID:)?\s*([0-9A-Fa-f]{2}(?:\s*[0-9A-Fa-f]{2}){1,9}|[0-9A-Fa-f]{4,20})(?![0-9A-Fa-f])',
      caseSensitive: false,
    );
    match = generalUidRegex.firstMatch(rawData);
    if (match != null && match.groupCount >= 1) {
      String? potentialUid = match.group(1)?.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase(); 
      if (potentialUid != null && potentialUid.isNotEmpty && potentialUid.length >= 4 && potentialUid.length <= 20) {
        if (RegExp(r'^[0-9A-Fa-f]+$').hasMatch(potentialUid)) {
            print("[DEBUG HomePage] _extractUidRobustly (General pattern) returning: '$potentialUid'");
          return potentialUid;
        }
      }
    }
    
    String trimmedData = rawData.trim();
    if (RegExp(r'^[0-9A-Fa-f\s]+$').hasMatch(trimmedData)) { 
        String potentialUid = trimmedData.replaceAll(' ', '').toUpperCase();
        if (potentialUid.isNotEmpty && potentialUid.length >= 4 && potentialUid.length <= 20) {
             print("[DEBUG HomePage] _extractUidRobustly (Simple hex fallback) returning: '$potentialUid'");
          return potentialUid;
        }
    }

    print("[DEBUG HomePage] _extractUidRobustly returning null for rawData: '$rawData'");
  return null;
  }

  void connectToDevice(DiscoveredDevice device) async {
    final connected = await _bleService.connectToDevice(device);

    if (connected) {
      setState(() {});

      _bleService.subscribeToCharacteristic().listen((data) {
        final jsonString = String.fromCharCodes(data);
        print("🔵 BLE recibido: $jsonString");
        
        // Procesar mensajes de reset_success para confirmar reset
        if (jsonString.contains('"message":"reset_success"') || 
            jsonString.contains('"reset_counter":true') || 
            jsonString.contains('"force_reset":true') || 
            jsonString.contains('"verify_reset":true')) {
          print("Recibido mensaje de reset, confirmando reset");
          if (mounted) {
            setState(() {
              _ignorarProximasLecturas = false;
              litros = 0.0;
              flujo = 0.0;
              receivedData = "L: 0.00, F: 0.00";
            });
          }
        }
        
        // Si estamos ignorando lecturas, no procesar datos de litros/flujo
        if (_ignorarProximasLecturas) {
          print("Ignorando actualización de litros/flujo debido a _ignorarProximasLecturas=true");
          return;
        }
        
        // Extraer datos de litros y flujo usando expresiones regulares
        // Esta es una solución más robusta para mensajes truncados
        final litrosRegex = RegExp(r'"litros":([0-9.]+)');
        final flujoRegex = RegExp(r'"flujo":([0-9.]+)');
        
        final litrosMatch = litrosRegex.firstMatch(jsonString);
        final flujoMatch = flujoRegex.firstMatch(jsonString);
        
        if (litrosMatch != null) {
          final litrosValue = double.tryParse(litrosMatch.group(1) ?? '0.0') ?? 0.0;
          print("Litros encontrados: $litrosValue");
          
          // Actualizar UI con los litros encontrados
          if (mounted) {
            setState(() {
              litros = litrosValue;
              receivedData = "L: ${litros.toStringAsFixed(2)}";
              
              // Si también tenemos flujo, actualizar eso también
              if (flujoMatch != null) {
                flujo = double.tryParse(flujoMatch.group(1) ?? '0.0') ?? 0.0;
                receivedData += ", F: ${flujo.toStringAsFixed(2)}";
              }
            });
          }
          
          // Verificar si se alcanzó el preset
          if (presetActivo && presetLitros != null && litros >= presetLitros!) {
            _bleService.sendData('{"stop_dispense":true}');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Preset de $presetLitros L alcanzado.')),
              );
            }
            _guardarEnHistorial();
            _cancelarPreset();
          }
          
          return; // Procesamiento exitoso
        }
        
        // Si no encontramos litros, intentamos procesar como JSON normal
        dynamic jsonData;
        try {
          jsonData = jsonDecode(jsonString);
          // JSON válido
        } catch (e) {
          // El JSON no es válido, intentar extraer UID directamente
          String? uidFromFailedJson = _extractUidRobustly(jsonString); 
          if (uidFromFailedJson != null) {
            print("UID extraído de mensaje: $uidFromFailedJson");
            _validateRfidTag(uidFromFailedJson);
            return;
          }
          
          // Si no podemos procesar el mensaje, simplemente lo ignoramos
          return;
        }

        // JSON decodificado exitosamente. Ahora jsonData es un Map<String, dynamic> o List.
        if (jsonData is Map<String, dynamic>) {
          // 1. Verificar mensajes de control específicos que vienen como JSON
          if (jsonData.containsKey('message')) {
            final message = jsonData['message'];
            if (message == 'RFID_validated') {
              // print("✅ Mensaje de validación RFID recibido y procesado.");
              if (mounted) {
                setState(() {
                  receivedData = "Tag RFID Validado"; 
                  rfidValidationMessage = 'Tag RFID validado. Puede dispensar.';
                });
              }
              return; 
            } else if (message == 'RFID_invalid') {
              // print("❌ Mensaje de RFID inválido recibido.");
              if (mounted) {
                setState(() {
                  rfidValidationMessage = 'Tag RFID no reconocido o inválido.';
                });
              }
              return; 
            } else if (message == 'reset_success') {
              // print("🔄 Reset del contador confirmado por ESP32.");
              if (mounted) {
                setState(() {
                  litros = 0.0;
                  flujo = 0.0;
                  receivedData = 'Contador reseteado en ESP32.';
                  rfidValidationMessage = 'Contador reseteado. Acerque tag para nueva autorización.';
                  lastValidatedTagId = null; 
                });
              }
              _ignorarProximasLecturas = false; 
              return; 
            }
          }

          // 2. Verificar mensajes de calibración
          if (jsonData.containsKey('calibration_complete') && jsonData['calibration_complete'] == true) {
            final newPpl = jsonData['new_ppl'];
            _bleService.reportCalibrationSuccess(newPpl is int ? newPpl : (newPpl as num?)?.toInt() ?? 0);
            // print('🎉 Calibración automática completada. Nuevo PPL: $newPpl');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Calibración automática exitosa. Nuevo PPL: $newPpl')),
              );
            }
            _saveAutoCalibrationRecord(newPpl?.toDouble() ?? 0.0);
            return; 
          } else if (jsonData.containsKey('calibration_failed')) {
            final errorMsg = jsonData['error'] ?? 'Error desconocido.';
            _bleService.reportCalibrationFailure(errorMsg);
            // print('💀 Error en calibración automática desde ESP32: $errorMsg');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error en calibración desde ESP32: $errorMsg'), backgroundColor: Colors.red),
              );
            }
            return; 
          }

          // 3. Verificar si el JSON contiene un UID para validar
          String? uidFromVerifiedJson;
          if (jsonData.containsKey('verify_uid') && jsonData['verify_uid'] is String) {
            uidFromVerifiedJson = jsonData['verify_uid'];
          } else if (jsonData.containsKey('tag_id') && jsonData['tag_id'] is String) {
            uidFromVerifiedJson = jsonData['tag_id'];
          } else if (jsonData.containsKey('uid') && jsonData['uid'] is String) {
            uidFromVerifiedJson = jsonData['uid'];
          }

          if (uidFromVerifiedJson != null) {
            // print("🔑 UID extraído de JSON verificado: $uidFromVerifiedJson");
            _validateRfidTag(uidFromVerifiedJson);
            return; // Mensaje RFID procesado
          }

          // 4. Procesar datos de dispensación (litros, flujo)
          if (jsonData.containsKey('litros') && jsonData.containsKey('flujo')) {
            if (_ignorarProximasLecturas) {
              // print("🚫 Ignorando lectura post-reset para evitar doble guardado.");
              if(mounted) setState(() => receivedData = "Ignorando: $jsonString");
              return;
            }

            double parsedLitros = _parseNumeric(jsonData['litros']);
            double parsedFlujo = _parseNumeric(jsonData['flujo']);

            if (parsedLitros.isInfinite || parsedLitros.isNaN || parsedFlujo.isInfinite || parsedFlujo.isNaN) {
              // print("🚫 Valores infinitos o NaN en JSON: L=${jsonData['litros']}, F=${jsonData['flujo']}. Original: $jsonString");
              if (mounted) {
                setState(() {
                  litros = 0.0;
                  flujo = 0.0;
                  receivedData = "Error: Datos numéricos inválidos del sensor.";
                });
              }
              return;
            }

            if (mounted) {
              setState(() {
                litros = parsedLitros;
                flujo = parsedFlujo;
                receivedData = "L: ${litros.toStringAsFixed(2)}, F: ${flujo.toStringAsFixed(2)}";
              });
            }

            // Lógica de preset
            if (presetActivo && presetLitros != null && litros >= presetLitros!) {
              _bleService.sendData('{"stop_dispense":true}');
              // print("🛑 Preset alcanzado ($presetLitros L), enviando comando de parada.");
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Preset de $presetLitros L alcanzado.')),
                );
              }
              _guardarEnHistorial(); 
              _cancelarPreset(); 
            }
            return; // Datos de dispensación procesados
          }
          
          // Si el JSON es un Map pero no coincide con ninguna estructura conocida
          // print("ℹ️ JSON (Map) recibido y decodificado, pero no coincide con formatos esperados: $jsonData");
          if(mounted) setState(() => receivedData = "Datos desconocidos (Map): $jsonString");

        } else {
          // Si el JSON decodificado no es un Map (podría ser una List u otro tipo primitivo)
          // print("ℹ️ JSON decodificado no es un Map: $jsonData. Original: $jsonString");
          if(mounted) setState(() => receivedData = "Formato inesperado (no Map): $jsonString");
        }
      }); // End of _bleService.subscribeToCharacteristic().listen
    } // End of if (connected)
  } // End of connectToDevice method

  Future<void> _guardarEnHistorial() async {
  // Primero detener la dispensación y resetear el contador
  try {
    // Enviar comando de reset que coincide con el código del ESP32
    await _bleService.sendData('{"reset_counter":true}');
    print("📤 Comando de reset enviado");
    // Pequeña pausa para asegurar que el comando de reset se procese
    await Future.delayed(const Duration(milliseconds: 500));
  } catch (e) {
    print("❌ Error al enviar comando de reset: $e");
  }

  // Incrementar el ID para la nueva transacción
  lastRecordId++;

  // Crear un registro incluyendo el tagId si está disponible
  final record = DispenseRecord(
    id: lastRecordId,
    timestamp: DateTime.now(),
    litros: litros,
    flujo: flujo,
    tagId: lastValidatedTagId, // Incluir el último tag validado
    eventType: DispenseRecord.eventTypeDispense, // Especificar tipo de evento
  );

  _saveRecordUseCase.execute(record);

  setState(() {
    historial.add(record);
    _ignorarProximasLecturas = true;
    
    // Limpiar el preset después de guardar
    presetActivo = false;
    presetLitros = null;
    
    // Resetear el contador a cero
    litros = 0.0;
    flujo = 0.0;
    receivedData = "L: 0.00, F: 0.00";
    
    // Resetear el tag validado para solicitar uno nuevo
    lastValidatedTagId = null;
    rfidValidationMessage = 'Acerque un tag RFID para comenzar';
  });
  
  // Después de un breve periodo, permitir nuevas lecturas
  Future.delayed(const Duration(seconds: 1), () {
    if (mounted) {
      setState(() {
        _ignorarProximasLecturas = false;
        print("Habilitando nuevas lecturas después del reset");
      });
    }
  });

  // Ya enviamos el comando de reset, solo mostrar mensaje
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Registro guardado. Acerque un nuevo tag RFID para continuar.'),
        backgroundColor: Colors.blue,
      ),
    );
  }
  }

  Future<void> _saveAutoCalibrationRecord(double newPplValue) async {
    // Aquí asumimos que 'newPplValue' es el valor que queremos registrar como 'litros'
    // o alguna otra representación del resultado de la calibración.
    // Si necesitamos los litros de referencia originales, se requeriría un manejo de estado más complejo
    // para pasarlos desde SettingsPage hasta aquí.
    lastRecordId++;
    final record = DispenseRecord(
      id: lastRecordId,
      timestamp: DateTime.now(),
      litros: newPplValue, // Guardando el nuevo PPL en el campo litros como referencia
      flujo: 0.0, 
      eventType: DispenseRecord.eventTypeAutoCalibration,
      tagId: null, // Opcional: se podría usar para el valor de litros de referencia si no es muy largo
    );
    await _saveRecordUseCase.execute(record);
    // print('💾 Registro de calibración automática guardado: ${record.toJson()}');
    _loadHistorial(); // Recargar para mostrar el nuevo registro
  }

  Future<void> _resetCounter({String? showMessage}) async {
    if (!_bleService.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No conectado al dispositivo BLE para reiniciar.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (lastValidatedTagId == null) {
        if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
            content: Text('Se requiere autorización RFID para reiniciar el contador.'),
            backgroundColor: Colors.orange,
            ),
        );
        }
        // print("ℹ️ Solicitando autorización RFID para resetear contador.");
        return;
    }

    try {
      await _bleService.sendData('{"reset_counter":true}');
      // print("🔄 Comando de reset enviado al ESP32.");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(showMessage ?? 'Comando de reinicio enviado al dispositivo.'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      // print("❌ Error al enviar comando de reset: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al reiniciar contador: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _validateRfidTag(String tagId) async {
    print("[DEBUG HomePage] _validateRfidTag received tagId: '$tagId'");
    // Clean the tag ID by removing all non-hexadecimal characters (not just spaces)
    final cleanTagId = tagId.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    print("[DEBUG HomePage] _validateRfidTag cleanTagId after replaceAll: '$cleanTagId'");
    if (_ignorarProximasLecturas) {
      // print("🚫 Validación de tag ignorada debido a _ignorarProximasLecturas = true");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Validación de tag ignorada temporalmente.'),
            backgroundColor: Colors.grey,
          ),
        );
      }
      return;
    }

    // print("🔑 Validando tag RFID internamente: $cleanTagId");
    if (mounted) {
      setState(() {
        rfidValidationMessage = 'Validando tag: ${cleanTagId.toUpperCase()}...';
      });
    }

    try {
      final isValid = await _validateTagUseCase.execute(cleanTagId);
      // print("✅ Resultado de validación para $cleanTagId: $isValid");
      
      // Si el tag es válido, intentamos obtener el tag completo de la base de datos
      String fullTagId = cleanTagId;
      if (isValid) {
        final fullTag = await _getFullTagByPartialIdUseCase.execute(cleanTagId);
        if (fullTag != null) {
          fullTagId = fullTag.hexCode;
          print("[DEBUG HomePage] Found full tag ID: '${fullTag.hexCode}' for partial ID: '$cleanTagId'");
        }
      }

      if (mounted) {
        setState(() {
          if (isValid) {
            lastValidatedTagId = fullTagId; // Guardar el ID completo
            rfidValidationMessage = 'Tag RFID autorizado: ${fullTagId.toUpperCase()}';
          } else {
            rfidValidationMessage = 'Tag RFID NO autorizado: ${cleanTagId.toUpperCase()}';
          }
        });
      }

      // Enviar el ID completo al ESP32
      await _bleService.sendRfidValidationResponse(isValid, fullTagId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isValid
                  ? 'Tag RFID validado: ${fullTagId.toUpperCase()}'
                  : 'Tag RFID no autorizado: ${cleanTagId.toUpperCase()}',
            ),
            backgroundColor: isValid ? Colors.green : Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // print("❌ Error al validar tag RFID: $e");
      if (mounted) {
        setState(() {
          rfidValidationMessage = 'Error al validar tag: ${cleanTagId.toUpperCase()}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error validando tag: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      try {
        await _bleService.sendRfidValidationResponse(false, cleanTagId);
      } catch (bleError) {
        // print("❌ Error al enviar respuesta de validación RFID fallida: $bleError");
      }
    }
  }


  // Navegar a la pantalla de gestión de tags RFID
  void _navigateToRfidManagement() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const RfidManagementPage()));
  }

  // Navegar a la página de historial
  void _navigateToHistory() {
    context.push('/history');
  }
  
  // Navegar a la página de preset de litros
  Future<void> _navigateToPreset() async {
    // Mostrar la página de preset y esperar el resultado
    final result = await context.push<double>('/preset');
    
    // Si el usuario seleccionó un preset válido
    if (result != null && result > 0) {
      setState(() {
        presetLitros = result;
        presetActivo = true;
      });
      
      // Enviar el preset al ESP32
      try {
        await _bleService.sendPresetLitros(result);
        
        // Mostrar mensaje de confirmación
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Preset configurado: ${result.toStringAsFixed(2)} L'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        // Mostrar error si no se pudo enviar el preset
        if (mounted) {
          setState(() {
            presetActivo = false;
            presetLitros = null;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al configurar preset: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }
  
  // Cancelar el preset actual
  Future<void> _cancelarPreset() async {
    try {
      await _bleService.cancelPreset();
      
      setState(() {
        presetActivo = false;
        presetLitros = null;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preset cancelado'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cancelar preset: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('ESP32 BLE Dispensador'),
            const SizedBox(width: 8),
            // Indicador de estado de conexión
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _bleService.isConnected ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _navigateToHistory,
            tooltip: 'Historial de Dispensas',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              context.push('/settings');
            },
            tooltip: 'Configuración',
          ),
          if (_bleService.isConnected)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _guardarEnHistorial,
              tooltip: 'Guardar lectura actual',
            ),
          if (_bleService.isConnected)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _resetCounter,
              tooltip: 'Reiniciar contador',
            ),
          IconButton(
            icon: const Icon(Icons.nfc),
            onPressed: _navigateToRfidManagement,
            tooltip: 'Gestionar Tags RFID',
          ),
        ],
      ),
      body:
          _bleService.isConnected
              ? Column(
                children: [
                  Text("Conectado a: ${_bleService.connectedDevice?.name}"),
                  const SizedBox(height: 16),

                  // Mostrar datos recibidos para depuración
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(13),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withAlpha(77)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Datos recibidos del ESP32:",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          receivedData,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),
                  
                  // Mostrar información del preset si está activo
                  if (presetActivo && presetLitros != null)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.auto_awesome, color: Colors.green.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Preset Activo: ${presetLitros!.toStringAsFixed(2)} L',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                  fontSize: 16,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.cancel, color: Colors.red),
                                onPressed: _cancelarPreset,
                                tooltip: 'Cancelar preset',
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: litros / (presetLitros ?? 1),
                            backgroundColor: Colors.green.shade100,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Progreso: ${litros.toStringAsFixed(2)} / ${presetLitros!.toStringAsFixed(2)} L',
                            style: TextStyle(color: Colors.green.shade700),
                          ),
                        ],
                      ),
                    ),
                  
                  DispenseDisplay(litros: litros, flujo: flujo),
                  const SizedBox(height: 20),
                  
                  // Mostrar botones de acción condicionalmente
                  if (lastValidatedTagId != null)
                    // Si hay un RFID autorizado, mostrar botón de preset y guardar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _navigateToPreset,
                            icon: const Icon(Icons.water_drop),
                            label: const Text('Configurar Preset'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _guardarEnHistorial,
                            icon: const Icon(Icons.save),
                            label: const Text('Guardar y Reiniciar'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    // Si no hay RFID autorizado, mostrar mensaje y botón de guardar
                    Column(
                      children: [
                        // Mensaje informativo sobre RFID
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.nfc, color: Colors.orange.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  rfidValidationMessage, // Mostrar el mensaje de estado RFID dinámico
                                  style: TextStyle(
                                    color: Colors.orange.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Cuando no hay RFID autorizado, solo se muestra el mensaje.
                        // El botón de guardar y reiniciar se omite por seguridad.
                      ],
                    ),
                  
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _navigateToHistory,
                    icon: const Icon(Icons.history),
                    label: const Text('Ver Historial de Despachos'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              )
              : DeviceList(
                devices: devices,
                onScanPressed: startScan,
                onDeviceSelected: connectToDevice,
              ),
    );
  }
}
