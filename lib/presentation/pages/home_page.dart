import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../../data/datasources/ble_service.dart';
import '../../data/models/dispense_record.dart';
import '../../data/repositories/dispense_repository_impl.dart';
import '../../domain/usecases/get_history_usecase.dart';
import '../../domain/usecases/save_record_usecase.dart';
import '../../domain/usecases/clear_history_usecase.dart';
import '../../domain/usecases/validate_tag_usecase.dart';
import '../pages/rfid_management_page.dart';
import '../widgets/device_list.dart';
import '../widgets/dispense_display.dart';
import 'package:go_router/go_router.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final BleService _bleService = BleService();
  final DispenseRepositoryImpl _repository = DispenseRepositoryImpl();
  late GetHistoryUseCase _getHistoryUseCase;
  late SaveRecordUseCase _saveRecordUseCase;
  late ClearHistoryUseCase _clearHistoryUseCase;
  late ValidateTagUseCase _validateTagUseCase;

  List<DiscoveredDevice> devices = [];
  List<DispenseRecord> historial = [];
  double litros = 0.0;
  double flujo = 0.0;
  String receivedData = "";
  bool _ignorarProximasLecturas = false;
  String? lastValidatedTagId; // Último tag RFID validado
  int lastRecordId = 0; // Último ID de registro usado

  @override
  void initState() {
    super.initState();
    _getHistoryUseCase = GetHistoryUseCase(_repository);
    _saveRecordUseCase = SaveRecordUseCase(_repository);
    _clearHistoryUseCase = ClearHistoryUseCase(_repository);
    _validateTagUseCase = ValidateTagUseCase();

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
        print('🔢 Último ID de registro cargado: $lastRecordId');
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

  void connectToDevice(DiscoveredDevice device) async {
    final connected = await _bleService.connectToDevice(device);

    if (connected) {
      setState(() {});

      // Buffer para acumular fragmentos de mensajes
      String messageBuffer = '';

      _bleService.subscribeToCharacteristic().listen((data) {
        final jsonString = String.fromCharCodes(data);
        print("🔵 BLE recibido: $jsonString");

        // Caso 1: Capturar fragmento inicial (contiene verify_uid pero no tiene llave de cierre)
        if (jsonString.contains("verify_uid") && !jsonString.endsWith("}")) {
          messageBuffer = jsonString;
          print("🔗 Guardando fragmento inicial: $messageBuffer");
          return;
        }

        // Caso 2: Si recibimos un fragmento que parece ser continuación (tiene } pero no tiene {)
        if (messageBuffer.isNotEmpty &&
            jsonString.contains("}") &&
            !jsonString.contains("{")) {
          String completeMessage = messageBuffer + jsonString;
          print("🕐 Mensaje completo reconstruido: $completeMessage");

          // Intentar extraer el UID
          RegExp uidRegex = RegExp(r'"verify_uid"\s*:\s*"([0-9a-fA-F]+)"');
          Match? match = uidRegex.firstMatch(completeMessage);

          if (match != null && match.groupCount >= 1) {
            String uid = match.group(1)!;
            print("🏷️ UID extraído: $uid");
            _validateRfidTag(uid);
            messageBuffer = '';
            return;
          } else {
            // Si no podemos extraer con regex, buscar cualquier secuencia hexadecimal
            RegExp hexRegex = RegExp(r'[0-9a-fA-F]{8,}');
            Match? hexMatch = hexRegex.firstMatch(completeMessage);

            if (hexMatch != null) {
              String uid = hexMatch.group(0)!;
              print("🔧 UID extraído por patrón hexadecimal: $uid");
              _validateRfidTag(uid);
              messageBuffer = '';
              return;
            }
          }

          // Limpiar buffer si no pudimos extraer nada útil
          messageBuffer = '';
        }

        // Si estamos ignorando lecturas después de un reset, solo actualizar el texto de datos recibidos
        if (_ignorarProximasLecturas) {
          setState(() {
            receivedData = jsonString;
          });
          print("🚧 Ignorando datos post-reset: $jsonString");
          return;
        }

        // Mostrar datos recibidos en UI para depuración
        setState(() {
          receivedData = jsonString;
        });

        // Intentar detectar cualquier tipo de solicitud de validación RFID
        print("🔍 Analizando mensaje para validación RFID: $jsonString");

        // Método 1: Verificar formato estándar (rfid_validation + tag_id)
        RegExp rfidValidationRegex = RegExp(r'"rfid_validation"\s*:\s*true');
        RegExp rfidTagRegex = RegExp(r'"tag_id"\s*:\s*"([0-9a-fA-F\s]+)"');

        // Método 2: Verificar formato alternativo (verify_uid)
        RegExp verifyUidRegex = RegExp(r'"verify_uid"');
        RegExp uidValueRegex = RegExp(
          r'"verify_uid"\s*:\s*"?([0-9a-fA-F\s]+)"?',
        );

        // Método 3: Verificar formato simplificado (uid)
        RegExp simpleUidRegex = RegExp(r'"uid"\s*:\s*"?([0-9a-fA-F\s]+)"?');

        // Método 4: Buscar cualquier secuencia hexadecimal que parezca un UID
        RegExp hexSequenceRegex = RegExp(r'[0-9a-fA-F]{8,}');

        String? tagId;

        // Caso 1: Formato estándar
        if (rfidValidationRegex.hasMatch(jsonString)) {
          Match? tagMatch = rfidTagRegex.firstMatch(jsonString);
          if (tagMatch != null && tagMatch.groupCount >= 1) {
            tagId = tagMatch.group(1)?.trim();
            print("🏷️ Detectado formato estándar - Tag ID: $tagId");
          }
        }

        // Caso 2: Formato verify_uid
        if (tagId == null && verifyUidRegex.hasMatch(jsonString)) {
          Match? uidMatch = uidValueRegex.firstMatch(jsonString);
          if (uidMatch != null && uidMatch.groupCount >= 1) {
            tagId = uidMatch.group(1)?.trim();
            print("🔑 Detectado formato verify_uid - UID: $tagId");
          } else {
            // Extracción manual si la regex falla
            int startIndex = jsonString.indexOf('"verify_uid"');
            if (startIndex >= 0) {
              // Buscar el valor después de verify_uid
              String restOfString = jsonString.substring(startIndex + 11);
              // Buscar cualquier secuencia hexadecimal
              Match? hexMatch = hexSequenceRegex.firstMatch(restOfString);
              if (hexMatch != null) {
                tagId = hexMatch.group(0)?.trim();
                print("💾 Extracción manual de verify_uid - UID: $tagId");
              }
            }
          }
        }

        // Caso 3: Formato simple uid
        if (tagId == null) {
          Match? simpleMatch = simpleUidRegex.firstMatch(jsonString);
          if (simpleMatch != null && simpleMatch.groupCount >= 1) {
            tagId = simpleMatch.group(1)?.trim();
            print("💼 Detectado formato simple uid - UID: $tagId");
          }
        }

        // Caso 4: Último recurso - buscar cualquier secuencia hexadecimal
        if (tagId == null) {
          Match? hexMatch = hexSequenceRegex.firstMatch(jsonString);
          if (hexMatch != null) {
            tagId = hexMatch.group(0)?.trim();
            print("🔧 Extracción de secuencia hexadecimal - UID: $tagId");
          }
        }

        // Si encontramos un ID válido, validarlo
        if (tagId != null && tagId.isNotEmpty) {
          print("🔎 Validando tag RFID: $tagId");
          _validateRfidTag(tagId);
          return;
        } else {
          print("⛔ No se pudo extraer ningún UID válido de: $jsonString");
        }

        // Extraer valores directamente con regex para actualización instantánea
        RegExp litrosRegex = RegExp(r'"litros"\s*:\s*([0-9.]+)');
        RegExp flujoRegex = RegExp(r'"flujo"\s*:\s*([0-9.]+)');

        // Patrones para detectar diferentes tipos de confirmación de reset
        RegExp resetConfirmRegex = RegExp(r'"reset_confirm"\s*:\s*true');
        RegExp resetCounterConfirmRegex = RegExp(
          r'"reset_counter_confirm"\s*:\s*true',
        );
        RegExp forceResetConfirmRegex = RegExp(
          r'"force_reset_confirm"\s*:\s*true',
        );
        RegExp verifyResetConfirmRegex = RegExp(
          r'"verify_reset_confirm"\s*:\s*true',
        );
        RegExp resetCompleteRegex = RegExp(r'"reset_complete"\s*:\s*true');

        // Verificar si recibimos alguna confirmación de reset
        if (resetConfirmRegex.hasMatch(jsonString) ||
            resetCounterConfirmRegex.hasMatch(jsonString) ||
            forceResetConfirmRegex.hasMatch(jsonString) ||
            verifyResetConfirmRegex.hasMatch(jsonString) ||
            resetCompleteRegex.hasMatch(jsonString)) {
          print("🔄 Confirmación de reset recibida del ESP32: $jsonString");

          // Forzar el valor de litros a cero nuevamente para asegurar
          setState(() {
            litros = 0.0;
          });

          return;
        }

        // Buscar valor de litros
        Match? litrosMatch = litrosRegex.firstMatch(jsonString);
        if (litrosMatch != null && litrosMatch.groupCount >= 1) {
          String litrosStr = litrosMatch.group(1) ?? "0";
          double? parsedLitros = double.tryParse(litrosStr);
          if (parsedLitros != null) {
            setState(() {
              litros = parsedLitros;
              receivedData = jsonString;
            });
            print("🟦 Litros por regex: $parsedLitros");
          }
        }

        // Buscar valor de flujo
        Match? flujoMatch = flujoRegex.firstMatch(jsonString);
        if (flujoMatch != null && flujoMatch.groupCount >= 1) {
          String flujoStr = flujoMatch.group(1) ?? "0";
          double? parsedFlujo = double.tryParse(flujoStr);
          if (parsedFlujo != null) {
            setState(() {
              flujo = parsedFlujo;
            });
            print("🟧 Flujo por regex: $parsedFlujo");
          }
        }

        // También intentar el parseo JSON completo si es posible
        if (jsonString.startsWith("{") && jsonString.endsWith("}")) {
          try {
            final decoded = jsonDecode(jsonString);
            print("🟩 Decoded JSON: $decoded");
            final parsedLitros =
                double.tryParse(decoded['litros'].toString()) ?? 0.0;
            final parsedFlujo =
                double.tryParse(decoded['flujo'].toString()) ?? 0.0;
            print("🟨 Litros JSON: $parsedLitros, Flujo JSON: $parsedFlujo");

            setState(() {
              litros = parsedLitros;
              flujo = parsedFlujo;
            });
          } catch (e) {
            print("❌ Error al parsear JSON válido: $e");
          }
        } else {
          print("⚠️ Datos no están en formato JSON: $jsonString");
        }
      });
    }
  }

  void _guardarEnHistorial() {
    // Incrementar el ID para la nueva transacción
    lastRecordId++;

    // Crear un registro incluyendo el tagId si está disponible
    final record = DispenseRecord(
      id: lastRecordId,
      timestamp: DateTime.now(),
      litros: litros,
      flujo: flujo,
      tagId: lastValidatedTagId, // Incluir el último tag validado
    );

    _saveRecordUseCase.execute(record);

    setState(() {
      historial.add(record);
      _ignorarProximasLecturas = true;
    });

    // Reiniciar el contador después de guardar
    _resetCounter(showMessage: 'Registro guardado y contador reiniciado');
  }

  // Método para reiniciar el contador sin guardar en historial
  void _resetCounter({String? showMessage}) {
    setState(() {
      _ignorarProximasLecturas = true;
    });

    // Enviar comandos de reset al ESP32
    try {
      _bleService.sendData('{"reset_counter":true}');

      Future.delayed(const Duration(milliseconds: 500), () {
        _bleService.sendData('{"force_reset":true}');
      });

      Future.delayed(const Duration(milliseconds: 1000), () {
        _bleService.sendData('{"verify_reset":true}');
      });

      // Establecer litros a 0 después de enviar los comandos
      setState(() {
        litros = 0.0;
      });

      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _ignorarProximasLecturas = false;
          });
        }
      });

      // Mostrar mensaje si se proporciona
      if (showMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(showMessage),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contador reiniciado'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print("❌ Error al enviar comandos de reset: $e");
      setState(() {
        _ignorarProximasLecturas = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al reiniciar: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void limpiarHistorial() async {
    await _clearHistoryUseCase.execute();
    setState(() {
      historial.clear();
    });
  }

  // Método para validar un tag RFID y enviar respuesta al ESP32
  Future<void> _validateRfidTag(String tagId) async {
    try {
      final isValid = await _validateTagUseCase.execute(tagId);

      // Guardar el tagId si es válido para incluirlo en el historial
      if (isValid) {
        setState(() {
          lastValidatedTagId = tagId;
        });
      }

      // Enviar respuesta al ESP32
      await _bleService.sendRfidValidationResponse(isValid, tagId);

      // Mostrar mensaje en la UI
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isValid
                  ? 'Tag RFID validado correctamente: ${tagId.toUpperCase()}'
                  : 'Tag RFID no autorizado: ${tagId.toUpperCase()}',
            ),
            backgroundColor: isValid ? Colors.green : Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print("❌ Error al validar tag RFID: $e");
      // Enviar respuesta de error al ESP32
      await _bleService.sendRfidValidationResponse(false, tagId);
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
                      color: Colors.black.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
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
                  DispenseDisplay(litros: litros, flujo: flujo),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _guardarEnHistorial,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      "Guardar y Reiniciar Contador",
                      style: TextStyle(fontSize: 16),
                    ),
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
