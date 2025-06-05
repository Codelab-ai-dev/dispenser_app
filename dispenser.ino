#include <SPI.h>
#include <MFRC522.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>
#include <EEPROM.h>

#define SERVICE_UUID        "12345678-1234-5678-1234-56789abcdef0"
#define CHARACTERISTIC_UUID "abcdef01-1234-5678-1234-56789abcdef0"

#define PULSE_PIN 15
#define SS_PIN 5
#define RST_PIN 4
#define EEPROM_ADDR 0

MFRC522 rfid(SS_PIN, RST_PIN);
BLECharacteristic* pCharacteristic;
BLEServer* pServer;

bool deviceConnected = false;
bool autorizado = false;
String uidPendiente = "";
float presetLitros = -1;
unsigned long ultimoIntentoRFID = 0;
const unsigned long intervaloRFID = 1000;

volatile unsigned long pulseCount = 0;
float ppl = 80.22;
volatile unsigned long pulseCountLastSecond = 0;
volatile unsigned long lastPulseTime = 0;
const unsigned long debounceTime = 10;

unsigned long lastSendTime = 0;
const unsigned long sendInterval = 1000;

bool calibrando = false;
unsigned long pulseCountCalibracion = 0;

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    deviceConnected = true;
    Serial.println("✅ Cliente BLE conectado");
  }

  void onDisconnect(BLEServer* pServer) override {
    deviceConnected = false;
    autorizado = false;
    calibrando = false;
    Serial.println("❌ Cliente BLE desconectado");
  }
};

class MyCallbacks : public BLECharacteristicCallbacks {
  bool enLecturaFragmento = false;
  String bufferBLE = "";

  void handleBLEJson(StaticJsonDocument<256>& doc) {
    if (doc.containsKey("reset_counter") || doc.containsKey("force_reset") || doc.containsKey("verify_reset")) {
      autorizado = false;
      pulseCount = 0;
      Serial.println("🔄 Contador reiniciado y autorización revocada");
      return;
    }

    if (doc.containsKey("preset_litros")) {
      presetLitros = doc["preset_litros"];
      Serial.printf("🎯 Límite de litros configurado: %.2f\n", presetLitros);
      return;
    }

    if (doc.containsKey("set_ppl")) {
      float nuevoPPL = doc["set_ppl"];
      if (nuevoPPL > 0) {
        ppl = nuevoPPL;
        EEPROM.put(EEPROM_ADDR, ppl);
        EEPROM.commit();
        Serial.printf("📥 ppl actualizado manualmente a: %.2f y guardado en EEPROM\n", ppl);
      } else {
        Serial.println("❌ Valor inválido para set_ppl");
      }
      return;
    }

    if (doc.containsKey("start_calibration")) {
      calibrando = true;
      pulseCountCalibracion = 0;
      pulseCount = 0;
      Serial.println("⚖️ Iniciando calibración...");
      return;
    }

    if (doc.containsKey("confirm_calibration_volume")) {
      if (calibrando) {
        float litrosCalibrados = doc["confirm_calibration_volume"];
        if (litrosCalibrados > 0) {
          ppl = (float)pulseCount / litrosCalibrados;
          EEPROM.put(EEPROM_ADDR, ppl);
          EEPROM.commit();

          StaticJsonDocument<128> res;
          res["calibration_complete"] = ppl;
          String response;
          serializeJson(res, response);
          pCharacteristic->setValue(response.c_str());
          pCharacteristic->notify();

          Serial.printf("✅ Calibración completada: %.2f pulses/litro\n", ppl);
        } else {
          Serial.println("❌ Volumen de calibración inválido");
        }
        calibrando = false;
      }
      return;
    }

    if (doc.containsKey("cancel_calibration")) {
      if (calibrando) {
        calibrando = false;
        Serial.println("⛔ Calibración cancelada");
      }
      return;
    }

    String uidRecibidoTemp = "";
    if (doc.containsKey("u")) {
      uidRecibidoTemp = doc["u"].as<String>();
    } else if (doc.containsKey("uid")) {
      uidRecibidoTemp = doc["uid"].as<String>();
    }

    if (uidRecibidoTemp.length() > 0) {
      Serial.println("💎 Comparando UID recibido: " + uidRecibidoTemp);
      Serial.println("📎 Con UID pendiente: " + uidPendiente);

      if (uidRecibidoTemp.equalsIgnoreCase(uidPendiente)) {
        autorizado = true;
        Serial.println("✅ UID autorizado correctamente. Despacho habilitado.");
      } else {
        autorizado = false;
        Serial.println("⛔ UID recibido no coincide con el pendiente.");
      }
    }
  }

