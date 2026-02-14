# Smart Cane - Hackathon MVP

**Self-navigating smart white cane with lateral steering guidance**

## System Overview

This system uses an iPhone 14 Pro Max (LiDAR + camera + IMU) to detect obstacles and guide the user by applying **lateral steering force only** through an omni wheel mounted on the cane.

### Critical Mechanical Understanding
- The omni wheel **does NOT** drive the cane forward/backward
- It only rolls laterally (left ↔ right)
- The motor pushes the cane sideways to gently guide the user's hand
- Forward walking is entirely controlled by the human
- System only provides assistive steering correction

## Architecture

```
iPhone (ARKit + LiDAR)
  ↓
Obstacle Detection (3 zones)
  ↓
Steering Decision (LEFT/NEUTRAL/RIGHT)
  ↓
BLE (1-byte command)
  ↓
ESP32-S3 Motor Control
  ↓
Lateral Force on Cane
```

## Project Structure

```
SmartCane/
├── SmartCane/
│   ├── SmartCaneApp.swift           # App entry point
│   ├── ContentView.swift             # UI (status display)
│   ├── Core/
│   │   └── SmartCaneController.swift # Main coordinator
│   ├── Sensors/
│   │   └── DepthSensor.swift         # ARKit + LiDAR capture
│   ├── Navigation/
│   │   ├── ObstacleDetector.swift    # Zone-based obstacle analysis
│   │   └── SteeringEngine.swift      # Lateral steering logic
│   ├── Communication/
│   │   └── BLEManager.swift          # Ultra-low-latency BLE
│   └── Feedback/
│       ├── HapticManager.swift       # Distance-based haptics
│       └── VoiceManager.swift        # Speech I/O
│
ESP32/
└── SmartCane_ESP32/
    └── SmartCane_ESP32.ino           # ESP32 motor control
```

## Hardware Requirements

### iPhone
- iPhone 14 Pro Max (or any iPhone with LiDAR)
- iOS 17.0+
- Xcode 26.2

### ESP32 System
- Seeed Studio XIAO ESP32-S3
- GoBilda 5203 Series 312 RPM motor
- H-bridge motor driver (L298N or similar)
- 3.25" omni wheel
- Haptic vibration motor
- Power supply (battery pack)

## Pin Configuration (ESP32)

```
D0  → Motor Left Direction
D1  → Motor Right Direction
D2  → Motor Enable (PWM speed control)
D3  → Haptic Motor
LED → Status indicator
```

## BLE Protocol

**Service UUID:** `4fafc201-1fb5-459e-8fcc-c5c9c331914b`

### Characteristics

1. **Steering Command** (`beb5483e-36e1-4688-b7f5-ea07361b26a8`)
   - Format: 1 signed byte
   - Values:
     - `-1` = Steer LEFT
     - `0` = NEUTRAL (no steering)
     - `+1` = Steer RIGHT
   - Write without response (lowest latency)

2. **Haptic Trigger** (`beb5483e-36e1-4688-b7f5-ea07361b26a9`)
   - Format: 1 unsigned byte
   - Values: 0-255 (intensity)
   - Write without response

## Setup Instructions

### iPhone App Setup

1. **Open project in Xcode**
   ```bash
   open SmartCane/SmartCane.xcodeproj
   ```

2. **Configure signing**
   - Select your development team
   - Change bundle identifier if needed

3. **Add permissions to Info.plist** (already configured)
   - Camera/LiDAR usage
   - Bluetooth usage
   - Microphone/Speech recognition
   - Location (for Phase 3)

4. **Build and run on iPhone 14 Pro Max**

### ESP32 Setup

1. **Install Arduino IDE** (version 2.x)

2. **Add ESP32 board support**
   - File → Preferences
   - Additional Boards Manager URLs:
     ```
     https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
     ```
   - Tools → Board → Boards Manager → Install "esp32"

3. **Install BLE libraries**
   - Should be included with ESP32 board package

4. **Select board**
   - Tools → Board → ESP32 Arduino → XIAO_ESP32S3

5. **Connect hardware**
   - Follow pin configuration above
   - Connect motor driver to motor
   - Connect power supply

6. **Upload code**
   ```
   Open: ESP32/SmartCane_ESP32/SmartCane_ESP32.ino
   Upload to ESP32
   ```

7. **Verify serial output**
   - Open Serial Monitor (115200 baud)
   - Should see: "Smart Cane ESP32-S3 Starting..."
   - Should see: "[BLE] Advertising started"

### Pairing and Testing

1. **Power on ESP32**
   - LED should start blinking slowly (advertising)

2. **Start iPhone app**
   - Should automatically discover "SmartCane"
   - LED on ESP32 will turn solid when connected

3. **Test system**
   - Press "Start System" in app
   - Walk toward a wall
   - Cane should apply lateral steering force
   - Haptic pulses should increase as you approach

4. **Monitor performance**
   - Check latency display (<20ms is good)
   - Check Serial Monitor for motor commands
   - Verify steering direction matches obstacles

## Phase Implementation Status

