import 'dart:async';
import 'dart:convert';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

// Definir constantes BLE
final serviceUuid = Uuid.parse("12345678-1234-5678-1234-56789abcdef0");
final charUuid = Uuid.parse("abcdef01-1234-5678-1234-56789abcdef0");
final FlutterReactiveBle flutterReactiveBle = FlutterReactiveBle();

class BleService {
  // Singleton setup
  static final BleService _instance = BleService._internal();
  static BleService get instance => _instance;
  BleService._internal(); // Private constructor
  // Variables de estado BLE
  DiscoveredDevice? _connectedDevice;
  QualifiedCharacteristic? _characteristic;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _characteristicSubscription;
  Timer? _reconnectTimer;
  bool _isReconnecting = false;
  
  // Ya no necesitamos un buffer para acumular datos
  
  // Controladores de Stream para comunicar eventos
  final _connectionStatusController = StreamController<bool>.broadcast();
  final _dataStreamController = StreamController<String>.broadcast();
  final _calibrationStatusController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Constantes BLE

  bool get isConnected => _connectedDevice != null;
  DiscoveredDevice? get connectedDevice => _connectedDevice;
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  Stream<String> get dataStream => _dataStreamController.stream;
  Stream<Map<String, dynamic>> get calibrationStatusStream => _calibrationStatusController.stream;

  Future<void> requestPermissions() async {
    await Permission.location.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
  }

  Stream<DiscoveredDevice> scanForDevices() {
    return flutterReactiveBle.scanForDevices(
      withServices: [serviceUuid],
      scanMode: ScanMode.balanced,
    );
  }

