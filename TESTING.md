# Testing & Validation Guide

**Comprehensive testing procedures for hackathon demo readiness**

## Test Strategy

The Smart Cane system has multiple subsystems that must work together. Test each subsystem independently before integration testing.

## Phase 1: Unit Tests

### 1.1 ESP32 Hardware Test

**Objective:** Verify ESP32 + motor driver + motor chain works

**Setup:**
- ESP32 powered via USB (no battery yet)
- Motor driver connected
- Motor connected
- Serial monitor open

**Test Steps:**

```cpp
// Add to setup() in ESP32 code temporarily:
void testMotor() {
    Serial.println("=== MOTOR TEST ===");

    Serial.println("Test 1: Motor LEFT");
    steerLeft(150);
    delay(2000);
    stopMotor();
    delay(1000);

    Serial.println("Test 2: Motor RIGHT");
    steerRight(150);
    delay(2000);
    stopMotor();
    delay(1000);

    Serial.println("Test 3: Speed ramp");
    for (int speed = 0; speed <= 255; speed += 25) {
        steerRight(speed);
        Serial.printf("Speed: %d\n", speed);
        delay(500);
    }
    stopMotor();

    Serial.println("=== TEST COMPLETE ===");
}
```

**Expected Results:**
- Motor spins left for 2 seconds
- Motor spins right for 2 seconds
- Motor speed increases gradually
- No burning smell, no overheating

**Pass Criteria:**
- ✅ Motor responds to all commands
- ✅ Direction changes correctly
- ✅ Speed control works
- ✅ No electrical issues

---

### 1.2 ESP32 BLE Test

**Objective:** Verify BLE advertising and connection

**Setup:**
- ESP32 powered on
- Serial monitor open
- iPhone Bluetooth ON
- Use LightBlue app (free iOS BLE scanner)

**Test Steps:**
1. Power on ESP32
2. Open LightBlue app on iPhone
3. Look for "SmartCane" in device list
4. Connect to SmartCane
5. View services
6. Find service `4fafc201-...`
7. Find characteristic `beb5483e-...-26a8` (steering)
8. Write hex value `01` (steer right)
9. Check serial monitor

**Expected Results:**
```
[BLE] Advertising started
[BLE] Client connected
[Motor] RIGHT →
```

**Pass Criteria:**
- ✅ Device shows up in LightBlue
- ✅ Can connect successfully
- ✅ Service and characteristics visible
- ✅ Writing to characteristic triggers motor
- ✅ Serial monitor logs commands

---

### 1.3 iPhone ARKit Test

**Objective:** Verify LiDAR depth sensing works

**Setup:**
- iPhone app built and running
- Camera permissions granted

**Test Method:**

Add temporary debug view to ContentView.swift:

```swift
// Add to ContentView body:
if let depthFrame = caneController.depthSensor?.latestDepthFrame {
    Text("Depth data active: \(depthFrame.timestamp)")
        .font(.caption)
}
```

**Test Steps:**
1. Launch app
2. Point at wall 1 meter away
3. Observe center distance reading
4. Move closer (0.5m)
5. Move farther (2m)
6. Point at different objects

**Expected Results:**
- Center distance shows ~1.0m
- Distance decreases when moving closer
- Distance increases when moving farther
- Updates in real-time (30-60 fps)

**Pass Criteria:**
- ✅ Depth values reasonable (0.3-1.5m range)
- ✅ Updates continuously
- ✅ Responds to movement
- ✅ No app crashes

---

### 1.4 iPhone Obstacle Detection Test

**Objective:** Verify zone-based obstacle detection

**Test Method:**

Add debug logging to ObstacleDetector.swift:

```swift
let zones = ObstacleZones(...)

print("[Zones] L:\(zones.leftDistance ?? -1) C:\(zones.centerDistance ?? -1) R:\(zones.rightDistance ?? -1)")

return zones
```

**Test Steps:**
1. Launch app, start system
2. Point at wall straight ahead
3. Check logs: center should have distance
4. Point at wall on left side
5. Check logs: left should have distance
6. Point at open space
7. Check logs: all should be nil or >1.5m

**Expected Results:**
```
[Zones] L:-1 C:0.8 R:-1       // Wall ahead
[Zones] L:0.5 C:-1 R:-1       // Wall on left
[Zones] L:-1 C:-1 R:-1        // Clear path
```

