#include <Arduino.h>
#include <NimBLEDevice.h>

static constexpr char kServiceUUID[] = "8A4E1E45-1E84-4AA2-B4B8-3D960D6CE001";
static constexpr char kDataCharacteristicUUID[] = "8A4E1E45-1E84-4AA2-B4B8-3D960D6CE002";

class DataCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* pCharacteristic, NimBLEConnInfo& connInfo) override {
    std::string value = pCharacteristic->getValue();

    if (value.size() != 12) {
      Serial.printf("RX size %d (expected 12)\n", static_cast<int>(value.size()));
      return;
    }

    float angle = 0.0f;
    float distance = 0.0f;
    uint32_t mode = 0;

    memcpy(&angle, value.data(), 4);
    memcpy(&distance, value.data() + 4, 4);
    memcpy(&mode, value.data() + 8, 4);

    Serial.printf("Angle: %.2f | Distance: %.2f | Mode: %lu\n", angle, distance, static_cast<unsigned long>(mode));
  }
};

NimBLECharacteristic* dataCharacteristic = nullptr;

void setup() {
  Serial.begin(115200);
  delay(1000);

  NimBLEDevice::init("ESP32-S3-BLE");
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);

  NimBLEServer* server = NimBLEDevice::createServer();
  NimBLEService* service = server->createService(kServiceUUID);

  dataCharacteristic = service->createCharacteristic(
      kDataCharacteristicUUID,
      NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
  );
  dataCharacteristic->setCallbacks(new DataCallbacks());

  service->start();

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  advertising->addServiceUUID(kServiceUUID);
  advertising->setName("ESP32-S3-BLE");
  advertising->start();

  Serial.println("BLE ready. Waiting for iOS app writes...");
}

void loop() {
  delay(20);
}
