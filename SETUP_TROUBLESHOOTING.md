# Smart Cane iOS App - Setup & Troubleshooting Guide

**Complete walkthrough of Xcode project setup and all errors encountered**

---

## Table of Contents
1. [Initial Problem: Project Won't Open](#initial-problem-project-wont-open)
2. [Creating Xcode Project from Scratch](#creating-xcode-project-from-scratch)
3. [Build Errors & Fixes](#build-errors--fixes)
4. [Runtime Crashes & Fixes](#runtime-crashes--fixes)
5. [Final Working Configuration](#final-working-configuration)

---

## Initial Problem: Project Won't Open

### Error
```
Failed to load project at '/Users/shanemion/TreeHacks2026/raising-canes/SmartCane/SmartCane.xcodeproj'
for an unknown reason.
```

### Root Cause
The repository contained Swift source files but had an empty/stub `project.pbxproj` file (only 173 bytes). The Xcode project structure existed but wasn't functional.

**Investigation:**
```bash
ls -la SmartCane/SmartCane.xcodeproj/
# Output: project.pbxproj was only 173 bytes (should be several KB)

cat SmartCane/SmartCane.xcodeproj/project.pbxproj
# Output: Just a stub with no real project structure
```

### Solution
Create a new Xcode project from scratch and add the existing source files.

---

## Creating Xcode Project from Scratch

### Step 1: Rename Existing Folder
```bash
cd /Users/shanemion/TreeHacks2026/raising-canes
mv SmartCane SmartCane_Source
```

**Why:** Prevent file conflict when Xcode creates the new project folder.

---

### Step 2: Create New Xcode Project

1. Open Xcode
2. **File → New → Project**
3. Choose **iOS → App**
4. Configure:
   - **Product Name:** SmartCane
   - **Team:** Your development team
   - **Organization Identifier:** com.yourname
   - **Interface:** SwiftUI
   - **Language:** Swift
   - **Storage:** None
   - **Include Tests:** Uncheck both boxes
5. **Save to:** `/Users/shanemion/TreeHacks2026/raising-canes/`

---

### Step 3: Add Source Files to Project

1. Delete auto-generated files:
   - Right-click `ContentView.swift` → Delete → Move to Trash
   - Right-click `SmartCaneApp.swift` → Delete → Move to Trash

2. Add existing source files:
   - Right-click "SmartCane" folder in Project Navigator
   - **Add Files to "SmartCane"...**
   - Navigate to `/Users/shanemion/TreeHacks2026/raising-canes/SmartCane_Source/SmartCane/`
   - Select **ALL** Swift files and folders
   - **Important options:**
     - ✅ **Copy items if needed**
     - ✅ **Create groups** (not folder references)
     - ✅ **Add to targets: SmartCane**
   - Click **Add**

---

### Step 4: Add Required Frameworks

1. Select **SmartCane project** in navigator
2. Select **SmartCane target**
3. Go to **"Frameworks, Libraries, and Embedded Content"** tab
4. Click **"+"** and add:
   - `ARKit.framework`
   - `CoreBluetooth.framework`
   - `AVFoundation.framework`
   - `Speech.framework`
   - `CoreHaptics.framework`
   - `CoreLocation.framework`
   - `MapKit.framework`

---

### Step 5: Configure Build Settings

1. Select project → SmartCane target
2. **Build Settings** tab
3. Search for **"deployment"**
4. Set **iOS Deployment Target** to **17.0**

---

## Build Errors & Fixes

### Error 1: Multiple Info.plist Conflict

**Error Message:**
```
Multiple commands produce '/Users/shanemion/Library/Developer/Xcode/DerivedData/SmartCane-.../Info.plist'
```

**Root Cause:**
- Info.plist file was included in source files
- Xcode also tries to auto-generate Info.plist
- Both try to copy to the same location → conflict

**Fix:**
1. Select SmartCane target
2. Go to **Build Phases** tab
3. Expand **"Copy Bundle Resources"**
4. Find `Info.plist` in the list
5. Select it and click **"-"** (minus) button to remove

Modern Xcode projects don't need a separate Info.plist file.

---

### Error 2: Missing `import Combine`

**Error Messages:**
```
HapticManager.swift:12:7 Type 'HapticManager' does not conform to protocol 'ObservableObject'
VoiceManager.swift:12:7 Type 'VoiceManager' does not conform to protocol 'ObservableObject'
VoiceManager.swift:19:6 Initializer 'init(wrappedValue:)' is not available due to missing import of defining module 'Combine'
ObjectRecognizer.swift:14:7 Type 'ObjectRecognizer' does not conform to protocol 'ObservableObject'
```

**Root Cause:**
Files using `@Published` and `ObservableObject` need to import the Combine framework.

**Fix:**
Add `import Combine` to these files:

**HapticManager.swift:**
```swift
import Foundation
import CoreHaptics
import Combine  // ← ADD THIS
```

**VoiceManager.swift:**
```swift
import Foundation
import AVFoundation
import Speech
import Combine  // ← ADD THIS
```

**ObjectRecognizer.swift:**
```swift
import Foundation
import Vision
import CoreImage
import AVFoundation
import Combine  // ← ADD THIS
```

---

## Runtime Crashes & Fixes

### Error 3: Privacy Permissions Crash

**Error Message:**
```
This app has crashed because it attempted to access privacy-sensitive data without a usage description.
The app's Info.plist must contain an NSSpeechRecognitionUsageDescription key with a string value
explaining to the user how the app uses this data.
```

**Root Cause:**
iOS requires explicit permission descriptions for accessing:
- Camera (for LiDAR)
- Bluetooth (for ESP32 communication)
- Microphone (for voice input)
- Speech Recognition (for voice commands)

**Fix:**
Add privacy keys to the project:

1. Select **SmartCane target**
2. Go to **"Info"** tab
3. Find **"Custom iOS Target Properties"**
4. Right-click on any existing row → **"Add Row"**
5. Add these keys (one at a time):

| Key | Value |
|-----|-------|
| `Privacy - Camera Usage Description` | `We need camera access for LiDAR depth sensing to detect obstacles.` |
| `Privacy - Bluetooth Always Usage Description` | `We need Bluetooth to communicate with the Smart Cane motor controller.` |
| `Privacy - Microphone Usage Description` | `We need microphone access for voice commands.` |
| `Privacy - Speech Recognition Usage Description` | `We need speech recognition for voice control features.` |
| `Privacy - Location When In Use Usage Description` | `We need location access for GPS navigation guidance.` |

**Alternative:** Use raw key names if auto-complete doesn't work:
- `NSCameraUsageDescription`
- `NSBluetoothAlwaysUsageDescription`
- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`
- `NSLocationWhenInUseUsageDescription`

---

### Error 4: Black Screen - VoiceManager Initialization Crash

**Symptoms:**
- App builds successfully
- App launches but shows black/blank screen
- No UI renders at all
- Console shows initialization stops after HapticManager

**Console Output:**
```
[ContentView] View appeared, initializing controller...
[Controller] Initializing Smart Cane System...
[Controller] Core systems initialized
(Fig) signalled err=-12710 at <>:601
[DepthSensor] ARKit configured for LiDAR at 60fps
[Controller] DepthSensor initialized
[Controller] BLEManager initialized
[Controller] HapticManager initialized
← STOPS HERE, never reaches VoiceManager
```

**Root Cause:**
`VoiceManager` initialization was crashing silently, preventing the entire app from rendering.

**Diagnostic Process:**

1. **Test with minimal UI** - Created ultra-simple ContentView with no controller:
```swift
struct ContentView: View {
    var body: some View {
        Color.red.ignoresSafeArea()  // Just a red screen
        Text("Test")
    }
}
```
Result: Red screen showed → UI rendering works, controller is the problem.

2. **Progressive initialization** - Added logging to each subsystem initialization:
```swift
func initialize() {
    obstacleDetector = ObstacleDetector()
    print("[Controller] ObstacleDetector initialized")  // ✓

    steeringEngine = SteeringEngine()
    print("[Controller] SteeringEngine initialized")    // ✓

    depthSensor = DepthSensor()
    print("[Controller] DepthSensor initialized")       // ✓

    bleManager = BLEManager()
    print("[Controller] BLEManager initialized")        // ✓

    hapticManager = HapticManager()
    print("[Controller] HapticManager initialized")     // ✓

    voiceManager = VoiceManager()
    print("[Controller] VoiceManager initialized")      // ✗ NEVER PRINTED
}
```

3. **Identified culprit** - VoiceManager was crashing during initialization.

**Fix:**
Temporarily disable VoiceManager initialization:

**SmartCaneController.swift:**
```swift
func initialize() {
    print("[Controller] Initializing Smart Cane System...")

    // Initialize simple subsystems first (no hardware dependencies)
    obstacleDetector = ObstacleDetector()
    steeringEngine = SteeringEngine()
    print("[Controller] Core systems initialized")

    // Initialize hardware subsystems
    depthSensor = DepthSensor()
    print("[Controller] DepthSensor initialized")

    bleManager = BLEManager()
    print("[Controller] BLEManager initialized")

    hapticManager = HapticManager()
    print("[Controller] HapticManager initialized")

    // TEMPORARY: VoiceManager disabled due to initialization crash
    // voiceManager = VoiceManager()
    print("[Controller] VoiceManager SKIPPED (temporarily disabled)")

    setupDataPipeline()
    print("[Controller] System initialized. Ready to start.")
}
```

Update methods that use VoiceManager:
```swift
private func startSystem() {
    depthSensor?.start()
    isARRunning = true
    bleManager?.startScanning()
    hapticManager?.initialize()

    // Safe voice announcement
    if voiceManager != nil {
        voiceManager?.speak("Smart cane activated")
    } else {
        print("[Controller] Voice announcement skipped (VoiceManager disabled)")
    }
}

func testVoice() {
    if voiceManager != nil {
        voiceManager?.speak("Voice system working correctly")
    } else {
        print("[Controller] Voice test skipped (VoiceManager disabled)")
    }
}
```

---

## Final Working Configuration

### Working Features ✅
- ✅ LiDAR depth sensing (ARKit)
- ✅ 3-zone obstacle detection (Left/Center/Right)
- ✅ Steering command logic
- ✅ Distance measurements in meters
- ✅ Haptic feedback (vibration pulses)
- ✅ BLE scanning (for ESP32 connection)
- ✅ Full SwiftUI interface

### Temporarily Disabled ⚠️
- ⚠️ Voice announcements (VoiceManager causes crash)
  - Can be tested later after investigating audio session conflicts
  - Not critical for core obstacle avoidance functionality

### Still Missing (Hardware Required) ❌
- ❌ BLE connection to ESP32 (shows "Disconnected" without hardware)
- ❌ Motor control testing (requires physical cane assembly)

---

## Testing the App (Without ESP32 Hardware)

### 1. Build and Run
```bash
# In Xcode
⌘R (or click Play button)
```

### 2. Grant Permissions
When app launches, grant permissions:
- **Camera** → Allow
- **Bluetooth** → Allow
- **Microphone** → Allow (even though voice is disabled)

### 3. Test LiDAR Obstacle Detection

**Step 1: Start System**
- Tap **"Start System"** button (turns red)
- LiDAR status turns **green** "LiDAR Active"

**Step 2: Point at Objects**
- Point iPhone at walls, furniture, objects
- Watch the distance values update:
  - **Left:** Distance to left side (in meters)
  - **Center:** Distance straight ahead
  - **Right:** Distance to right side

**Step 3: Observe Steering Commands**
The steering command will change based on obstacles:
- **"← LEFT"** → Obstacle on right, steer left
- **"→ NEUTRAL ←"** → Clear path, no steering
- **"RIGHT →"** → Obstacle on left, steer right

**Step 4: Feel Haptic Feedback**
- As you get closer to objects, vibration pulses get faster
- **Far (>1.5m):** No vibration
- **Medium (1.0-1.5m):** Slow pulses
- **Close (0.5-1.0m):** Medium pulses
- **Very Close (<0.5m):** Fast pulses

---

## Common Issues & Solutions

### Issue: "Developer Mode is not enabled"
**Solution:**
1. On iPhone: Settings → Privacy & Security → Developer Mode → ON
2. Restart iPhone
3. Try running again

### Issue: "No supported iOS devices available"
**Solution:**
Select an iOS Simulator from the device dropdown in Xcode toolbar.

### Issue: Simulator shows blank screen
**Cause:** Simulator doesn't have LiDAR hardware.
**Solution:** Use a physical iPhone 14 Pro (or newer) with LiDAR for full testing.

### Issue: Build succeeds but app crashes immediately
**Check:**
1. Xcode console for crash logs
2. Verify all privacy permissions are added to Info.plist
3. Check if initialization is completing (look for "[Controller] System initialized")

---

## Project File Structure (After Setup)

```
SmartCane/
├── SmartCane.xcodeproj/          # Xcode project (created fresh)
├── SmartCane/                     # Source code
│   ├── SmartCaneApp.swift        # App entry point
│   ├── ContentView.swift         # Main UI
│   ├── Core/
│   │   └── SmartCaneController.swift  # Main coordinator
│   ├── Sensors/
│   │   └── DepthSensor.swift     # ARKit + LiDAR
│   ├── Navigation/
│   │   ├── ObstacleDetector.swift
│   │   └── SteeringEngine.swift
│   ├── Communication/
│   │   └── BLEManager.swift      # Bluetooth
│   ├── Feedback/
│   │   ├── HapticManager.swift   # Vibration
│   │   └── VoiceManager.swift    # (Disabled)
│   └── Vision/
│       └── ObjectRecognizer.swift
```

---

## Next Steps

### To Re-enable Voice Manager
1. Investigate audio session configuration in `VoiceManager.swift`
2. Likely conflict with ARKit audio or app lifecycle
3. May need to delay voice initialization until after AR session starts

### To Connect ESP32 Hardware
1. Follow `QUICKSTART.md` Part 2 (ESP32 setup)
2. Upload firmware to ESP32
3. Power on ESP32
4. BLE status should change from red to green when connected

### To Add Camera Feed (Optional)
The attempt to add RealityKit ARView caused crashes. For camera preview:
- Use simpler `ARSCNView` instead of `ARView`
- Or use `AVCaptureVideoPreviewLayer`
- Not critical for functionality - obstacle detection works without camera view

---

## Summary of All Fixes

| # | Error | Fix |
|---|-------|-----|
| 1 | Project won't open | Create new Xcode project, add source files manually |
| 2 | Multiple Info.plist | Remove Info.plist from Copy Bundle Resources build phase |
| 3 | Missing Combine import | Add `import Combine` to HapticManager, VoiceManager, ObjectRecognizer |
| 4 | Privacy crash | Add 5 privacy usage descriptions to Info.plist |
| 5 | Black screen (VoiceManager) | Disable VoiceManager initialization, add nil checks |

---

## Conclusion

The app is now **fully functional** for testing obstacle detection without ESP32 hardware. All core navigation features work:
- Real-time LiDAR depth sensing
- 3-zone obstacle analysis
- Intelligent steering decisions
- Distance-based haptic feedback

Voice announcements can be re-enabled later after resolving audio session conflicts.

---

**Last Updated:** February 14, 2026
**Status:** ✅ Core functionality working | ⚠️ Voice disabled | ❌ ESP32 not connected
