package com.example.flutter_application_2

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.util.*
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.gustavo.bluetooth/bridge"
    private val DEVICE_NAME = "ESP32_BT" // Nombre del dispositivo ESP32 a buscar
    private val UUID_SPP: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private lateinit var channel: MethodChannel
    private var isListening = false
    private var bluetoothThread: Thread? = null
    private var socket: BluetoothSocket? = null

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> {
                    // Si ya está escuchando, detener primero
                    if (isListening) {
                        stopBluetoothConnection()
                    }
                    
                    // Iniciar nueva conexión
                    listenToBluetooth()
                    result.success("Listening started")
                }
                "stopListening" -> {
                    stopBluetoothConnection()
                    result.success("Listening stopped")
                }
                "getPairedDevices" -> {
                    val devices = getPairedDevices()
                    result.success(devices)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getPairedDevices(): List<String> {
        try {
            val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            val adapter = bluetoothManager.adapter ?: return listOf("Error: Bluetooth no disponible")
            
            if (!adapter.isEnabled) {
                return listOf("Error: Bluetooth desactivado")
            }
            
            return adapter.bondedDevices.map { it.name }
        } catch (e: Exception) {
            e.printStackTrace()
            return listOf("Error: ${e.message}")
        }
    }

    private fun stopBluetoothConnection() {
        isListening = false
        bluetoothThread?.interrupt()
        try {
            socket?.close()
        } catch (e: Exception) {
            e.printStackTrace()
        }
        sendToFlutter("Connected: Conexión cerrada")
    }

    private fun listenToBluetooth() {
        bluetoothThread = thread {
            try {
                sendToFlutter("Connected: Iniciando conexión...")
                
                // Obtener el adaptador Bluetooth
                val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
                val adapter = bluetoothManager.adapter
                
                if (adapter == null) {
                    sendToFlutter("Error: Bluetooth no disponible en este dispositivo")
                    return@thread
                }
                
                if (!adapter.isEnabled) {
                    sendToFlutter("Error: Bluetooth desactivado. Por favor, actívalo e intenta de nuevo")
                    return@thread
                }
                
                // Buscar el dispositivo ESP32 emparejado
                val pairedDevices = adapter.bondedDevices
                sendToFlutter("Connected: Buscando dispositivo '$DEVICE_NAME'...")
                
                // Lista de dispositivos emparejados para depuración
                val deviceList = pairedDevices.joinToString(", ") { it.name }
                sendToFlutter("Connected: Dispositivos emparejados: $deviceList")
                
                val device = pairedDevices.firstOrNull { it.name == DEVICE_NAME }
                
                if (device == null) {
                    sendToFlutter("Error: Dispositivo '$DEVICE_NAME' no encontrado. Asegúrate de que esté emparejado y encendido")
                    return@thread
                }
                
                sendToFlutter("Connected: Dispositivo encontrado, conectando...")
                
                // Conectar al dispositivo
                socket = device.createRfcommSocketToServiceRecord(UUID_SPP)
                socket?.connect()
                
                if (socket == null || !socket!!.isConnected) {
                    sendToFlutter("Error: No se pudo establecer conexión con el dispositivo")
                    return@thread
                }
                
                val input: InputStream = socket!!.inputStream
                sendToFlutter("Connected: Conexión establecida con éxito")
                
                isListening = true
                
                // Leer datos continuamente
                val buffer = ByteArray(1024)
                var bytes: Int

                while (isListening) {
                    try {
                        bytes = input.read(buffer)
                        if (bytes > 0) {
                            val data = String(buffer, 0, bytes).trim()
                            // Validar que el dato sea un número o un formato válido
                            try {
                                // Intentar convertir a entero para validar
                                data.toInt()
                                // Si llega aquí, es un número válido
                                sendToFlutter(data)
                            } catch (e: NumberFormatException) {
                                // No es un número, enviar como mensaje de estado
                                sendToFlutter("Connected: Dato recibido (no numérico): $data")
                            }
                        }
                    } catch (e: Exception) {
                        if (isListening) {
                            sendToFlutter("Error: Error al leer datos: ${e.message}")
                            isListening = false
                            break
                        }
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
                sendToFlutter("Error: ${e.message}")
            } finally {
                try {
                    socket?.close()
                } catch (e: Exception) {
                    e.printStackTrace()
                }
                isListening = false
            }
        }
    }

    private fun sendToFlutter(value: String) {
        Handler(Looper.getMainLooper()).post {
            channel.invokeMethod("updateCounter", value)
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        stopBluetoothConnection()
    }
}