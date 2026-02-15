# Quick Start Guide

**Get your Smart Cane MVP running in under 1 hour**

## Prerequisites

- Mac with Xcode 26.2 installed
- iPhone 14 Pro Max (or any iPhone with LiDAR)
- Arduino IDE 2.x installed
- Hardware components assembled (see [Hardware/Assembly Instructions.md](Hardware/Assembly%20Instructions.md))

## Part 1: Create iOS Project (15 minutes)

Since Xcode project files are complex, follow these steps to create the project:

### 1. Create New Project

```bash
# Open Xcode
open -a Xcode
```

1. File → New → Project
2. Choose "iOS" → "App"
3. Click "Next"
4. Configure:
   - Product Name: `SmartCane`
   - Team: Your development team
   - Organization Identifier: `com.yourname`
   - Interface: SwiftUI
   - Language: Swift
   - Storage: None
   - Include Tests: No
5. Save to: `/Users/tonywang/raising-canes/SmartCane`

### 2. Add Source Files

Copy all the Swift files from the generated code:

```bash
cd /Users/tonywang/raising-canes/SmartCane/SmartCane

# The following files should already exist:
# - SmartCaneApp.swift
# - ContentView.swift
# - Core/SmartCaneController.swift
# - Sensors/DepthSensor.swift
# - Navigation/ObstacleDetector.swift
# - Navigation/SteeringEngine.swift
# - Communication/BLEManager.swift
# - Feedback/HapticManager.swift
# - Feedback/VoiceManager.swift
```

In Xcode:
1. Right-click "SmartCane" folder in project navigator
2. New Group → Name it "Core"
3. Drag `SmartCaneController.swift` into Core group
4. Repeat for "Sensors", "Navigation", "Communication", "Feedback" groups

### 3. Configure Info.plist

The Info.plist file is already created with all required permissions.

### 4. Add Frameworks

1. Select project in navigator
2. Select "SmartCane" target
3. "Frameworks, Libraries, and Embedded Content"
4. Click "+" and add:
   - ARKit.framework
   - CoreBluetooth.framework
   - AVFoundation.framework
   - Speech.framework
   - CoreHaptics.framework
   - CoreLocation.framework
   - MapKit.framework (for Phase 3)

### 5. Build Settings

1. Select project → SmartCane target
2. Build Settings tab
3. Search for "deployment target"
4. Set iOS Deployment Target to 17.0

### 6. Connect iPhone

1. Connect iPhone 14 Pro Max via USB
2. Trust computer on iPhone
3. In Xcode: Select your iPhone as build target
4. Product → Run (⌘R)

The app should build and launch on your iPhone.

## Part 2: Program ESP32 (10 minutes)

### 1. Install ESP32 Support

1. Open Arduino IDE
2. File → Preferences
3. Additional Board Manager URLs:
   ```
   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
   ```
4. Tools → Board → Boards Manager
5. Search "esp32"
6. Install "esp32 by Espressif Systems"

### 2. Configure Board

1. Tools → Board → ESP32 Arduino → "XIAO_ESP32S3"
2. Tools → Port → Select your ESP32 port
3. Tools → Upload Speed → "921600"

### 3. Upload Code

1. Open: `/Users/tonywang/raising-canes/ESP32/SmartCane_ESP32/SmartCane_ESP32.ino`
2. Click "Upload" button (→)
3. Wait for "Done uploading"
4. Open Serial Monitor (Tools → Serial Monitor)
5. Set baud rate to 115200
6. You should see:
   ```
   =================================
   Smart Cane ESP32-S3 Starting...
   =================================
   [BLE] Advertising started - waiting for connection...
   ```

## Part 3: Test Connection (5 minutes)

### 1. Power On ESP32

- Disconnect USB
- Connect battery pack
- Power switch ON
- LED should blink slowly

### 2. Launch iPhone App

- Open SmartCane app on iPhone
- You should see:
  - "Disconnected" → "Connected" (turns green)
  - "LiDAR Inactive" status
- Check ESP32 Serial Monitor:
  ```
  [BLE] Client connected
  ```

### 3. Start System

- Tap "Start System" in app
- "LiDAR Active" should turn green
- Point iPhone at a wall
- You should see:
  - Zone indicators change color (red/orange when close)
  - Steering command changes
- Check ESP32 Serial Monitor:
  ```
  [Motor] → LEFT
  [Motor] → NEUTRAL ←
  [Motor] RIGHT →
  ```

## Part 4: Test Motor (10 minutes)

### 1. Bench Test

**WITHOUT attaching to cane:**

1. Place ESP32 + motor assembly on table
2. Secure so it doesn't move
3. Power on
4. In iPhone app: Tap "Start System"
5. Point iPhone at wall on LEFT side
6. Motor should spin (steering RIGHT away from wall)
7. Point iPhone at wall on RIGHT side
8. Motor should spin opposite direction (steering LEFT)

### 2. Check Steering Direction

If motor spins wrong direction:

**Option A (Hardware):**
```
Swap motor wires on L298N:
OUT1 ↔ OUT2
```

**Option B (Software - ESP32 code):**
```cpp
// In SmartCane_ESP32.ino, swap these two:
#define MOTOR_PIN_LEFT  D1  // Was D0
#define MOTOR_PIN_RIGHT D0  // Was D1
```

### 3. Adjust Motor Speed

If motor too weak/strong, edit ESP32 code:

```cpp
#define MOTOR_SPEED_GENTLE   120    // Increase for stronger steering
```

Re-upload to ESP32.

## Part 5: Full System Test (20 minutes)

### 1. Mount to Cane

- Follow [Hardware/Assembly Instructions.md](Hardware/Assembly%20Instructions.md) for mechanical assembly
- Ensure omni wheel contacts ground lightly
- iPhone mounted securely at handle

