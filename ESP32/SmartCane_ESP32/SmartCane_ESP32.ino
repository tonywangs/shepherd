/*
 * SmartCane_ESP32.ino
 *
 * ESP32-S3 BLE Peripheral for Smart Cane
 * Receives steering commands from iPhone and controls motor
 *
 * Hardware:
 * - Seeed Studio XIAO ESP32-S3
 * - GoBilda 5203 Series 312 RPM motor
 * - Motor driver (H-bridge)
 * - Haptic vibration motor
 *
 * BLE Protocol:
 * - Receives 1-byte steering commands: -1 (LEFT), 0 (NEUTRAL), +1 (RIGHT)
 * - Receives 1-byte haptic intensity: 0-255
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ========================================
// BLE UUIDs - MUST MATCH iOS APP
// ========================================
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define STEERING_CHAR_UUID  "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define HAPTIC_CHAR_UUID    "beb5483e-36e1-4688-b7f5-ea07361b26a9"

// ========================================
// Hardware Pin Definitions
// ========================================
// Motor driver pins (H-bridge)
#define MOTOR_PIN_LEFT  D0    // Left direction
#define MOTOR_PIN_RIGHT D1    // Right direction
#define MOTOR_ENABLE    D2    // Enable/PWM (speed control)

// Haptic motor
#define HAPTIC_PIN      D3    // Vibration motor control

// LED indicator
#define LED_PIN         LED_BUILTIN

// ========================================
// Motor Control Parameters
// ========================================
#define MOTOR_SPEED_NEUTRAL  0      // Stopped
#define MOTOR_SPEED_GENTLE   120    // Gentle steering (0-255 PWM)
#define MOTOR_SPEED_STRONG   200    // Strong steering for obstacles

// ========================================
// Global Variables
// ========================================
BLEServer* pServer = NULL;
BLECharacteristic* pSteeringChar = NULL;
BLECharacteristic* pHapticChar = NULL;

bool deviceConnected = false;
int8_t currentSteeringCommand = 0;
uint8_t currentHapticIntensity = 0;

unsigned long lastCommandTime = 0;
const unsigned long COMMAND_TIMEOUT = 500; // ms - safety timeout

// ========================================
// BLE Callbacks
// ========================================
class ServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      digitalWrite(LED_PIN, HIGH);
      Serial.println("[BLE] Client connected");
    }

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      digitalWrite(LED_PIN, LOW);
      Serial.println("[BLE] Client disconnected");

      // Safety: Stop motor on disconnect
      stopMotor();

      // Restart advertising
      BLEDevice::startAdvertising();
      Serial.println("[BLE] Advertising restarted");
    }
};

class SteeringCharCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      std::string value = pCharacteristic->getValue();

      if (value.length() == 1) {
        int8_t command = (int8_t)value[0];
        handleSteeringCommand(command);
        lastCommandTime = millis();
      }
    }
};

class HapticCharCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      std::string value = pCharacteristic->getValue();

      if (value.length() == 1) {
        uint8_t intensity = (uint8_t)value[0];
        triggerHaptic(intensity);
      }
    }
};

// ========================================
// Setup
// ========================================
void setup() {
  Serial.begin(115200);
  Serial.println("\n=================================");
  Serial.println("Smart Cane ESP32-S3 Starting...");
  Serial.println("=================================");

  // Configure hardware pins
  pinMode(MOTOR_PIN_LEFT, OUTPUT);
  pinMode(MOTOR_PIN_RIGHT, OUTPUT);
  pinMode(MOTOR_ENABLE, OUTPUT);
  pinMode(HAPTIC_PIN, OUTPUT);
  pinMode(LED_PIN, OUTPUT);

  // Initialize outputs to safe state
  stopMotor();
  digitalWrite(HAPTIC_PIN, LOW);
  digitalWrite(LED_PIN, LOW);

  // Initialize BLE
  initBLE();

  Serial.println("[Setup] System ready");
}

// ========================================
// Main Loop
// ========================================
void loop() {
  // Safety timeout - stop motor if no command received recently
  if (deviceConnected && (millis() - lastCommandTime > COMMAND_TIMEOUT)) {
    if (currentSteeringCommand != 0) {
      Serial.println("[Safety] Command timeout - stopping motor");
      stopMotor();
      currentSteeringCommand = 0;
    }
  }

  // Blink LED when connected
  if (deviceConnected) {
    static unsigned long lastBlink = 0;
    if (millis() - lastBlink > 1000) {
      digitalWrite(LED_PIN, !digitalRead(LED_PIN));
      lastBlink = millis();
    }
  }

  delay(10);
}

// ========================================
// BLE Initialization
// ========================================
void initBLE() {
  Serial.println("[BLE] Initializing...");

  // Create BLE device
  BLEDevice::init("SmartCane");

  // Create BLE server
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  // Create BLE service
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Create steering characteristic
  pSteeringChar = pService->createCharacteristic(
                    STEERING_CHAR_UUID,
                    BLECharacteristic::PROPERTY_WRITE |
                    BLECharacteristic::PROPERTY_WRITE_NR
                  );
  pSteeringChar->setCallbacks(new SteeringCharCallbacks());

  // Create haptic characteristic
  pHapticChar = pService->createCharacteristic(
                  HAPTIC_CHAR_UUID,
                  BLECharacteristic::PROPERTY_WRITE |
                  BLECharacteristic::PROPERTY_WRITE_NR
                );
  pHapticChar->setCallbacks(new HapticCharCallbacks());

  // Start service
  pService->start();

  // Start advertising
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // iPhone connection optimization
  pAdvertising->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("[BLE] Advertising started - waiting for connection...");
  Serial.print("[BLE] Device name: SmartCane | Service UUID: ");
  Serial.println(SERVICE_UUID);
}

// ========================================
// Motor Control Functions
// ========================================
void handleSteeringCommand(int8_t command) {
  currentSteeringCommand = command;

  switch (command) {
    case -1:  // LEFT
      steerLeft(MOTOR_SPEED_GENTLE);
      Serial.println("[Motor] ← LEFT");
      break;

    case 0:   // NEUTRAL
      stopMotor();
      Serial.println("[Motor] → NEUTRAL ←");
      break;

    case 1:   // RIGHT
      steerRight(MOTOR_SPEED_GENTLE);
      Serial.println("[Motor] RIGHT →");
      break;

    default:
      Serial.print("[Motor] Unknown command: ");
      Serial.println(command);
      stopMotor();
      break;
  }
}

void steerLeft(uint8_t speed) {
  digitalWrite(MOTOR_PIN_RIGHT, LOW);
  digitalWrite(MOTOR_PIN_LEFT, HIGH);
  analogWrite(MOTOR_ENABLE, speed);
}

void steerRight(uint8_t speed) {
  digitalWrite(MOTOR_PIN_LEFT, LOW);
  digitalWrite(MOTOR_PIN_RIGHT, HIGH);
  analogWrite(MOTOR_ENABLE, speed);
}

void stopMotor() {
  digitalWrite(MOTOR_PIN_LEFT, LOW);
  digitalWrite(MOTOR_PIN_RIGHT, LOW);
  analogWrite(MOTOR_ENABLE, 0);
}

// ========================================
// Haptic Control
// ========================================
void triggerHaptic(uint8_t intensity) {
  currentHapticIntensity = intensity;

  if (intensity > 0) {
    analogWrite(HAPTIC_PIN, intensity);
    Serial.print("[Haptic] Pulse: ");
    Serial.println(intensity);

    // Short pulse (haptic manager controls repetition)
    delay(50);
    analogWrite(HAPTIC_PIN, 0);
  } else {
    analogWrite(HAPTIC_PIN, 0);
  }
}
