# Shepherd

**An open-source, self-navigating smart white cane for the visually impaired.**

<p align="center">
  <img src="Hardware/CAD%20images/Screenshot%202026-02-15%20at%205.45.07%E2%80%AFAM.png" alt="Shepherd CAD render" width="600"/>
</p>

> **Demo Video:** *(Coming soon — showing obstacle avoidance, person detection, and GPS navigation in action)*

**Quick Stats:**
- 🚀 **<100ms latency** — 30-50× faster than cloud-based alternatives
- 💰 **~$50 to build** — 1/20th the cost of commercial smart canes
- 🔋 **4-6 hours battery** — charges your phone while you walk
- 🌐 **Fully open-source** — CAD, code, and assembly instructions

---

## Table of Contents

- [The Problem](#the-problem)
- [Our Solution](#our-solution)
- [How It Works](#how-it-works)
  - [Architecture](#architecture)
  - [Sensing & Steering Pipeline](#sensing--steering-pipeline)
  - [Technical Highlights: The Gap-Seeking Algorithm](#technical-highlights-the-gap-seeking-algorithm)
  - [AI Models & Frameworks](#ai-models--frameworks)
- [Hardware](#hardware)
- [Getting Started](#getting-started)
- [Project Structure](#project-structure)
- [Performance Metrics](#performance-metrics)
- [Roadmap](#roadmap)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Acknowledgments](#acknowledgments)
- [License](#license)

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
- **On-device AI** — LiDAR, camera, and IMU data are processed locally on the iPhone at 30-60 Hz using Apple's Vision framework and ARKit. No internet required for obstacle avoidance.
- **Gap-seeking steering algorithm** — instead of pushing away from obstacles (which causes overcorrection), Shepherd finds the direction of maximum clearance and steers you toward the safest path.
- **Object recognition** — identifies people, surfaces, signs, and obstacles using Apple's Vision framework (`VNDetectHumanRectanglesRequest`, `VNClassifyImageRequest`).
- **GPS navigation** — integrates Google Routes API and OpenRouteService API for turn-by-turn pedestrian routing with infrastructure warnings (crosswalks, traffic signals).
- **Voice assistant** — powered by Vapi, providing conversational guidance with real-time situational awareness of your surroundings.
- **Haptic feedback** — custom-built from recycled e-waste; pulses faster as you approach obstacles, giving you constant spatial awareness.
- **ARKit pose tracking** — 60 Hz heading updates from visual-inertial odometry, fused with compass for drift-resistant orientation.
- **Charges your phone** — a built-in 12V-to-5V step-down powers your iPhone while you walk.

### Prior Work

Shepherd builds on research from Stanford's [Augmented Cane project](https://hai.stanford.edu/news/stanford-researchers-build-400-self-navigating-smart-cane) ([GitHub](https://github.com/pslade2/AugmentedCane)), which demonstrated the viability of omni-wheel steering for assistive navigation. We extend this concept with on-device AI, GPS navigation, object recognition, and a fully open-source hardware design.

---

## How It Works

### Architecture

```
iPhone 14 Pro Max (LiDAR + Camera + IMU + GPS + Compass)
  │
  ├─ ARKit (30-60 Hz)
  │   ├─ LiDAR depth maps (sceneDepth)
  │   ├─ Camera RGB frames
  │   └─ Pose tracking (heading, position)
  │
  ├─ Vision Framework (~2 Hz)
  │   ├─ VNDetectHumanRectanglesRequest (person detection)
  │   └─ VNClassifyImageRequest (scene classification)
  │
  ├─ CoreLocation (1 Hz)
  │   ├─ GPS position
  │   └─ Magnetometer (compass heading)
  │
  ├─ Obstacle Detection & Steering
  │   ├─ Gap profiling (16-column depth analysis)
  │   ├─ Navigation bias (GPS bearing to next waypoint)
  │   └─ Merge: gapCommand + navBias × (1 - proximityFactor)
  │
  └─ BLE (10-20 Hz, custom 12-byte protocol) ──► ESP32-S3
                                                      │
                                              ┌───────┴────────┐
                                              │                │
                                         Motor Control    Haptic Engine
                                       (omni wheel PWM)  (taptic pulses)
                                              │                │
                                        Leaky Integrator   Distance-based
                                        (smooth accel)     (pulse freq)
```

### Sensing & Steering Pipeline

1. **Depth capture** — ARKit captures LiDAR depth maps at 30-60 Hz, along with camera RGB frames for object recognition
2. **Obstacle detection** — depth map is analyzed in left/center/right zones for obstacles, with vertical filtering to ignore ceiling/floor
3. **Person detection** — Vision framework (`VNDetectHumanRectanglesRequest`) runs at ~2 Hz, mapping bounding boxes to LiDAR depth for distance estimation
4. **Gap profiling** — the depth map is split into 16 vertical columns; average depth per column is computed and smoothed with a [0.25, 0.5, 0.25] kernel to find the direction of maximum clearance
5. **Steering computation** — `command = sqrt(|gapDirection|) × proximityFactor`, where `proximityFactor` ramps from 0 (clear) to 1 (obstacle <0.2m). This produces smooth, non-oscillating steering toward the safest path.
6. **Navigation merge (if active)** — GPS navigation bias is blended additively with obstacle avoidance, scaled by `(1 - proximityFactor)` so obstacles always take priority
7. **BLE transmission** — a custom 12-byte protocol sends `{speed, angle, distance, mode}` at 10-20 Hz over Bluetooth Low Energy (write-without-response for minimal latency)
8. **Motor response** — the ESP32 applies a leaky integrator (boat-like momentum model) for smooth acceleration/deceleration, preventing jarring movements
9. **Safety** — if Bluetooth disconnects, the ESP32 auto-decays motor power to zero over ~500ms (no sudden jolts)

### Why On-Device?

As Saqib Shaikh (creator of Microsoft's Seeing AI) has noted, accessibility tech for the visually impaired benefits enormously from edge processing — users can't afford to wait for a cloud round-trip while navigating a crosswalk. Shepherd's core obstacle detection and steering runs entirely on the iPhone with **no network dependency**.

### Technical Highlights: The Gap-Seeking Algorithm

Early prototypes used obstacle repulsion steering (push away from detected obstacles). This failed catastrophically at close range — approaching a trash can dead-center would cause violent oscillation as the system overcorrected left, then right, then left again.

**Our solution:** We replaced repulsive steering with gap-seeking. The algorithm:

1. Profiles the depth map across 16 vertical columns
2. Computes average depth per column (more depth = more clearance)
3. Applies a smoothing kernel to denoise the profile
4. Finds the direction of maximum clearance using argmax
5. Outputs a square-root-boosted command scaled by proximity factor

This eliminates overcorrection by always steering **toward safety** (the clearest path) rather than **away from danger**. Result: smooth, stable navigation even when obstacles are <1 meter away.

### AI Models & Frameworks

| Model/Framework | Purpose | Runs On |
|-----------------|---------|---------|
| ARKit Visual-Inertial SLAM | LiDAR depth sensing + camera pose tracking | iPhone (60 Hz) |
| `VNDetectHumanRectanglesRequest` | Person detection with bounding boxes | iPhone (Apple Vision) |
| `VNClassifyImageRequest` | Scene/object classification | iPhone (Apple Vision) |
| Vapi Voice Assistant | Conversational AI with real-time sensor context | Cloud (WebRTC) |
| Google Routes API | Pedestrian routing with step-by-step polylines | Cloud |
| OpenRouteService API | Alternative routing + accessibility data | Cloud |

All obstacle detection and steering computation runs **entirely on-device** with zero network dependency. GPS navigation and voice assistant require connectivity but are non-blocking — if offline, obstacle avoidance continues to function.

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

### 3. Configure API Keys

Create `SmartCane/SmartCane/Secrets.swift` with your API keys:

```swift
import Foundation

struct Secrets {
    static let googleAPIKey = "YOUR_GOOGLE_MAPS_API_KEY"
    static let openRouteServiceAPIKey = "YOUR_OPENROUTE_API_KEY"
    static let vapiPublicKey = "YOUR_VAPI_PUBLIC_KEY"
}
```

**API Key Sources:**
- **Google Maps API**: [Get key from Google Cloud Console](https://console.cloud.google.com/) (enable Geocoding API + Routes API)
- **OpenRouteService**: [Get free key from openrouteservice.org](https://openrouteservice.org/dev/#/signup)
- **Vapi**: [Get key from vapi.ai](https://vapi.ai/) (voice assistant platform)

**Note:** The app will build without these keys, but GPS navigation and voice assistant features will be disabled.

### 4. Build and Run the iOS App

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

### 5. Test Core Features

**Obstacle Avoidance:**
1. Walk toward a wall — the cane should smoothly steer you away
2. Walk between two obstacles (e.g., chairs) — the cane should find the "gap" and guide you through
3. Approach a person — you should hear "person detected at X meters" from the voice assistant

**Haptic Feedback:**
- As you approach obstacles, the handle should pulse faster
- At <1 meter, pulses should be rapid and intense

**GPS Navigation:**
1. Tap the navigation tab and enter a destination (e.g., "Main Quad, Stanford")
2. Start navigation — you should hear turn-by-turn voice guidance
3. Walk along the route — the cane should blend navigation bias with obstacle avoidance

**Voice Assistant (if configured):**
- Tap "Start Call" to activate Vapi
- Ask "Where am I?" or "Navigate to [destination]"
- The assistant should respond with context-aware guidance

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

## Performance Metrics

| Metric | Value | Notes |
|--------|-------|-------|
| **Obstacle detection latency** | <33ms | 30-60 Hz depth processing on iPhone |
| **BLE round-trip latency** | <100ms | Write-without-response + leaky integrator on ESP32 |
| **Person detection rate** | ~2 Hz | Throttled to balance accuracy and performance |
| **GPS navigation rate** | ~1 Hz | Standard for CoreLocation pedestrian mode |
| **Total reaction time** | <150ms | From obstacle detection to motor response |
| **Cost to build** | ~$40-60 | Excluding iPhone (BOM details in Hardware/) |
| **Battery life** | ~4-6 hours | Depends on motor usage intensity |

**Comparison:** Cloud-based AI glasses (e.g., Envision) have latency of 4-5 seconds per query. Shepherd's on-device processing is **~30-50× faster**.

---

## Roadmap

**Completed:**
- [x] LiDAR depth sensing + obstacle detection (ARKit, 30-60 Hz)
- [x] Gap-seeking steering algorithm (eliminates overcorrection)
- [x] Ultra-low-latency BLE (custom 12-byte protocol, 10-20 Hz)
- [x] Distance-based haptic feedback (recycled e-waste taptic engine)
- [x] On-device person detection (Vision framework, bounding box + depth)
- [x] On-device scene classification (Vision framework)
- [x] GPS navigation with pedestrian routing (Google Routes + OpenRouteService)
- [x] Voice assistant integration (Vapi, real-time sensor context)
- [x] Navigation-obstacle merge (GPS bias + gap-seeking)
- [x] ARKit pose tracking for heading (60 Hz visual-inertial odometry)
- [x] Joy-Con steering override (for testing/demos)

**In Progress:**
- [ ] Compass-ARKit fusion for drift-resistant heading
- [ ] Waypoint progression with perpendicular projection
- [ ] Sign reading (OCR) and traffic signal detection

**Future Work:**
- [ ] Moving obstacle prediction and trajectory forecasting
- [ ] Indoor positioning (UWB or visual SLAM)
- [ ] Semantic mapping (remember locations and landmarks)
- [ ] Multi-user obstacle sharing (crowd-sourced hazard map)

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| **iPhone can't find ESP32** | Check Serial Monitor shows "Advertising started". Restart Bluetooth on iPhone. Power cycle ESP32. Ensure ESP32 is within 1-2 meters. |
| **BLE connected but motor doesn't move** | Check motor driver power supply (12V) and H-bridge wiring. Open Serial Monitor and verify motor commands are being received. Test motor manually with Arduino digitalWrite. |
| **Motor oscillates or overcorrects** | This was fixed with the gap-seeking algorithm. If still occurring, check that you're running the latest code. Reduce `magnitude` in BluetoothPairingView to 1.5-2.0. |
| **Sluggish steering response** | Move phone closer to ESP32 (<1m). Reduce WiFi/Bluetooth interference. Verify BLE uses write-without-response (not write-with-response). Check that `block_until_ms` is not blocking. |
| **No LiDAR depth data** | Confirm device has LiDAR (iPhone 12 Pro or later). Check ARKit/Camera permissions in Settings. Clean the LiDAR sensor (small black dot near camera). Restart the app. |
| **Weak or no haptic feedback** | Check taptic motor wiring to D3. Verify 5V power supply to motor. Test with different PWM values in Serial Monitor. Try a different taptic motor (recycled from old phones). |
| **Person detection not working** | Verify Vision framework permissions. Check that `processDepthFrame` is being called (watch the console logs). Person detection is throttled to ~2 Hz to save battery. |
| **GPS navigation not starting** | Check that you've added API keys to `Secrets.swift`. Verify Location permissions are granted ("When In Use" or "Always"). Check internet connectivity. |
| **Voice assistant not responding** | Ensure Vapi API key is valid. Check microphone permissions. Verify internet connectivity. Try stopping and restarting the call. |
| **App crashes on launch** | Check that all dependencies are installed (Xcode may need to fetch Swift packages on first build). Clean build folder (Cmd+Shift+K) and rebuild. |

**Full troubleshooting guide:** See [`SETUP_TROUBLESHOOTING.md`](SETUP_TROUBLESHOOTING.md)

---

## Contributing

We welcome contributions! Areas where help is especially appreciated:

- **Hardware improvements** — lighter materials, better phone mounts, waterproofing
- **Algorithm refinement** — moving obstacle prediction, indoor positioning, terrain classification
- **Accessibility testing** — feedback from visually impaired users is invaluable
- **Localization** — translations and region-specific routing data
- **Documentation** — tutorials, videos, improved assembly instructions

**How to contribute:**
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## Acknowledgments

- **Stanford Augmented Cane** — [Original research project](https://github.com/pslade2/AugmentedCane) that pioneered omni-wheel steering for white canes
- **Apple** — ARKit and Vision framework make real-time on-device processing possible
- **Vapi** — Voice assistant platform with low-latency real-time context injection
- **TreeHacks 2026** — Stanford's premier hackathon, where Shepherd was built

Special thanks to the visually impaired community members who provided feedback and testing insights during development.

---

## License

MIT License — see [LICENSE](LICENSE) for details.

**Open-source hardware and software.** Build it, modify it, share it.

---

## Contact & Links

- **Project Homepage:** [github.com/yourusername/shepherd](https://github.com/yourusername/shepherd)
- **Demo Video:** *(Coming soon)*
- **CAD Files:** [View on Onshape](https://cad.onshape.com/documents/81a23f6a3ee770cabe38b40e/w/dbefee79fbdbd29cc2534d7b/e/bc9c36a15806c6943102f855?renderMode=0&uiState=6991caa73046b0bcd89e3977)
- **Devpost:** *(Add TreeHacks submission link)*

**Built at Stanford TreeHacks 2026** 🌲⚡

---

*"Technology should amplify human capability, not amplify cost."*