**Pass Criteria:**
- ✅ Zones correctly identify obstacle position
- ✅ Distance values accurate
- ✅ Clear paths show no obstacles

---

### 1.5 Steering Logic Test

**Objective:** Verify steering decisions make sense

**Test Method:**

Add to SteeringEngine.swift:

```swift
let decision = SteeringDecision(...)

print("[Steering] Command:\(decision.command) Reason:\(decision.reason)")

return decision
```

**Test Scenarios:**

| Scenario | L | C | R | Expected Command | Expected Reason |
|----------|---|---|---|-----------------|----------------|
| Wall ahead | - | 0.8 | - | -1 or +1 | Avoid center |
| Wall on left | 0.5 | - | - | +1 | Avoid left |
| Wall on right | - | - | 0.5 | -1 | Avoid right |
| Clear path | - | - | - | 0 | Clear path |
| Narrow gap | 1.0 | - | 1.2 | +1 | Prefer right (more space) |

**Pass Criteria:**
- ✅ All scenarios produce correct commands
- ✅ Reasons make sense
- ✅ Confidence values reasonable

---

## Phase 2: Integration Tests

### 2.1 End-to-End Latency Test

**Objective:** Measure total system latency

**Test Method:**

1. Add timestamp logging to pipeline
2. Measure from ARFrame → Motor command

```swift
// In SmartCaneController.swift:
let t0 = CFAbsoluteTimeGetCurrent()

// ... processing ...

let latency = (CFAbsoluteTimeGetCurrent() - t0) * 1000
print("[Latency] Total: \(latency)ms")
```

**Test Steps:**
1. Start system
2. Walk around for 30 seconds
3. Calculate average latency from logs
4. Check max latency

**Expected Results:**
- Average: 20-40ms
- Max: <80ms
- 95th percentile: <50ms

**Pass Criteria:**
- ✅ Average latency <50ms
- ✅ No latency spikes >100ms
- ✅ Feels responsive when walking

---

### 2.2 BLE Reliability Test

**Objective:** Verify stable BLE connection

**Test Method:**

```swift
// Track connection stats in BLEManager:
var totalPacketsSent = 0
var connectionDrops = 0
var lastConnectionTime: Date?

func sendSteeringCommand(_ command: Int8) {
    totalPacketsSent += 1
    // ... existing code ...
}
```

**Test Steps:**
1. Connect BLE
2. Run system for 5 minutes
3. Monitor serial output for disconnects
4. Count total packets sent

**Expected Results:**
- Packets sent: ~9000 (30 Hz × 300 seconds)
- Connection drops: 0
- No reconnection needed

**Pass Criteria:**
- ✅ Zero disconnections in 5 minute test
- ✅ Packet rate consistent (~30 Hz)
- ✅ No command loss (verified in serial logs)

---

### 2.3 Steering Response Test

**Objective:** Verify motor responds correctly to obstacles

**Test Setup:**
- Cane mounted with all hardware
- Phone secured to handle
- Motor can spin freely (not touching ground yet)

**Test Steps:**

| Action | Expected Motor Response | Verify in Serial |
|--------|------------------------|-----------------|
| Point at wall ahead | LEFT or RIGHT (whichever has more space) | `[Motor] ← LEFT` or `RIGHT →` |
| Point at open space | NEUTRAL | `[Motor] → NEUTRAL ←` |
| Point at wall on left | RIGHT | `[Motor] RIGHT →` |
| Point at wall on right | LEFT | `[Motor] ← LEFT` |
| Block center zone | Steer to clearer side | Command changes to open side |

**Pass Criteria:**
- ✅ Motor direction matches steering logic
- ✅ Response time <100ms (subjective)
- ✅ Serial logs match expected commands

---

### 2.4 Haptic Feedback Test

**Objective:** Verify haptic pulses match distance

**Test Method:**

Add logging to HapticManager:

```swift
func updateDistance(_ distance: Float) {
    print("[Haptic] Distance:\(distance) Interval:\(interval)")
    // ... existing code ...
}
```