### 2. Indoor Test

**Test in safe open area first (hallway, large room):**

1. Hold cane at normal walking angle (~60°)
2. iPhone screen visible for monitoring
3. Start system
4. Walk toward wall slowly
5. You should feel lateral pressure on cane handle
6. Cane should gently guide you away from wall

### 3. Fine-Tune Wheel Position

- **Too much force?** Raise motor mount (less ground contact)
- **Too little force?** Lower motor mount (more ground contact)
- **Inconsistent?** Check wheel rotates freely

### 4. Test Scenarios

✅ **Walk toward wall**
- System should steer away
- Haptic pulses increase as you approach
- At ~0.5m, steering becomes aggressive

✅ **Walk through doorway**
- System should steer toward center
- Should avoid both sides

✅ **Obstacle on left**
- System should steer right
- Left zone indicator turns red/orange

✅ **Obstacle on right**
- System should steer left
- Right zone indicator turns red/orange

✅ **Clear path**
- Steering should be neutral
- All zone indicators green
- No lateral force on cane

## Troubleshooting

### App won't build in Xcode

**Error: "Developer Mode disabled"**
- Settings → Privacy & Security → Developer Mode → ON
- Restart iPhone

**Error: "Code signing"**
- Xcode → Project → Signing & Capabilities
- Check "Automatically manage signing"
- Select your team

**Error: "Framework not found"**
- Check all frameworks added (see Part 1, Step 4)

### ESP32 won't upload

**Error: "Port not found"**
- Install CP210x driver (for XIAO ESP32-S3)
- Restart Arduino IDE

**Error: "Upload failed"**
- Hold BOOT button while clicking Upload
- Release after "Connecting..."

### BLE won't connect

**iPhone can't find ESP32:**
- Check ESP32 Serial Monitor shows "Advertising started"
- Settings → Bluetooth → ON
- Force quit and restart SmartCane app
- Power cycle ESP32

**Connects then immediately disconnects:**
- Check battery voltage (should be >6.5V)
- Check ESP32 not crashing (Serial Monitor)

### LiDAR not working

**All zones show "--":**
- Settings → SmartCane → Camera → Allow
- Grant camera permission when prompted
- Clean LiDAR sensor (next to cameras)

**Zones don't update:**
- Check "LiDAR Active" is green
- Walk closer to obstacles (needs <1.5m range)
- Point iPhone forward (not down)

### Motor problems

**Motor doesn't spin:**
1. Check battery connected and charged
2. Verify L298N power LED is ON
3. Check motor connections (no loose wires)
4. Test motor directly with battery

**Motor spins continuously:**
- ESP32 probably not receiving BLE commands
- Check Serial Monitor for command logs
- Verify BLE connected
- Check 500ms timeout working (should auto-stop)

**Motor spins wrong direction:**
- See Part 4, Step 2 (swap wires or pins)

**Motor too weak:**
- Increase `MOTOR_SPEED_GENTLE` in ESP32 code
- Check battery voltage (weak battery = weak motor)
- Verify motor not stalled/blocked

## Performance Benchmarks

After setup, you should see:

| Metric | Target | How to Check |
|--------|--------|--------------|
| BLE Latency | <20ms | iPhone app displays latency |
| ARKit Frame Rate | 30-60 fps | Should feel responsive |
| Steering Response | <100ms | Subjective feel while walking |
| Battery Life | 2+ hours | Test runtime |
| Detection Range | 0.3-1.5m | Test with measuring tape |

## Next Steps

Once basic system works:

1. **Tune parameters** (see README.md)
   - Adjust obstacle thresholds
   - Adjust motor speeds
   - Adjust haptic intensity

2. **Implement Phase 2** (object recognition)
   - See PHASE2_GUIDE.md
   - Adds voice announcements

3. **Test in various environments**
   - Different lighting conditions
   - Various obstacle types
   - Indoor vs outdoor

4. **Practice demo**
   - Prepare talking points
   - Have backup cane ready
   - Charge all batteries

## Getting Help

### Serial Monitor Debug Output

**ESP32 (115200 baud):**
```
[BLE] Advertising started
[BLE] Client connected
[Motor] → LEFT / → NEUTRAL ← / RIGHT →
[Haptic] Pulse: 180
```

**Xcode Console (iPhone):**
```
[Controller] Initializing Smart Cane System...
[DepthSensor] ARKit configured for LiDAR at 60fps
[BLE] Scanning for Smart Cane ESP32...
[BLE] Connected to SmartCane
[Controller] Frame processed in 12.34ms
```

### Test Points

**Electrical:**
- Battery voltage: 7.4V ±0.5V
- ESP32 power: 3.3V or 5V
- Motor driver 5V out: ~5V (for powering ESP32)

**Mechanical:**
- Wheel rotates freely (no binding)
- Wheel contacts ground when cane tilted 60°
- Motor has visible torque (can't stop with finger)

## Quick Reference

**BLE UUIDs:**
- Service: `4fafc201-1fb5-459e-8fcc-c5c9c331914b`
- Steering: `beb5483e-36e1-4688-b7f5-ea07361b26a8`
- Haptic: `beb5483e-36e1-4688-b7f5-ea07361b26a9`

**Pin Configuration:**
- D0 → Motor Left
- D1 → Motor Right
- D2 → Motor Enable (PWM)
- D3 → Haptic Motor

**Power Requirements:**
- ESP32: 3.3V / 200mA
- Motor: 6-12V / 1.5A peak
- Battery: 7.4V 2S LiPo recommended

---

**Total Setup Time:** ~1 hour first time, ~15 minutes after
**Difficulty:** Intermediate (hardware + software)
**Success Rate:** High (if hardware assembled correctly)
