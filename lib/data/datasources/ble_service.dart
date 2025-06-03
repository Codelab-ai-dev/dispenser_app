import 'dart:async';
import 'dart:convert';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

// Definir constantes BLE
final serviceUuid = Uuid.parse("12345678-1234-5678-1234-56789abcdef0");
final charUuid = Uuid.parse("abcdef01-1234-5678-1234-56789abcdef0");
final FlutterReactiveBle flutterReactiveBle = FlutterReactiveBle();

class BleService {
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
  
  // Constantes BLE

  bool get isConnected => _connectedDevice != null;
  DiscoveredDevice? get connectedDevice => _connectedDevice;
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  Stream<String> get dataStream => _dataStreamController.stream;

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
  
  // Método para enviar respuesta de validación de RFID al ESP32
  Future<void> sendRfidValidationResponse(bool isValid, String tagId) async {
    // Asegurarse de que el UID esté completo (debe ser una cadena hexadecimal)
    final String cleanTagId = tagId.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    print("🔍 UID limpio: $cleanTagId");
    
    try {
      // Enviar primero un mensaje ultra corto para indicar validez
      final validMessage = isValid ? '{"v":1}' : '{"v":0}';
      print("📌 Enviando indicador de validez: $validMessage");
      await sendData(validMessage);
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Luego enviar el UID en un mensaje separado
      final uidMessage = '{"u":"$cleanTagId"}'; 
      print("🔑 Enviando UID: $uidMessage");
      await sendData(uidMessage);
      await Future.delayed(const Duration(milliseconds: 100));
      
      print("✅ Respuesta RFID enviada en dos partes");
    } catch (e) {
      print("❌ Error al enviar respuesta RFID: $e");
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
  
  // Método para limpiar recursos cuando se destruye el servicio
  void dispose() {
    disconnect();
    _connectionStatusController.close();
    _dataStreamController.close();
  }
}