**Test Steps:**
1. Start system
2. Walk toward wall slowly
3. Note haptic pulse rate at different distances
4. Should feel:
   - 1.5m: Slow pulse (~1 Hz)
   - 1.0m: Medium pulse (~3 Hz)
   - 0.5m: Fast pulse (~7 Hz)
   - 0.3m: Very fast pulse (~10 Hz)

**Pass Criteria:**
- ✅ Pulse rate increases as distance decreases
- ✅ Pulses stop when >1.5m away
- ✅ Pulses feel distinct (not continuous vibration)

---

## Phase 3: System Tests

### 3.1 Basic Navigation Test

**Objective:** Verify lateral steering works while walking

**Test Environment:** Indoor hallway with clear walls

**Test Steps:**
1. Stand at one end of hallway (center)
2. Start system
3. Walk forward slowly
4. Cane should remain centered
5. Drift slightly left
6. Cane should push back to center
7. Drift slightly right
8. Cane should push back to center

**Pass Criteria:**
- ✅ Cane provides lateral force when needed
- ✅ Force is gentle, not aggressive
- ✅ User can override force if desired
- ✅ Cane returns to neutral in open space

---

### 3.2 Obstacle Avoidance Test

**Test Scenarios:**

**A. Wall Approach**
1. Walk directly toward wall from 2m away
2. At ~1.2m, should feel steering force
3. At ~0.6m, force should increase
4. Stop at ~0.3m (or before collision)

**Pass Criteria:**
- ✅ Steering engages before collision
- ✅ Direction is away from wall
- ✅ Force proportional to distance

---

**B. Narrow Doorway**
1. Walk toward doorway (off-center)
2. Cane should guide toward center
3. Should thread through doorway
4. Steering disengages once through

**Pass Criteria:**
- ✅ Avoids both sides of doorway
- ✅ Finds center path
- ✅ Smooth transition

---

**C. Corner Navigation**
1. Walk along wall (wall on left)
2. Approach corner (ahead + left blocked)
3. Cane should steer right
4. Walk around corner

**Pass Criteria:**
- ✅ Detects corner as center + side obstacle
- ✅ Steers toward open side
- ✅ Allows user to turn

---

### 3.3 Multi-Obstacle Test

**Test Environment:** Room with chairs, tables, etc.

**Test Steps:**
1. Walk through cluttered environment
2. System should avoid multiple obstacles
3. Should not get "stuck" between obstacles

**Pass Criteria:**
- ✅ Detects various obstacle types
- ✅ Provides coherent steering guidance
- ✅ Doesn't oscillate between left/right
- ✅ User can make progress through space

---

### 3.4 Battery Endurance Test

**Objective:** Verify 2+ hour runtime

**Test Method:**
1. Fully charge battery
2. Power on system
3. Run continuously (walking or bench test)
4. Monitor battery voltage every 15 minutes
5. Record time until system fails

**Expected Results:**
- 7.4V LiPo 2500mAh: 2-3 hours
- Voltage drop: 8.4V → 6.0V (cutoff)

**Pass Criteria:**
- ✅ Minimum 2 hours runtime
- ✅ No brownouts or resets
- ✅ Motor maintains performance until battery depleted

---

## Phase 4: Environmental Tests

### 4.1 Lighting Conditions

Test in various lighting:

| Condition | LiDAR Expected | Notes |
|-----------|---------------|-------|
| Bright indoor | ✅ Works | Optimal |
| Dim indoor | ✅ Works | LiDAR not affected by light |
| Dark indoor | ✅ Works | LiDAR active sensing |
| Bright sunlight | ⚠️ May degrade | IR interference possible |
| Direct sunlight | ⚠️ May degrade | Test fallback behavior |

**Pass Criteria:**
- ✅ Works in all indoor conditions
- ⚠️ Acceptable degradation outdoors (hackathon MVP ok)

---

### 4.2 Surface Types

Test obstacle detection on:

| Surface | Detection Expected | Notes |
|---------|-------------------|-------|
| White wall | ✅ Excellent | High IR reflectance |
| Dark wall | ✅ Good | Some absorption |
| Glass window | ⚠️ Variable | May see through |
| Mirror | ❌ Poor | Specular reflection |
| Curtain | ⚠️ Variable | Soft material |

**Pass Criteria:**
- ✅ Reliably detects walls/doors
- ⚠️ Glass/mirrors acceptable limitation for MVP

---

### 4.3 Range Test

