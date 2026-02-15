#include <Arduino.h>
#include <NimBLEDevice.h>

static constexpr char kServiceUUID[] = "8A4E1E45-1E84-4AA2-B4B8-3D960D6CE001";
static constexpr char kDataCharacteristicUUID[] = "8A4E1E45-1E84-4AA2-B4B8-3D960D6CE002";

// Hardware pins from the standalone examples.
static constexpr int kTapticPin = 1;
static constexpr int kMotorForwardPin = 3;
static constexpr int kMotorReversePin = 2;

// Taptic pulse shape from the original Taptic.ino demo.
static constexpr uint32_t kCycleMicros = 3840;
static constexpr uint8_t kPulseCycles = 2;
static constexpr float multConst = 5;

// Motor behavior tuning (adjust on hardware).
static constexpr float kMotorInputScale = 1.0f / 255.0f;  // packet speed units -> normalized input
static constexpr float kMotorTauSeconds = 0.5f;           // slightly faster exponential decay time constant
static constexpr uint32_t kPacketTimeoutMs = 250;          // if packets stop arriving, force speed input to zero

portMUX_TYPE gDataMux = portMUX_INITIALIZER_UNLOCKED;
volatile float gSpeedField = 0.0f;     // packet field #1 (called angle in iOS UI)
volatile float gDistanceField = 0.0f;  // packet field #2
volatile uint32_t gModeField = 0;      // packet field #3
volatile uint32_t gLastPacketMs = 0;

void doTapticPulse() {
  for (uint8_t i = 0; i < kPulseCycles; ++i) {
    digitalWrite(kTapticPin, HIGH);
    delayMicroseconds(kCycleMicros);
    digitalWrite(kTapticPin, LOW);
    delayMicroseconds(kCycleMicros);
  }
}


uint8_t capPwm255(float pwmValue) {
  const float capped = constrain(pwmValue, 0.0f, 255.0f);
  return static_cast<uint8_t>(roundf(capped));
}

float distanceToPulseIntervalMs(float distanceValue) {
  const float d = constrain(distanceValue, 0.0f, 500.0f);
  constexpr float minIntervalMs = 60.0f;    // very frequent at near distance
  constexpr float maxIntervalMs = 3000.0f;  // infrequent at far distance
  return minIntervalMs + (d / 500.0f) * (maxIntervalMs - minIntervalMs);
}

class DataCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* pCharacteristic, NimBLEConnInfo& connInfo) override {
    (void)connInfo;
    std::string value = pCharacteristic->getValue();

    if (value.size() != 12) {
      Serial.printf("RX size %d (expected 12)\n", static_cast<int>(value.size()));
      return;
    }

    float speed = 0.0f;
    float distance = 0.0f;
    uint32_t mode = 0;

    memcpy(&speed, value.data(), 4);
    memcpy(&distance, value.data() + 4, 4);
    memcpy(&mode, value.data() + 8, 4);

    portENTER_CRITICAL(&gDataMux);
    gSpeedField = speed;
    gDistanceField = distance;
    gModeField = mode;
    gLastPacketMs = millis();
    portEXIT_CRITICAL(&gDataMux);

    Serial.printf("Speed(field1): %.2f | Distance: %.2f | Mode: %lu\n",
                  speed,
                  distance,
                  static_cast<unsigned long>(mode));
  }
};

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* server, NimBLEConnInfo& connInfo) override {
    (void)server;
    (void)connInfo;
    Serial.println("BLE connected");
  }

  void onDisconnect(NimBLEServer* server, NimBLEConnInfo& connInfo, int reason) override {
    (void)connInfo;
    Serial.printf("BLE disconnected (reason %d), restarting advertising\n", reason);

    portENTER_CRITICAL(&gDataMux);
    gSpeedField = 0.0f;
    gLastPacketMs = 0;
    portEXIT_CRITICAL(&gDataMux);

    server->startAdvertising();
  }
};

void tapticTask(void* parameter) {
  (void)parameter;
  uint32_t lastPulseMs = millis();

  while (true) {
    float distanceSnapshot = 0.0f;
    portENTER_CRITICAL(&gDataMux);
    distanceSnapshot = gDistanceField;
    portEXIT_CRITICAL(&gDataMux);

    const float intervalMs = distanceToPulseIntervalMs(distanceSnapshot);
    const uint32_t now = millis();
    if (now - lastPulseMs >= static_cast<uint32_t>(intervalMs)) {
      doTapticPulse();
      lastPulseMs = millis();
    }

    vTaskDelay(pdMS_TO_TICKS(5));
  }
}

void motorTask(void* parameter) {
  (void)parameter;
  float motorState = 0.0f;  // Stored "impulse"/energy state
  uint32_t lastMs = millis();

  while (true) {
    const uint32_t nowMs = millis();
    float dt = (nowMs - lastMs) / 1000.0f;
    if (dt <= 0.0f) {
      dt = 0.001f;
    }
    lastMs = nowMs;

    float speedInput = 0.0f;
    uint32_t lastPacketMs = 0;
    portENTER_CRITICAL(&gDataMux);
    speedInput = gSpeedField;
    lastPacketMs = gLastPacketMs;
    portEXIT_CRITICAL(&gDataMux);

    if (lastPacketMs == 0 || (nowMs - lastPacketMs) > kPacketTimeoutMs) {
      speedInput = 0.0f;
    }

    // Signed leaky integrator: dS/dt = input - S/tau
    // Positive integral drives forward, negative integral drives reverse.
    // Output is S/tau, so integrated output tracks integrated input when S starts/ends near zero.
    const float inputNorm = constrain(speedInput * kMotorInputScale, -1.0f, 1.0f);
    motorState += dt * (inputNorm - (motorState / kMotorTauSeconds));

    const float outputNorm = constrain(motorState * multConst / kMotorTauSeconds, -1.0f, 1.0f);
    const uint8_t pwm = capPwm255(fabsf(outputNorm) * 255.0f);

    if (outputNorm >= 0.0f) {
      analogWrite(kMotorReversePin, 0);
      analogWrite(kMotorForwardPin, pwm);
    } else {
      analogWrite(kMotorForwardPin, 0);
      analogWrite(kMotorReversePin, pwm);
    }

    vTaskDelay(pdMS_TO_TICKS(20));
  }
}

NimBLECharacteristic* dataCharacteristic = nullptr;

void setup() {
  Serial.begin(115200);
  delay(1000);

  pinMode(kTapticPin, OUTPUT);
  pinMode(kMotorForwardPin, OUTPUT);
  pinMode(kMotorReversePin, OUTPUT);
  analogWrite(kMotorForwardPin, 0);
  analogWrite(kMotorReversePin, 0);

  NimBLEDevice::init("ESP32-S3-BLE");
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);

  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
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

  xTaskCreatePinnedToCore(tapticTask, "tapticTask", 4096, nullptr, 1, nullptr, 1);
  xTaskCreatePinnedToCore(motorTask, "motorTask", 4096, nullptr, 1, nullptr, 1);

  Serial.println("BLE ready. Waiting for iOS app writes...");
}

void loop() {
  // BLE + workers run continuously; keep loop idle.
  vTaskDelay(pdMS_TO_TICKS(100));
}