  Future<bool> connectToDevice(DiscoveredDevice device) async {
    // Si ya estamos conectados o intentando reconectar, desconectar primero
    if (_connectionSubscription != null) {
      await _connectionSubscription!.cancel();
      _connectionSubscription = null;
    }
    
    if (_characteristicSubscription != null) {
      await _characteristicSubscription!.cancel();
      _characteristicSubscription = null;
    }
    
    final completer = Completer<bool>();
    
    _connectionSubscription = flutterReactiveBle
        .connectToDevice(
          id: device.id,
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen(
          (connectionState) {
            print("🔌 Estado de conexión BLE: ${connectionState.connectionState}");
            
            if (connectionState.connectionState == DeviceConnectionState.connected) {
              _connectedDevice = device;
              _characteristic = QualifiedCharacteristic(
                deviceId: device.id,
                serviceId: serviceUuid,
                characteristicId: charUuid,
              );
              
              _connectionStatusController.add(true);
              _isReconnecting = false;
              
              // Cancelar cualquier temporizador de reconexión en curso
              _reconnectTimer?.cancel();
              
              if (!completer.isCompleted) completer.complete(true);
              
              // Suscribirse automáticamente a la característica al conectar
              subscribeToCharacteristic();
            } 
            else if (connectionState.connectionState == DeviceConnectionState.disconnected) {
              print("📴 Dispositivo BLE desconectado: ${device.id}");
              
              // Notificar a la UI sobre la desconexión
              _connectionStatusController.add(false);
              
              // Intentar reconectar automáticamente si no estamos ya en proceso de reconexión
              if (!_isReconnecting && _connectedDevice != null) {
                _attemptReconnect(device);
              }
              
              if (!completer.isCompleted) completer.complete(false);
            }
          },
          onError: (error) {
            print("❌ Error al conectar BLE: $error");
            _connectionStatusController.add(false);
            
            // Intentar reconectar en caso de error si teníamos un dispositivo conectado
            if (_connectedDevice != null) {
              _attemptReconnect(device);
            }
            
            if (!completer.isCompleted) completer.complete(false);
          },
        );

    final result = await completer.future;
    return result;
  }

  Stream<List<int>> subscribeToCharacteristic() {
    if (_characteristic == null) {
      throw Exception('No conectado a ningún dispositivo');
    }
    
    // Cancelar suscripción anterior si existe
    _characteristicSubscription?.cancel();
    
    // Iniciar nueva suscripción
    
    // Suscribirse a las notificaciones de la característica
    _characteristicSubscription = flutterReactiveBle
        .subscribeToCharacteristic(_characteristic!)
        .listen(
          (data) {
            // Procesar datos recibidos
            _processJsonBuffer(data);
          },
          onError: (error) {
            print("❌ Error al recibir datos BLE: $error");
          },
        );
    
    // Devolver el stream original para compatibilidad
    return flutterReactiveBle.subscribeToCharacteristic(_characteristic!);
  }

  void _processJsonBuffer(List<int> data) {
    // Convertir bytes a string y emitir directamente sin ningún procesamiento
    final receivedText = String.fromCharCodes(data);
    print("📥 Datos BLE recibidos: $receivedText");
    
    // Emitir directamente todos los datos recibidos
    if (receivedText.isNotEmpty) {
      _dataStreamController.add(receivedText);
    }
  }
  
  // Método eliminado: _tryExtractJson ya no se utiliza
  


  // Método para enviar datos al dispositivo BLE
  Future<void> sendData(String data) async {
    if (_characteristic == null) {
      throw Exception('No conectado a ningún dispositivo');
    }
    print("📤 Enviando datos: $data (${data.length} bytes)");
    try {
      // Convertir a bytes y enviar directamente sin procesamiento
      final bytes = utf8.encode(data);
      
      // Usar writeCharacteristicWithoutResponse para mensajes pequeños
      // Esto puede ayudar con problemas de fragmentación en algunos dispositivos
      if (bytes.length <= 20) {
        await flutterReactiveBle.writeCharacteristicWithoutResponse(
          _characteristic!,
          value: bytes,
        );
      } else {
        // Para mensajes más grandes, usar writeCharacteristicWithResponse
        await flutterReactiveBle.writeCharacteristicWithResponse(
          _characteristic!,
          value: bytes,
        );
      }
      
      print("✅ Datos enviados correctamente");
    } catch (e) {
      print("❌ Error al enviar datos: $e");
      throw e;
    }
  }
  
  // Método para enviar el valor de Pulsos Por Litro (PPL) al ESP32
  Future<void> sendPplValue(int ppl) async {
    if (_characteristic == null) {
      throw Exception('No conectado a ningún dispositivo o característica no disponible.');
    }
    final String command = '{"set_ppl":$ppl}';
    print("📤 Enviando comando PPL: $command");
    await sendData(command);
    // Considerar un pequeño delay si es necesario para el ESP32 procesar
    // await Future.delayed(const Duration(milliseconds: 100)); 
  }

  // --- Métodos para Calibración Automática ---
  Future<void> startAutoCalibration(double litros) async {
    if (_characteristic == null) throw Exception('Característica BLE no disponible.');
    final command = '{"start_calibration":$litros}';
    print('📤 Enviando comando Iniciar Calibración Automática: $command');
    await sendData(command);
  }

  Future<void> confirmAutoCalibrationVolume() async {
    if (_characteristic == null) throw Exception('Característica BLE no disponible.');
    const command = '{"confirm_calibration_volume":true}';
    print('📤 Enviando comando Confirmar Volumen Calibración: $command');
    await sendData(command);
  }

  Future<void> cancelAutoCalibration() async {
    if (_characteristic == null) throw Exception('Característica BLE no disponible.');
    const command = '{"cancel_calibration":true}';
    print('📤 Enviando comando Cancelar Calibración: $command');
    await sendData(command);
  }

  // Método para enviar respuesta de validación de RFID al ESP32
  Future<void> sendRfidValidationResponse(bool isValid, String tagId) async {
    print("[DEBUG BleService] sendRfidValidationResponse received tagId: '$tagId'");
    // Asegurarse de que el UID esté completo (debe ser una cadena hexadecimal)
    final String cleanTagId = tagId.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    print("[DEBUG BleService] sendRfidValidationResponse cleanTagId after replaceAll: '$cleanTagId'");
    
    try {
      // Primero enviamos el mensaje de validación
      final validMessage = isValid ? '{"v":1}' : '{"v":0}';
      await sendData(validMessage);
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Asegurarnos de enviar el UID completo, sin truncar
      // Enviamos el UID exactamente como está en la base de datos
      final uidMessage = '{"u":"$cleanTagId","full_uid":true}';
      print("[DEBUG BleService] sendRfidValidationResponse uidMessage: '$uidMessage'");
      await sendData(uidMessage);
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      print("❌ Error al enviar respuesta RFID: $e");
      throw e;
    }
  }
  
  /// Envía el preset de litros al ESP32
  /// 
  /// Este método envía un comando al ESP32 para configurar un límite
  /// automático de despacho. Cuando se alcance esta cantidad de litros,
  /// el ESP32 detendrá automáticamente el flujo.
  Future<void> sendPresetLitros(double litros) async {
    try {
      // Redondear a 2 decimales para evitar problemas de precisión
      final litrosRedondeados = litros.toStringAsFixed(2);
      
      // Crear el mensaje JSON con el preset
      final presetMessage = '{"preset_litros":$litrosRedondeados}';
      print("🎯 Enviando preset de litros: $litrosRedondeados L");
      
      // Enviar el comando al ESP32
      await sendData(presetMessage);
      
      // Enviar un comando de confirmación después de un breve retraso
      await Future.delayed(const Duration(milliseconds: 100));
      await sendData('{"preset_confirm":true}');
    } catch (e) {
      print("❌ Error al enviar preset de litros: $e");
      throw e;
    }
  }
  
  /// Cancela el preset actual y detiene el despacho
  Future<void> cancelPreset() async {
    try {
      await sendData('{"cancel_preset":true}');
    } catch (e) {
      print("❌ Error al cancelar preset: $e");
      throw e;
    }
  }

  void disconnect() async {
    // Cancelar temporizador de reconexión si existe
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    
    // Cancelar suscripciones
    await _characteristicSubscription?.cancel();
    _characteristicSubscription = null;
    
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    
    _connectedDevice = null;
    _characteristic = null;
    
    // Notificar a la UI
    _connectionStatusController.add(false);
  }
  
  // Método para intentar reconectar automáticamente
  void _attemptReconnect(DiscoveredDevice device) {
    if (_isReconnecting) return;
    
    _isReconnecting = true;
    print("🔄 Intentando reconectar a ${device.name}...");
    
    // Cancelar temporizador anterior si existe
    _reconnectTimer?.cancel();
    
    // Intentar reconectar después de un breve retraso
    _reconnectTimer = Timer(const Duration(seconds: 2), () async {
      try {
        // Limpiar estado actual
        await _connectionSubscription?.cancel();
        _connectionSubscription = null;
        
        // Intentar conectar nuevamente
        final success = await connectToDevice(device);
        if (success) {
          print("✅ Reconexión exitosa a ${device.name}");
        } else {
          print("❌ Falló la reconexión a ${device.name}");
          // Programar otro intento después de un tiempo más largo
          _reconnectTimer = Timer(const Duration(seconds: 5), () {
            if (_isReconnecting) {
              _attemptReconnect(device);
            }
          });
        }
      } catch (e) {
        print("❌ Error durante la reconexión: $e");
        _isReconnecting = false;
      }
    });
  }
  
  // Métodos para reportar el estado de la calibración
  void reportCalibrationSuccess(int newPpl) {
    _calibrationStatusController.add({'status': 'success', 'new_ppl': newPpl});
  }

  void reportCalibrationFailure(String error) {
    _calibrationStatusController.add({'status': 'failure', 'error': error});
  }

  // Método para limpiar recursos cuando se destruye el servicio
  void dispose() {
    disconnect();
    _connectionStatusController.close();
    _dataStreamController.close();
    _calibrationStatusController.close();
  }
}