**Test Method:**

1. Position phone at exact distances from wall
2. Record detected distance
3. Calculate error

| Actual Distance | Measured Distance | Error |
|----------------|-------------------|-------|
| 0.3m | ? | ? |
| 0.5m | ? | ? |
| 1.0m | ? | ? |
| 1.5m | ? | ? |
| 2.0m | ? | ? |

**Pass Criteria:**
- ✅ Error <10% for distances 0.3-1.5m
- ⚠️ Acceptable error >1.5m (out of range)

---

## Phase 5: Demo Rehearsal

### 5.1 Demo Run-Through

**Objective:** Practice full demo script

**Setup:**
- Fully assembled system
- Batteries charged
- Test environment prepared
- Backup components ready

**Demo Script:**
1. **Introduction** (30 seconds)
   - Show system components
   - Explain lateral steering concept

2. **Connection Demo** (30 seconds)
   - Power on ESP32
   - Launch iPhone app
   - Show connection established

3. **Basic Avoidance** (1 minute)
   - Walk toward wall
   - Show steering engages
   - Show haptic feedback

4. **Doorway Navigation** (1 minute)
   - Walk through doorway
   - Show centering behavior

5. **UI Demo** (30 seconds)
   - Show live zone indicators
   - Show steering commands
   - Show latency metrics

6. **(Optional) Phase 2** (30 seconds)
   - Object recognition announcement

**Total Demo Time:** 3-4 minutes

**Pass Criteria:**
- ✅ No technical failures
- ✅ Clear demonstration of value
- ✅ All features work

---

### 5.2 Failure Mode Testing

**Objective:** Identify and prepare for potential demo failures

**Test Scenarios:**

**A. BLE Disconnects Mid-Demo**
- **Cause:** Interference, battery, range
- **Recovery:** Auto-reconnect (already implemented)
- **Backup:** Have spare ESP32 powered on

**B. iPhone App Crashes**
- **Cause:** Memory, ARKit failure
- **Recovery:** Force quit and restart (15 seconds)
- **Backup:** Have app pre-loaded on backup iPhone

**C. Motor Stops Working**
- **Cause:** Battery dead, driver failure, loose wire
- **Recovery:** Can't fix quickly
- **Backup:** Have backup cane fully assembled

**D. LiDAR Stops Working**
- **Cause:** App issue, permissions, ARKit crash
- **Recovery:** Restart app
- **Backup:** Have backup iPhone

**E. Battery Dies**
- **Cause:** Forgot to charge
- **Backup:** Have 2-3 charged batteries, labeled

**Pass Criteria:**
- ✅ Identified recovery for each failure
- ✅ Backup hardware available
- ✅ Can recover within 1 minute

---

## Testing Checklist

Before demo day:

### Day Before Demo
- [ ] Full battery endurance test (2+ hours)
- [ ] All unit tests passing
- [ ] Integration tests passing
- [ ] Demo rehearsal 3x with team
- [ ] Backup hardware tested and ready
- [ ] All batteries charged

### Demo Day Morning
- [ ] Charge all batteries to 100%
- [ ] Test primary system (full run-through)
- [ ] Test backup system (full run-through)
- [ ] Pack backup hardware
- [ ] Pack tools (screwdrivers, tape, zip ties)
- [ ] Label all components

### Pre-Demo (30 min before)
- [ ] Fresh battery in primary system
- [ ] Test BLE connection
- [ ] Test LiDAR
- [ ] Test motor
- [ ] Backup system powered and ready
- [ ] iPhone app pre-loaded (not suspended)

---

## Performance Metrics Summary

**Target Metrics (MVP):**

| Metric | Target | Stretch Goal |
|--------|--------|-------------|
| End-to-end latency | <50ms | <30ms |
| BLE latency | <20ms | <10ms |
| ARKit frame rate | 30 fps | 60 fps |
| Detection range | 0.3-1.5m | 0.2-2.0m |
| Detection accuracy | >90% | >95% |
| BLE reliability | 0 drops/5min | 0 drops/hour |
| Battery life | 2 hours | 4 hours |
| Steering response | <100ms | <50ms |

---

**Test Status:** Complete all Phase 1-3 tests before demo
**Last Updated:** February 2026
**Estimated Testing Time:** 4-6 hours total