  void onWrite(BLECharacteristic* pChar) override {
    std::string value = pChar->getValue();
    String str = String(value.c_str());
    Serial.println("📩 BLE recibido: " + str);

    if (str == "<START>") {
      enLecturaFragmento = true;
      bufferBLE = "";
      return;
    }

    if (str == "<END>") {
      enLecturaFragmento = false;
      StaticJsonDocument<256> doc;
      DeserializationError err = deserializeJson(doc, bufferBLE);
      if (err) {
        Serial.println("❌ Error al parsear JSON fragmentado");
        return;
      }
      handleBLEJson(doc);
      return;
    }

    if (enLecturaFragmento) {
      bufferBLE += str;
      return;
    }

    StaticJsonDocument<256> doc;
    DeserializationError err = deserializeJson(doc, str);
    if (!err) handleBLEJson(doc);
    else Serial.println("❌ Error al parsear JSON directo");
  }
};

void IRAM_ATTR onPulse() {
  unsigned long now = millis();
  if (now - lastPulseTime > debounceTime) {
    pulseCount++;
    pulseCountLastSecond++;
    if (calibrando) pulseCountCalibracion++;
    lastPulseTime = now;
  }
}

void verificarUID() {
  if (rfid.PICC_IsNewCardPresent() && rfid.PICC_ReadCardSerial()) {
    char uidBuffer[32] = {0};
    for (byte i = 0; i < rfid.uid.size; i++) {
      sprintf(&uidBuffer[i * 2], "%02x", rfid.uid.uidByte[i]);
    }
    uidPendiente = String(uidBuffer);

    StaticJsonDocument<128> doc;
    doc["verify_uid"] = uidPendiente;
    String json;
    serializeJson(doc, json);

    Serial.println("📤 Enviando JSON BLE fragmentado:");
    Serial.println(json);

    pCharacteristic->setValue("<START>");
    pCharacteristic->notify();
    delay(5);

    const int maxFragmentSize = 20;
    for (int i = 0; i < json.length(); i += maxFragmentSize) {
      String fragment = json.substring(i, i + maxFragmentSize);
      pCharacteristic->setValue(fragment.c_str());
      pCharacteristic->notify();
      delay(5);
    }

    pCharacteristic->setValue("<END>");
    pCharacteristic->notify();
    delay(5);

    rfid.PICC_HaltA();
    rfid.PCD_StopCrypto1();
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(PULSE_PIN, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(PULSE_PIN), onPulse, FALLING);

  EEPROM.begin(512);
  EEPROM.get(EEPROM_ADDR, ppl);
  if (isnan(ppl) || ppl <= 0) ppl = 80.22;

  SPI.begin();
  rfid.PCD_Init();
  Serial.println("📡 Esperando tarjeta RFID...");

  BLEDevice::init("ESP32-RFID-FLUJO");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_WRITE
  );
  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setCallbacks(new MyCallbacks());

  pService->start();
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->start();

  Serial.println("🔵 BLE listo y esperando conexión...");
}

void loop() {
  if (deviceConnected && !autorizado && millis() - ultimoIntentoRFID > intervaloRFID) {
    verificarUID();
    ultimoIntentoRFID = millis();
    delay(10);
    return;
  }

  if (deviceConnected && autorizado && millis() - lastSendTime > sendInterval) {
    if (ppl <= 0) {
      Serial.println("{\"error\":\"calculo_invalido\"}");
      return;
    }

    float litros = pulseCount / ppl;
    float flujo = (pulseCountLastSecond / ppl) * 60.00;

    if (presetLitros > 0 && litros >= presetLitros) {
      autorizado = false;
      presetLitros = -1;
      Serial.println("🛑 Límite alcanzado. Despacho detenido.");
      return;
    }

    char buffer[64];
    snprintf(buffer, sizeof(buffer), "{\"litros\":%.2f,\"flujo\":%.2f}", litros, flujo);
    Serial.println(buffer);

    pCharacteristic->setValue(buffer);
    pCharacteristic->notify();

    pulseCountLastSecond = 0;
    lastSendTime = millis();
  }

  delay(10);
}