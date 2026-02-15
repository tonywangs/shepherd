# Shepherd

**An open-source, self-navigating smart white cane for the visually impaired.**

<p align="center">
  <img src="Hardware/CAD%20images/Screenshot%202026-02-15%20at%205.45.07%E2%80%AFAM.png" alt="Shepherd CAD render" width="600"/>
</p>

---

## The Problem

Over **253 million people** worldwide live with visual impairments. Many rely on guide dogs, AI glasses, or smart canes to navigate safely — but these tools are prohibitively expensive:

| Tool | Typical Cost |
|------|-------------|
| Smart canes (e.g. [WeWalk](https://wewalk.io/en/)) | $800 -- $1,150 |
| AI wearables (e.g. OrCam MyEye) | $2,000 -- $5,000 |
| Guide dogs | ~$50,000 (with multi-year waitlists) |

85--90% of people with visual impairments live in developing countries, where any of these costs can eclipse an annual salary. Global access to assistive navigation tools is **under 1%**.

Existing smart canes on the market rely on cloud-based AI (like GPT) for their intelligence — meaning they're subject to cellular connectivity, server latency (4-5 seconds per query), and subscription fees. That latency isn't just inconvenient; when you're approaching a crosswalk or a moving obstacle, it can be the difference between safety and harm.

## Our Solution

Shepherd is a smart cane that **physically guides you** around obstacles using a motorized omni wheel, with all processing done **on-device** on an iPhone. No cloud. No subscriptions. Response time is **under 100ms** — roughly 50x faster than cloud-based alternatives.

It costs a fraction of anything on the market, and we've open-sourced the CAD files, bill of materials, and assembly instructions so **anyone with a 3D printer and a soldering iron can build one**.

### Key Features

- **Physical steering guidance** — a motorized 3.25" omni wheel at the base pushes the cane laterally to steer you around obstacles. You walk forward; Shepherd handles the rest.
- **On-device AI** — LiDAR, camera, and IMU data are processed locally on the iPhone at 60 Hz. No internet required.
- **Object recognition** — identifies people, surfaces, signs, and obstacles using on-device computer vision.
- **GPS navigation** — voice-guided turn-by-turn directions with pedestrian-accessible routing.
- **Haptic feedback** — pulses faster as you approach obstacles, giving you constant spatial awareness.
- **Voice interface** — ask Shepherd where to go; it gives you spoken guidance along the way.
- **Charges your phone** — a built-in 12V-to-5V step-down powers your iPhone while you walk.

### Prior Work

Shepherd builds on research from Stanford's [Augmented Cane project](https://hai.stanford.edu/news/stanford-researchers-build-400-self-navigating-smart-cane) ([GitHub](https://github.com/pslade2/AugmentedCane)), which demonstrated the viability of omni-wheel steering for assistive navigation. We extend this concept with on-device AI, GPS navigation, object recognition, and a fully open-source hardware design.

---

## How It Works

### Architecture

```
iPhone (LiDAR + Camera + IMU + GPS)
  │
  ├─ 60 Hz depth capture (ARKit)
  ├─ LiDAR obstacle detection + camera-based object recognition
  ├─ Gap profiling & nonlinear steering transformation
  │
  └─ 10 Hz BLE (custom 12-byte protocol) ──► ESP32-S3
                                                │
                                        ┌───────┴───────┐
                                        │               │
                                   Motor Control    Haptic Engine
                                   (omni wheel)    (taptic pulses)
```

### Sensing & Steering Pipeline

1. **Depth capture** — ARKit captures LiDAR + camera depth at 60 Hz
2. **Obstacle detection** — zones are analyzed for no-go areas (walls, people, terrain, curbs)
3. **Gap profiling** — fast denoising to find the best clear path
4. **Steering computation** — nonlinear transformation converts obstacle data into a steering value
5. **BLE transmission** — a custom 12-byte protocol sends motor + haptic commands at 10 Hz
6. **Motor response** — the ESP32 uses a leaky integrator with exponential decay for smooth, safe motor output
7. **Safety** — if Bluetooth disconnects, the ESP32 auto-decays motor power to zero (no sudden jolts)

### Why On-Device?

As Saqib Shaikh (creator of Microsoft's Seeing AI) has noted, accessibility tech for the visually impaired benefits enormously from edge processing — users can't afford to wait for a cloud round-trip while navigating a crosswalk. Shepherd's core obstacle detection and steering runs entirely on the iPhone with **no network dependency**.

---

## Hardware

<p align="center">
  <img src="Hardware/CAD%20images/Screenshot%202026-02-15%20at%205.43.31%E2%80%AFAM.png" alt="Shepherd handle CAD" width="400"/>
  <img src="Hardware/CAD%20images/Screenshot%202026-02-15%20at%205.42.51%E2%80%AFAM.png" alt="Shepherd motor mount CAD" width="400"/>
</p>

The cane is built from 7 custom 3D-printed parts, a GoBilda 5203 Series 312 RPM motor, a 3.25" omni wheel, and a Seeed Studio XIAO ESP32-S3. The handle houses the electronics; the motor assembly clamps to the bottom of a 1.25" PVC pipe.

- **Full BOM and step-by-step assembly instructions:** [`Hardware/Assembly Instructions.md`](Hardware/Assembly%20Instructions.md)
- **CAD files (Onshape):** [View on Onshape](https://cad.onshape.com/documents/81a23f6a3ee770cabe38b40e/w/dbefee79fbdbd29cc2534d7b/e/bc9c36a15806c6943102f855?renderMode=0&uiState=6991caa73046b0bcd89e3977)
- **STL files for 3D printing:** [`Hardware/`](Hardware/)

---

## Getting Started

### Prerequisites

| Component | Requirement |
|-----------|-------------|
| iPhone | 14 Pro Max (or any iPhone with LiDAR), iOS 17.0+ |
| Mac | macOS with Xcode 26.2 installed |
| ESP32 | Seeed Studio XIAO ESP32-S3 |
| Arduino IDE | Version 2.x |
| Hardware | Fully assembled cane (see [Assembly Instructions](Hardware/Assembly%20Instructions.md)) |

### 1. Build the Hardware

Follow the [Hardware Assembly Instructions](Hardware/Assembly%20Instructions.md) to 3D-print, wire, and assemble the cane.

### 2. Flash the ESP32

1. **Install Arduino IDE** (version 2.x)

2. **Add ESP32 board support:**
   - Go to File → Preferences
   - Add this URL to "Additional Boards Manager URLs":
     ```
     https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
     ```
   - Go to Tools → Board → Boards Manager → search and install **esp32**

3. **Select the board:**
   - Tools → Board → ESP32 Arduino → **XIAO_ESP32S3**

4. **Open and upload the firmware:**
   ```bash
   # Open in Arduino IDE:
   ESP32/SmartCane_ESP32/SmartCane_ESP32.ino
   ```
   Click Upload.

5. **Verify it's working:**
   - Open Serial Monitor (115200 baud)
   - You should see: `Smart Cane ESP32-S3 Starting...` and `[BLE] Advertising started`
   - The onboard LED should blink slowly (advertising for a Bluetooth connection)

### 3. Build and Run the iOS App

1. **Open the Xcode project:**
   ```bash
   open SmartCane/SmartCane.xcodeproj
   ```

2. **Configure code signing:**
   - Select the SmartCane target
   - Under Signing & Capabilities, choose your development team
   - Update the bundle identifier if needed

3. **Build and run** on your iPhone (must be a physical device with LiDAR — the simulator won't work)

4. **Pair with the cane:**
   - The app will automatically discover the ESP32 over Bluetooth
   - The ESP32 LED will turn solid when connected
   - Press **Start System** in the app

### 4. Test

1. Walk toward a wall — the cane should steer you away
2. Haptic pulses should increase as you get closer to obstacles
3. Try voice commands to set a navigation destination

---

## Project Structure

```
├── SmartCane/                      # iOS App (Swift 6.2, Xcode 26.2)
│   └── SmartCane/
│       ├── SmartCaneApp.swift              # App entry point
│       ├── ContentView.swift               # Main UI
│       ├── Core/
│       │   └── SmartCaneController.swift   # Central coordinator
│       ├── Sensors/
│       │   └── DepthSensor.swift           # ARKit + LiDAR depth capture
│       ├── Navigation/
│       │   ├── ObstacleDetector.swift      # Zone-based obstacle analysis
│       │   ├── SteeringEngine.swift        # Lateral steering logic
│       │   ├── SurfaceClassifier.swift     # Terrain classification
│       │   ├── NavigationManager.swift     # GPS route management
│       │   ├── NavigationSteering.swift    # Route-following steering
│       │   └── RouteService.swift          # Routing API integration
│       ├── Vision/
│       │   ├── ObjectRecognizer.swift      # On-device object detection
│       │   └── DepthVisualizer.swift       # Depth map visualization
│       ├── Communication/
│       │   └── ESPBluetoothManager.swift   # BLE (custom 12-byte protocol)
│       ├── Feedback/
│       │   ├── HapticManager.swift         # Distance-based haptic pulses
│       │   └── VoiceManager.swift          # Speech output
│       ├── Voice/
│       │   └── VapiManager.swift           # Voice assistant integration
│       └── Input/
│           └── GameControllerManager.swift # Joy-Con steering override
│
├── ESP32/                          # ESP32 Firmware (Arduino)
│   └── SmartCane_ESP32/
│       └── SmartCane_ESP32.ino             # Motor control + BLE bridge
│
└── Hardware/                       # Hardware Design
    ├── Assembly Instructions.md            # BOM + build guide
    ├── CAD images/                         # Render screenshots
    └── *.stl                               # 3D-printable parts
```

## ESP32 Pin Configuration

```
D0  →  Motor Left Direction
D1  →  Motor Right Direction
D2  →  Motor Enable (PWM speed control)
D3  →  Haptic Motor (Taptic Engine)
LED →  Status indicator (blink = advertising, solid = connected)
```

---

## Roadmap

- [x] LiDAR depth sensing + obstacle detection (ARKit, 60 Hz)
- [x] Lateral omni-wheel steering with nonlinear control
- [x] Ultra-low-latency BLE (custom 12-byte protocol, 10 Hz)
- [x] Distance-based haptic feedback
- [x] On-device object recognition (people, surfaces, terrain)
- [x] GPS navigation with pedestrian-accessible routing
- [x] Voice interface (commands + spoken guidance)
- [x] Joy-Con steering override (for testing/demos)
- [ ] Sign reading and traffic signal detection
- [ ] Moving obstacle prediction and avoidance
- [ ] Indoor positioning and mapping

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| iPhone can't find ESP32 | Check Serial Monitor shows "Advertising started". Restart Bluetooth on iPhone. Power cycle ESP32. |
| BLE connected but motor doesn't move | Check motor driver power supply and pin connections. Check Serial Monitor for motor commands. |
| Sluggish steering response (>50ms) | Move phone closer to ESP32. Reduce WiFi interference. Verify BLE uses write-without-response. |
| No LiDAR depth data | Confirm device has LiDAR (iPhone 14 Pro or later). Check camera permissions. Clean sensor. |
| Weak or no haptic feedback | Check taptic engine wiring to D3. Test with different PWM values. |

---

## License

MIT License

---

**Built at Stanford TreeHacks 2026**
