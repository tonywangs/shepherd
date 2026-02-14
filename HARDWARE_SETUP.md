# Hardware Setup Guide

**Physical assembly and wiring for Smart Cane MVP**

## Bill of Materials

### Core Components

| Component | Quantity | Notes |
|-----------|----------|-------|
| iPhone 14 Pro Max | 1 | Or any iPhone with LiDAR |
| Seeed Studio XIAO ESP32-S3 | 1 | Main microcontroller |
| GoBilda 5203 Series 312 RPM Motor | 1 | 6V-12V DC motor |
| L298N H-Bridge Motor Driver | 1 | Or equivalent dual H-bridge |
| 3.25" Omni Wheel | 1 | Mounts to motor shaft |
| Haptic Vibration Motor | 1 | Standard 3V vibration motor |
| Battery Pack | 1 | 7.4V 2S LiPo or 8x AA holder |
| White Cane | 1 | Standard mobility cane |
| Phone Mount | 1 | Secure iPhone to cane handle |

### Wiring & Connectors

| Component | Quantity | Notes |
|-----------|----------|-------|
| Jumper wires | 20+ | Male-to-male and male-to-female |
| JST connectors | 4 | For motor and haptic connections |
| Heat shrink tubing | 1 pack | Wire insulation |
| Velcro straps | 3-4 | Secure components to cane |
| Zip ties | 10+ | Cable management |

### Mechanical

| Component | Quantity | Notes |
|-----------|----------|-------|
| Motor mount bracket | 1 | 3D printed or metal |
| ESP32 case | 1 | 3D printed or plastic enclosure |
| Breadboard (temporary) | 1 | For initial testing |
| Mounting hardware | 1 set | Screws, nuts, bolts |

## Wiring Diagram

```
[Battery Pack 7.4V]
    │
    ├──────────────────────┬────────── VCC
    │                      │
    │                      └────────── L298N (12V in)
    │                                       │
    │                                       ├─── Motor A+/A- → [GoBilda Motor]
    │                                       │
    │                                       ├─── IN1 ← ESP32 D0
    │                                       ├─── IN2 ← ESP32 D1
    │                                       └─── ENA ← ESP32 D2 (PWM)
    │
    ├──────────────────────┬────────── 3.3V Regulator
    │                      └────────── ESP32 (3.3V/5V)
    │                                       │
    │                                       ├─── D3 → [Haptic Motor] → GND
    │                                       └─── GND
    │
    └─────────────────────────────────── GND (Common Ground)
```

## Pin Assignments

### ESP32 XIAO

| Pin | Function | Connection | Notes |
|-----|----------|------------|-------|
| D0  | GPIO (Output) | L298N IN1 | Motor direction left |
| D1  | GPIO (Output) | L298N IN2 | Motor direction right |
| D2  | PWM (Output) | L298N ENA | Motor speed control |
| D3  | PWM (Output) | Haptic Motor + | Vibration control |
| GND | Ground | Common ground | Connect all grounds |
| 5V  | Power input | 5V from regulator | Or USB for testing |
| 3V3 | 3.3V output | Not used | Available if needed |

### L298N Motor Driver

| Pin | Connection | Notes |
|-----|------------|-------|
| 12V | Battery + (7.4V) | Accepts 5-35V |
| GND | Common ground | |
| 5V  | 5V regulator output | Can power ESP32 |
| ENA | ESP32 D2 (PWM) | Enable/speed motor A |
| IN1 | ESP32 D0 | Motor A direction 1 |
| IN2 | ESP32 D1 | Motor A direction 2 |
| OUT1 | Motor + (red) | Motor terminal A+ |
| OUT2 | Motor - (black) | Motor terminal A- |

### GoBilda Motor

| Wire | Connection | Notes |
|------|------------|-------|
| Red (+) | L298N OUT1 | Positive terminal |
| Black (-) | L298N OUT2 | Negative terminal |

### Haptic Motor

| Wire | Connection | Notes |
|------|------------|-------|
| Red (+) | ESP32 D3 | Via current-limiting resistor if needed |
| Black (-) | GND | Common ground |

## Assembly Steps

### 1. Mount ESP32 to Cane
- Place ESP32 in protective case
- Mount case to cane shaft ~6" below handle
- Use velcro strap for easy removal
- Ensure USB port is accessible for programming