### ✅ Phase 1 (Core MVP)
- [x] LiDAR depth sensing (ARKit)
- [x] 3-zone obstacle detection
- [x] Lateral steering algorithm
- [x] Ultra-low-latency BLE (1-byte packets)
- [x] Distance-based haptic feedback
- [x] Full iOS + ESP32 code

### 🚧 Phase 2 (Object Recognition)
- [ ] Vision framework integration
- [ ] VNRecognizeObjectsRequest
- [ ] Voice announcements for object types

### 🚧 Phase 3 (GPS Navigation)
- [ ] CoreLocation + MapKit integration
- [ ] Turn-by-turn voice guidance
- [ ] Route planning

## Tuning Parameters

### iOS (SteeringEngine.swift)
```swift
obstacleThreshold: 1.2m    // Triggers avoidance
criticalThreshold: 0.6m    // Aggressive avoidance
```

### iOS (ObstacleDetector.swift)
```swift
maxDetectionRange: 1.5m    // Maximum sensing range
minDetectionRange: 0.2m    // Minimum range (too close)
```

### ESP32 (SmartCane_ESP32.ino)
```cpp
MOTOR_SPEED_GENTLE: 120    // PWM value (0-255)
MOTOR_SPEED_STRONG: 200    // For critical obstacles
```

## Troubleshooting

### BLE Connection Issues
- **Symptom:** iPhone can't find ESP32
- **Fix:**
  - Check ESP32 serial output shows "Advertising started"
  - Restart Bluetooth on iPhone
  - Power cycle ESP32

### Motor Not Responding
- **Symptom:** BLE connected but no motor movement
- **Fix:**
  - Check motor driver power supply
  - Verify pin connections
  - Check serial monitor for steering commands
  - Test motor directly with driver

### High Latency (>50ms)
- **Symptom:** Sluggish steering response
- **Fix:**
  - Move phone closer to ESP32
  - Reduce interference (avoid WiFi congestion)
  - Check BLE is using "write without response"
  - Verify no other apps using Bluetooth

### LiDAR Not Working
- **Symptom:** No depth data
- **Fix:**
  - Verify device has LiDAR (iPhone 14 Pro)
  - Check camera permissions in Settings
  - Clean LiDAR sensor
  - Restart app

### Haptic Feedback Weak/Missing
- **Symptom:** No vibration or too weak
- **Fix:**
  - Check haptic motor connections
  - Increase intensity in HapticManager
  - Test with different PWM values on ESP32

## Risk Mitigation

### Primary Risks

1. **LiDAR fails in bright sunlight**
   - **Fallback:** Use camera-based depth estimation (ARKit still provides rough depth)
   - **Workaround:** Reduce maxDetectionRange, rely more on haptics

2. **BLE latency too high**
   - **Current:** Using write-without-response (lowest latency mode)
   - **Fallback:** Reduce update rate to 20Hz, increase smoothing

3. **Motor too weak for steering**
   - **Fix:** Increase PWM duty cycle in ESP32
   - **Fallback:** Use haptics + voice only

4. **Battery life insufficient for demo**
   - **Target:** 2+ hours (sufficient for hackathon)
   - **Optimization:** Reduce ARKit frame rate to 30fps if needed

5. **Obstacle detection in complex environments**
   - **Simplification:** Focus on walls/large objects first
   - **Phase 2:** Add object classification for better context

## Demo Script

1. **Show connection status** (green indicators)
2. **Walk toward wall** → System steers away
3. **Walk through doorway** → System finds center
4. **Approach obstacle from side** → Steers to clear space
5. **Show haptic feedback** → Pulse rate increases with proximity
6. **(Phase 2)** Voice announces object type
7. **(Phase 3)** Navigate to destination with GPS

## Performance Targets

- **ARKit Frame Rate:** 30-60 fps
- **Obstacle Detection:** 30 Hz
- **BLE Latency:** <20ms
- **End-to-end Latency:** <50ms (sensor → motor)
- **Battery Life:** 2+ hours
- **Detection Range:** 0.3m - 1.5m

## Development Timeline (36 hours)

- **Hour 0-4:** Hardware assembly + basic BLE test
- **Hour 4-12:** Core obstacle detection + steering (Phase 1)
- **Hour 12-16:** Integration testing + tuning
- **Hour 16-20:** Haptics + voice output (Phase 1 complete)
- **Hour 20-28:** Object recognition (Phase 2)
- **Hour 28-36:** GPS navigation (Phase 3) OR polish + demo prep

## Code Style & Best Practices

- Heavy comments for hackathon clarity
- Modular architecture (easy to swap components)
- Safety timeouts on motor control
- Auto-reconnect for BLE
- Extensive debug logging
- UI shows all live data for demos

## Future Enhancements (Post-Hackathon)

- Machine learning for terrain classification
- Multi-cane collaboration (detect other cane users)
- Cloud sync for learned routes
- Integration with smart home devices
- Curb detection and stair warning
- Indoor positioning (iBeacons)

## License

MIT License - Hackathon project for demonstration purposes

## Contributors

Built during 36-hour hackathon
- iOS Development: Swift 6.2 + ARKit
- Embedded Systems: Arduino ESP32
- Hardware Integration: GoBilda motors

---

**Last Updated:** February 2026
**Status:** Phase 1 Complete ✅ | Phase 2 In Progress 🚧
