import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

final flutterReactiveBle = FlutterReactiveBle();
late DiscoveredDevice connectedDevice;
late QualifiedCharacteristic characteristic;

final serviceUuid = Uuid.parse("12345678-1234-5678-1234-56789abcdef0");
final charUuid = Uuid.parse("abcdef01-1234-5678-1234-56789abcdef0");

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE ESP32 Flutter',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<DiscoveredDevice> devices = [];
  bool isConnected = false;
  String receivedData = "";
  double litros = 0.0;
  double flujo = 0.0;
  List<Map<String, dynamic>> historial = [];
  bool _ignorarProximasLecturas =
      false; // Flag para ignorar lecturas después de reset

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadHistorial();
  }

  Future<void> _requestPermissions() async {
    await Permission.location.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
  }

  Future<void> _loadHistorial() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('historialDespachos');
    if (stored != null) {
      setState(() {
        historial = List<Map<String, dynamic>>.from(jsonDecode(stored));
      });
    }
  }

  Future<void> _saveHistorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('historialDespachos', jsonEncode(historial));
  }

  // Función para guardar el último valor en el historial cuando se presiona el botón
  // y reiniciar el contador de litros acumulados a cero
  void _guardarEnHistorial() {
    // Guardar el valor actual antes de reiniciar
    final registro = {
      "timestamp": DateTime.now().toIso8601String(),
      "litros": litros,
      "flujo": flujo,
    };

    setState(() {
      historial.add(registro);
      // Reiniciar litros acumulados a cero en la app inmediatamente
      litros = 0.0;
      // Activar flag para ignorar las próximas lecturas del ESP32
      _ignorarProximasLecturas = true;
    });

    _saveHistorial();

    // Enviar comandos al ESP32 para reiniciar su contador desde el hardware
    try {
      print("📤 Enviando comandos de reset al ESP32");
      
      // Primer comando: reset de contador
      sendData('{"reset_counter":true}');
      
      // Esperar un momento y enviar un segundo comando para confirmar
      Future.delayed(const Duration(milliseconds: 500), () {
        sendData('{"force_reset":true}');
        print("🔄 Enviado comando de force_reset al ESP32");
      });
      
      // Esperar otro momento y enviar un tercer comando para verificar
      Future.delayed(const Duration(milliseconds: 1000), () {
        sendData('{"verify_reset":true}');
        print("🔄 Enviado comando de verify_reset al ESP32");
      });

      // Programar la desactivación del flag después de un tiempo más largo
      // para asegurar que el ESP32 haya procesado todos los comandos
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _ignorarProximasLecturas = false;
            print("🔄 Volviendo a aceptar lecturas del ESP32");
          });
        }
      });
    } catch (e) {
      print("❌ Error al enviar comandos de reset: $e");
      // Desactivar el flag en caso de error
      setState(() {
        _ignorarProximasLecturas = false;
      });
    }

    // Mostrar confirmación al usuario
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Registro guardado y contador reiniciado'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void startScan() {
    devices.clear();
    flutterReactiveBle
        .scanForDevices(
          withServices: [serviceUuid],
          scanMode: ScanMode.balanced,
        )
        .listen((device) {
          if (!devices.any((d) => d.id == device.id)) {
            setState(() => devices.add(device));
          }
        });
  }

  void connectToDevice(DiscoveredDevice device) async {
    await flutterReactiveBle.connectToDevice(id: device.id).listen((
      connectionState,
    ) {
      if (connectionState.connectionState == DeviceConnectionState.connected) {
        setState(() => isConnected = true);
        connectedDevice = device;
        characteristic = QualifiedCharacteristic(
          deviceId: device.id,
          serviceId: serviceUuid,
          characteristicId: charUuid,
        );

        flutterReactiveBle.subscribeToCharacteristic(characteristic).listen((
          data,
        ) {
          final jsonString = String.fromCharCodes(data);

          // Si estamos ignorando lecturas después de un reset, solo actualizar el texto de datos recibidos
          if (_ignorarProximasLecturas) {
            setState(() {
              receivedData = jsonString;
            });
            print("🚧 Ignorando datos post-reset: $jsonString");
            return;
          }

          // Extraer valores directamente con regex para actualización instantánea
          RegExp litrosRegex = RegExp(r'"litros"\s*:\s*([0-9.]+)');
          RegExp flujoRegex = RegExp(r'"flujo"\s*:\s*([0-9.]+)');
          
          // Patrones para detectar diferentes tipos de confirmación de reset
          RegExp resetConfirmRegex = RegExp(r'"reset_confirm"\s*:\s*true');
          RegExp resetCounterConfirmRegex = RegExp(r'"reset_counter_confirm"\s*:\s*true');
          RegExp forceResetConfirmRegex = RegExp(r'"force_reset_confirm"\s*:\s*true');
          RegExp verifyResetConfirmRegex = RegExp(r'"verify_reset_confirm"\s*:\s*true');
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
            }
          }

          // También intentar el parseo JSON completo si es posible
          if (jsonString.startsWith("{") && jsonString.endsWith("}")) {
            try {
              final decoded = jsonDecode(jsonString);
              final parsedLitros =
                  double.tryParse(decoded['litros'].toString()) ?? 0.0;
              final parsedFlujo =
                  double.tryParse(decoded['flujo'].toString()) ?? 0.0;

              setState(() {
                litros = parsedLitros;
                flujo = parsedFlujo;
              });

              // Ya no guardamos automáticamente en el historial
              // Solo actualizamos los valores de litros y flujo
              // El guardado se hará manualmente con el botón
            } catch (e) {
              print("❌ Error al parsear JSON válido: $e");
            }
          } else {
            print("⚠️ Datos no están en formato JSON: $jsonString");
          }
        });
      }
    }).asFuture();
  }

  void sendData(String data) async {
    await flutterReactiveBle.writeCharacteristicWithResponse(
      characteristic,
      value: data.codeUnits,
    );
  }

  void limpiarHistorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('historialDespachos');
    setState(() {
      historial.clear();
    });
  }
  
  // Función para formatear la fecha ISO 8601 a un formato legible
  String formatearFecha(String fechaISO) {
    try {
      final fecha = DateTime.parse(fechaISO);
      final dia = fecha.day.toString().padLeft(2, '0');
      final mes = fecha.month.toString().padLeft(2, '0');
      final anio = fecha.year;
      final hora = fecha.hour.toString().padLeft(2, '0');
      final minutos = fecha.minute.toString().padLeft(2, '0');
      final segundos = fecha.second.toString().padLeft(2, '0');
      
      return "$dia/$mes/$anio $hora:$minutos:$segundos";
    } catch (e) {
      print("❌ Error al formatear fecha: $e");
      return fechaISO; // Devolver la fecha original si hay error
    }
  }
  
  // Función para mostrar el modal con detalles del registro
  void _mostrarDetalleRegistro(Map<String, dynamic> registro) {
    final double litrosReg = double.tryParse(registro['litros'].toString()) ?? 0.0;
    final double flujoReg = double.tryParse(registro['flujo'].toString()) ?? 0.0;
    final String fechaFormateada = formatearFecha(registro['timestamp']);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detalle de Registro', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  "Litros Acumulados: ${litrosReg.toStringAsFixed(2)} L",
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
                  "Flujo: ${flujoReg.toStringAsFixed(2)} L/min",
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            const Divider(),
            const Text(
              "ID de Registro:",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Text(
              registro['timestamp'],
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("BLE ESP32 Flutter")),
      body:
          isConnected
              ? Column(
                children: [
                  Text("Conectado a: ${connectedDevice.name}"),
                  const SizedBox(height: 20),
                  // Contenedor estable para mostrar litros acumulados
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.blue, width: 2.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          "LITROS ACUMULADOS",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.water_drop, color: Colors.blue, size: 36),
                            const SizedBox(width: 12),
                            Text(
                              "${litros.toStringAsFixed(2)} L",
                              style: const TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text("⚡ Flujo actual: ${flujo.toStringAsFixed(2)} L/min"),

                  // Botón para guardar el último valor en el historial
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: ElevatedButton.icon(
                      onPressed: _guardarEnHistorial,
                      icon: const Icon(Icons.save),
                      label: const Text("Guardar en historial"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextField(
                      onSubmitted: (text) => sendData(text),
                      decoration: const InputDecoration(
                        labelText: "Enviar comando al ESP32",
                      ),
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: historial.length,
                      itemBuilder: (_, i) {
                        final item = historial[i];
                        final double litrosHist =
                            double.tryParse(item['litros'].toString()) ?? 0.0;
                        final double flujoHist =
                            double.tryParse(item['flujo'].toString()) ?? 0.0;

                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          child: ListTile(
                            leading: const Icon(Icons.water_drop, color: Colors.blue),
                            title: Text(
                              "💾 ${litrosHist.toStringAsFixed(2)} L @ ${flujoHist.toStringAsFixed(2)} L/min",
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(formatearFecha(item['timestamp'])),
                            trailing: const Icon(Icons.info_outline),
                            onTap: () => _mostrarDetalleRegistro(item),
                          ),
                        );
                      },
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: limpiarHistorial,
                    icon: const Icon(Icons.delete),
                    label: const Text("Borrar historial"),
                  ),
                ],
              )
              : Column(
                children: [
                  ElevatedButton(
                    onPressed: startScan,
                    child: const Text("Buscar ESP32"),
                  ),
                  ...devices.map(
                    (device) => ListTile(
                      title: Text(
                        device.name.isEmpty ? "(Sin nombre)" : device.name,
                      ),
                      subtitle: Text(device.id),
                      onTap: () => connectToDevice(device),
                    ),
                  ),
                ],
              ),
    );
  }
}