### 2. Mount Motor Driver
- Mount L298N to cane shaft below ESP32
- Keep close to ESP32 (short wires)
- Use velcro or zip ties
- Ensure heat sinks have airflow

### 3. Mount Motor + Omni Wheel
- Attach motor bracket to cane shaft
- Position near bottom (12-18" from ground)
- Mount motor to bracket
- Attach omni wheel to motor shaft
- Ensure wheel rotates freely
- Wheel should press laterally against ground when cane is tilted

### 4. Mount Battery Pack
- Position battery pack on cane shaft
- Use velcro straps for easy removal/charging
- Keep battery accessible
- Add power switch on positive lead

### 5. Wiring - Power Distribution
```
Battery + ──[Switch]─┬─── L298N 12V input
                     └─── 3.3V Regulator ─── ESP32 VCC

Battery - ─────────────── Common GND
```

### 6. Wiring - Motor Control
```
L298N OUT1 ───── Motor Red
L298N OUT2 ───── Motor Black

ESP32 D0 ───── L298N IN1
ESP32 D1 ───── L298N IN2
ESP32 D2 ───── L298N ENA
```

### 7. Wiring - Haptic Motor
```
ESP32 D3 ───[Resistor 100Ω]─── Haptic Motor +
ESP32 GND ────────────────────── Haptic Motor -
```

### 8. Mount iPhone
- Attach phone mount to cane handle
- Position iPhone with camera/LiDAR facing forward
- Secure firmly (will experience vibration)
- Ensure screen is visible for debugging

### 9. Cable Management
- Route wires along cane shaft
- Use zip ties every 6-12"
- Keep wires away from omni wheel
- Leave slack for flexing/adjustment

## Power Requirements

### System Power Budget

| Component | Voltage | Current | Power |
|-----------|---------|---------|-------|
| ESP32-S3 | 3.3V | 200mA avg | 0.66W |
| GoBilda Motor | 7.4V | 1.5A peak | 11.1W |
| Haptic Motor | 3.3V | 100mA | 0.33W |
| **Total Peak** | 7.4V | ~2A | **~15W** |

### Battery Recommendations

**Option 1: 2S LiPo (Recommended)**
- Voltage: 7.4V nominal (6.0-8.4V range)
- Capacity: 2000-3000 mAh
- Runtime: 2-4 hours
- Weight: ~100g
- Pro: High power density, rechargeable
- Con: Requires LiPo charger, fragile

**Option 2: 8x AA Battery Pack**
- Voltage: 12V nominal (NiMH) or 12V (alkaline)
- Capacity: 2000-2500 mAh
- Runtime: 2-3 hours
- Weight: ~200g
- Pro: Easy to source, no charger needed
- Con: Heavier, disposable (or need NiMH)

**Option 3: USB Power Bank**
- Voltage: 5V (need boost converter for motor)
- Capacity: 10,000+ mAh
- Runtime: 6+ hours
- Weight: ~200g
- Pro: Easy to charge, high capacity
- Con: Need 5V → 12V boost converter

For hackathon: **Use 2S LiPo** (best power-to-weight).

## Mechanical Considerations

### Omni Wheel Positioning

The omni wheel is critical to the lateral steering mechanism.

**Correct Positioning:**
```
                    [iPhone]
                        │
    ┌───────────────────┼───────────────────┐
    │                   │                   │
    │               [Handle]                │
    │                   │                   │
    │              [ESP32]                  │
    │                   │                   │
    │         [Motor + Wheel] ←────── 12-18" from ground
    │                   │                   │
    │                   │                   │
    │              [Cane Tip]               │
    └───────────────────────────────────────┘

    Side view of wheel:

    [Cane shaft]
         ║
         ║
      [Motor]──┐
         ║     │
         ║  [Omni Wheel] ←── Rolls laterally (⟷)
         ║     │           ←── Should lightly touch ground
         ║     │               when cane is tilted
         ▼
      [Tip]
```

**Key Points:**
- Wheel should be 12-18" from ground
- When cane is held at ~60° angle (typical walking position), wheel should lightly contact ground
- Too much pressure → hard to walk
- Too little pressure → insufficient steering force
- Adjust by moving motor mount up/down cane shaft

### Steering Mechanics

When motor spins:
- **LEFT command:** Wheel rolls left → cane pushes user's hand left
- **RIGHT command:** Wheel rolls right → cane pushes user's hand right
- **NEUTRAL:** Wheel freewheels (minimal resistance)

The user MUST continue walking forward. The system only applies gentle lateral correction.

## Testing Checklist

### Electrical Tests (Before Assembly)

- [ ] Battery voltage correct (7.4V ±0.5V)
- [ ] ESP32 powers on (LED blinks)
- [ ] Motor spins in both directions (bench test)
- [ ] Haptic motor vibrates (bench test)
- [ ] All GND connections common
- [ ] No shorts (multimeter continuity test)

### Software Tests (After Programming)

- [ ] ESP32 advertises BLE ("SmartCane" visible)
- [ ] iPhone connects to ESP32
- [ ] Serial monitor shows steering commands
- [ ] Motor responds to commands (LEFT/RIGHT/STOP)
- [ ] Haptic motor triggers on command

### Mechanical Tests (After Assembly)

- [ ] Omni wheel rotates freely
- [ ] Wheel contacts ground at correct pressure
- [ ] Motor has sufficient torque for steering
- [ ] No rattling or loose components
- [ ] iPhone mount secure
- [ ] Cane still functions as normal cane (fallback)

### Integration Tests (Full System)

- [ ] Walk toward wall → cane steers away
- [ ] Walk through doorway → cane finds center
- [ ] Obstacle on left → cane steers right
- [ ] Obstacle on right → cane steers left
- [ ] Haptic pulses increase with proximity
- [ ] System runs for 30+ minutes without issues

## Safety Considerations

### Electrical Safety
- Use proper fuse on battery positive lead (3A fuse recommended)
- Ensure all connections insulated (heat shrink)
- Never short LiPo battery terminals
- Charge LiPo with proper charger (balance charging)

### Mechanical Safety
- Motor should NOT be strong enough to hurt user
- Emergency stop: Power switch easily accessible
- Wheel should freewheel if system fails
- Cane must remain functional as regular cane

### User Safety
- System is assistive only, not autonomous
- User maintains full control of movement
- Test in safe environment first
- Have backup spotter during demos

## Troubleshooting

### Motor doesn't spin
- Check battery voltage (should be >6.5V)
- Check L298N connections (IN1, IN2, ENA)
- Verify ESP32 GPIO outputs (use multimeter)
- Test motor directly with battery (bypass driver)

### Motor spins wrong direction
- Swap motor wires (OUT1 ↔ OUT2)
- OR swap IN1 ↔ IN2 in code

### Motor too weak
- Increase PWM duty cycle in code (MOTOR_SPEED_GENTLE)
- Check battery voltage (weak battery = weak motor)
- Verify ENA pin receiving PWM signal

### Motor too strong
- Decrease PWM duty cycle
- Add mechanical resistance (friction damper)

### Wheel doesn't contact ground
- Lower motor mount position
- Adjust cane angle (more tilt)

### Wheel drags too much
- Raise motor mount position
- Verify wheel rotates freely (bearing not stuck)

### Haptic motor doesn't vibrate
- Check 100Ω resistor present
- Verify D3 output with multimeter
- Test motor with 3V directly

## Bill of Materials Suppliers

### Electronics
- **ESP32:** Seeed Studio, Amazon
- **Motor Driver:** Amazon, SparkFun
- **Motors:** GoBilda (direct), ServoCity
- **Haptic Motor:** Adafruit, Amazon
- **Battery:** HobbyKing, Amazon (LiPo)

### Mechanical
- **Cane:** Medical supply store, Amazon
- **Omni Wheel:** GoBilda, VEX Robotics
- **Mounts:** 3D print files (STL available online)
- **Phone Mount:** Amazon, REI

### Total Cost Estimate
- Electronics: $80-120
- Mechanical: $40-60
- Battery + Charger: $30-50
- **Total: $150-230**

(Assuming you already have iPhone + cane)

---

**Last Updated:** February 2026
**Assembly Time:** 2-4 hours (first build)
**Recommended for:** Hackathon prototyping
