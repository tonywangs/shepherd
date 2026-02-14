# BLE Protocol Specification

**Ultra-Low-Latency Communication Protocol for Smart Cane**

## Design Philosophy

This protocol is optimized for minimal latency in a real-time control system. Every design decision prioritizes speed over features.

### Key Optimizations
- **Single-byte packets** - Minimal transmission time
- **Write without response** - No ACK overhead
- **No JSON/serialization** - Direct binary values
- **Persistent connection** - No reconnection overhead
- **High connection priority** - iPhone optimization flags

## Service Definition

### Service UUID
```
4fafc201-1fb5-459e-8fcc-c5c9c331914b
```

This UUID must be identical in both iOS and ESP32 code.

## Characteristics

### 1. Steering Command Characteristic

**UUID:** `beb5483e-36e1-4688-b7f5-ea07361b26a8`

**Direction:** iPhone → ESP32

**Format:** 1 signed byte (int8_t / Int8)

**Values:**
| Value | Meaning | Motor Action |
|-------|---------|--------------|
| -1    | LEFT    | Omni wheel rolls left (lateral force) |
| 0     | NEUTRAL | Motor stopped (no lateral force) |
| +1    | RIGHT   | Omni wheel rolls right (lateral force) |

**Write Mode:** Write Without Response (fastest)

**Update Rate:** ~30 Hz (every 33ms)

**Timeout:** ESP32 stops motor if no command received for 500ms (safety)

#### iOS Implementation
```swift
var command: Int8 = -1  // or 0 or +1
let data = Data(bytes: &command, count: 1)
peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
```

#### ESP32 Implementation
```cpp
void onWrite(BLECharacteristic *pCharacteristic) {
    std::string value = pCharacteristic->getValue();
    if (value.length() == 1) {
        int8_t command = (int8_t)value[0];
        handleSteeringCommand(command);
    }
}
```

### 2. Haptic Trigger Characteristic

**UUID:** `beb5483e-36e1-4688-b7f5-ea07361b26a9`

**Direction:** iPhone → ESP32

**Format:** 1 unsigned byte (uint8_t / UInt8)

**Values:** 0-255 (haptic intensity)
- 0 = No vibration
- 128 = Medium intensity
- 255 = Maximum intensity

**Write Mode:** Write Without Response

**Update Rate:** Variable (triggered by distance changes)

**Purpose:** Trigger vibration motor pulses on ESP32

#### iOS Implementation
```swift
var intensity: UInt8 = 180
let data = Data(bytes: &intensity, count: 1)
peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
```

#### ESP32 Implementation
```cpp
void onWrite(BLECharacteristic *pCharacteristic) {
    std::string value = pCharacteristic->getValue();
    if (value.length() == 1) {
        uint8_t intensity = (uint8_t)value[0];
        analogWrite(HAPTIC_PIN, intensity);
    }
}
```

## Connection Parameters

### iOS Central Configuration
```swift
// Scanning
centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)

// Connection
centralManager.connect(peripheral, options: nil)

// No connection interval configuration needed - iOS manages automatically
```

### ESP32 Peripheral Configuration
```cpp
// Advertising parameters optimized for iPhone
pAdvertising->setMinPreferred(0x06);  // 7.5ms min interval
pAdvertising->setMaxPreferred(0x12);  // 22.5ms max interval
```

These values optimize for low latency on iOS devices.

## Latency Budget

Target end-to-end latency: **<50ms**

| Component | Target Latency | Notes |
|-----------|---------------|-------|
| ARKit frame capture | 16-33ms | 30-60 fps |
| Obstacle processing | <5ms | Optimized sampling |
| Steering decision | <1ms | Simple algorithm |
| BLE transmission | <10ms | Write without response |
| ESP32 processing | <1ms | Direct GPIO control |
| **Total** | **<50ms** | Acceptable for steering |

## Error Handling

### Connection Loss
- **iOS:** Automatically restarts scanning
- **ESP32:** Automatically restarts advertising
- **Safety:** Motor stops immediately on disconnect

### Timeout Protection
- **ESP32 side:** If no steering command received for 500ms, motor stops
- **Prevents:** Runaway motor if iPhone crashes or disconnects

### Invalid Commands
- **Handling:** Unknown values default to NEUTRAL (0)
- **Logging:** Errors logged to serial console

## Testing & Validation

### Latency Testing
```swift
// iOS - measure round trip time
let startTime = CFAbsoluteTimeGetCurrent()
peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
print("Latency: \(latency)ms")
```

### Connection Quality
```cpp
// ESP32 - log command reception rate
unsigned long lastCommandTime = 0;
void handleSteeringCommand(int8_t command) {
    unsigned long now = millis();
    unsigned long delta = now - lastCommandTime;
    Serial.printf("Command interval: %lums\n", delta);
    lastCommandTime = now;
}
```

### Expected Performance
- **Command interval:** 30-35ms (30 Hz)
- **Write latency:** <10ms
- **Connection stability:** No drops in 2+ hour session

## Security Considerations

### For Hackathon MVP
- **No encryption:** BLE connection is unencrypted
- **No authentication:** First device found is connected
- **No pairing:** Automatic connection for ease of use

### For Production
Consider adding:
- BLE pairing/bonding
- Encrypted characteristics
- Device whitelisting
- Command validation/checksums

## Debugging Tools

### iOS
```swift
// Enable BLE logging
print("[BLE] State: \(central.state)")
print("[BLE] Peripheral: \(peripheral.name ?? "Unknown")")
print("[BLE] Command sent: \(command)")
```

### ESP32
```cpp
// Serial monitor at 115200 baud
Serial.println("[BLE] Connected");
Serial.printf("[Motor] Command: %d\n", command);
```

### Recommended Debugging Flow
1. Verify ESP32 advertising (serial monitor)
2. Verify iOS scanning (Xcode console)
3. Verify connection (both sides log)
4. Verify characteristic discovery (iOS)
5. Verify command reception (ESP32)
6. Measure latency (iOS)
7. Verify motor response (physical observation)

## Packet Format Summary

Both characteristics use the same simple format:

```
+--------+
| BYTE 0 |  <- Command or intensity value
+--------+
```

**Total packet size:** 1 byte (plus BLE overhead)

**BLE overhead:** ~10 bytes (header, CRC, etc.)

**Total transmission:** ~11 bytes per command

**At 30 Hz:** ~330 bytes/sec = ~2.6 kbps (trivial bandwidth)

## Future Extensions (Phase 2+)

Potential additions without breaking existing protocol:

### Status Feedback (ESP32 → iPhone)
```
UUID: beb5483e-36e1-4688-b7f5-ea07361b26aa
Format: 1 byte bitfield
Bits:
  0: Motor active
  1: Battery low warning
  2: Motor fault
  3-7: Reserved
```

### Extended Commands (Optional)
```
UUID: beb5483e-36e1-4688-b7f5-ea07361b26ab
Format: 2 bytes
Byte 0: Command type
Byte 1: Parameter
```

These are NOT implemented in Phase 1 MVP.

---

**Protocol Version:** 1.0
**Last Updated:** February 2026
**Status:** Stable for Phase 1 MVP
