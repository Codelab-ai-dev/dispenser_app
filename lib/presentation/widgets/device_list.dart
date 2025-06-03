import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class DeviceList extends StatelessWidget {
  final List<DiscoveredDevice> devices;
  final VoidCallback onScanPressed;
  final Function(DiscoveredDevice) onDeviceSelected;

  const DeviceList({
    Key? key,
    required this.devices,
    required this.onScanPressed,
    required this.onDeviceSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            onPressed: onScanPressed,
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text("Buscar ESP32"),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ),
        devices.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "No se encontraron dispositivos. Presiona 'Buscar ESP32' para iniciar el escaneo.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                  ),
                ),
              )
            : Expanded(
                child: ListView.builder(
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.bluetooth, color: Colors.blue),
                        title: Text(
                          device.name.isEmpty ? "(Sin nombre)" : device.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          "ID: ${device.id}",
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios),
                        onTap: () => onDeviceSelected(device),
                      ),
                    );
                  },
                ),
              ),
      ],
    );
  }
}
