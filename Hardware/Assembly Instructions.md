# Smart Cane - Hardware Assembly Instructions

> **Estimated build time:** 2-3 hours
>
> **Skill level:** Beginner-Intermediate (basic soldering & 3D printing required)
>
> **CAD file:** [View on Onshape](https://cad.onshape.com/documents/81a23f6a3ee770cabe38b40e/w/dbefee79fbdbd29cc2534d7b/e/bc9c36a15806c6943102f855?renderMode=0&uiState=6991caa73046b0bcd89e3977)

---

## Bill of Materials (BOM)

### Electronics

| # | Part | Qty | Notes |
|---|------|-----|-------|
| 1 | Seeed Studio XIAO ESP32-S3 | 1 | Microcontroller board |
| 2 | L298N Motor Driver | 1 | H-bridge motor controller |
| 3 | GoBilda 5203 Series 312 RPM Motor | 1 | Drive motor for the omni wheel |
| 4 | 3.25" Omni Wheel | 1 | Provides lateral steering force |
| 5 | Apple iPhone 12 Taptic Engine | 1 | Haptic feedback motor (salvaged) |
| 6 | 3S LiPo Battery Cells | 1 set | To build a 3S battery pack |
| 7 | 3S BMS Board | 1 | Battery management system |
| 8 | 12V to 5V Step-Down Converter (with USB output) | 1 | Steps battery voltage down to charge the phone |
| 9 | Phone Charging Cable | 1 | Plugs from the step-down USB into your phone |
| 10 | USB-C Battery Charger Board | 1 | For recharging the battery pack |

### Hardware & Fasteners

| # | Part | Qty | Notes |
|---|------|-----|-------|
| 11 | 1.25" PVC Pipe | 1 | Main cane shaft — cut to desired length |
| 12 | M4 Heat-Set Inserts | As needed | Press into 3D-printed parts with soldering iron |
| 13 | M4 Bolts (various lengths) | As needed | For securing motor, clamp, and covers |
| 14 | Heat Shrink Tubing | As needed | To wrap the battery pack |
| 15 | VHB Double-Sided Tape | As needed | To secure charger boards if snap fit is loose |

### 3D-Printed Parts (6 total)

Print all parts from the STL files in this folder. PLA or PETG recommended.

| # | File Name | Qty | Description |
|---|-----------|-----|-------------|
| A | `motor mounting - motor mount (2).stl` | 2 | Mounts the motor to the PVC pipe |
| B | `motor mounting - motor cover (2).stl` | 2 | Covers the motor assembly |
| C | `motor mounting - motor clamp (4).stl` | 4 | Clamps the motor in place |
| D | `handle - handle (3).stl` | 3 | Main handle body |
| E | `handle - handle cover (1).stl` | 1 | Covers the top of the handle |
| F | `handle - electronics cover.stl` | 1 | Covers the electronics compartment |
| G | `vex wheel to gobilda hub - wheel adapter.stl` | 1 | Adapts the omni wheel to the GoBilda motor shaft |

---

## Tools You'll Need

- 3D printer (PLA/PETG filament)
- Soldering iron (for heat-set inserts and wiring)
- Allen keys / hex drivers (for M4 bolts)
- Wire strippers / cutters
- Heat gun or lighter (for heat shrink)
- Screwdriver set

---

## Assembly Instructions

### Step 1: Print All Parts

Print each of the 3D-printed parts listed above. Use the quantities shown — some parts need multiple copies. Check your prints against the CAD file to make sure they look right.

### Step 2: Install Heat-Set Inserts

Using your soldering iron, carefully press **M4 heat-set inserts** into all the marked holes on the 3D-printed parts. The holes for inserts are slightly smaller than the insert diameter — the hot iron melts the plastic around the insert as you press it in.

> **Tip:** Go slow and keep the iron straight. Let the insert pull itself in with gravity and heat — don't force it.

### Step 3: Assemble the Motor & Wheel (Bottom of Cane)

1. **Attach the wheel adapter** to the omni wheel using the provided screws.
2. **Mount the adapter + wheel** onto the GoBilda motor shaft.
3. **Screw the motor** into the **motor mount** using M4 bolts.
4. **Feed the motor wire** up through the bottom of the **1.25" PVC pipe**.
5. **Place the motor cover** over the motor.
6. **Loosely attach the motor clamps** around the assembly — don't fully tighten yet (you'll adjust the fit once everything is in the pipe).

### Step 4: Build the Battery Pack

1. Assemble the battery cells into a **3S configuration** (3 cells in series).
2. Wire the cells to the **3S BMS board** following the BMS wiring diagram (it comes with instructions).
3. Wrap the entire battery + BMS assembly in **heat shrink tubing** for protection.

> **Safety note:** Be careful with LiPo cells. Never short the terminals. Always double-check polarity before connecting.

### Step 5: Feed Wires Through the PVC Pipe

1. **Feed the motor wire and battery** into the bottom of the PVC pipe at the same time.
2. **Pull both out the top** of the PVC pipe (the handle end).

> **Tip:** Use a piece of string or a wire fish tape to pull everything through if it's a tight fit.

### Step 6: Wire the Electronics

Connect everything to the **Seeed Studio XIAO ESP32-S3** and the **L298N motor driver**:

| ESP32-S3 Pin | Connects To |
|-------------|-------------|
| D0 | L298N — Motor Left Direction |
| D1 | L298N — Motor Right Direction |
| D2 | L298N — Motor Enable (PWM) |
| D3 | Taptic Engine (haptic motor) |

Additional wiring:
- **L298N motor output** → GoBilda motor wires
- **L298N power input** → Battery (via BMS)
- **12V to 5V step-down converter** → Battery 12V output (USB end connects to phone via charging cable)
- **USB-C battery charger board** → Battery (for recharging the battery pack)

> **Tip:** Refer to the ESP32 firmware code (`ESP32/SmartCane_ESP32/SmartCane_ESP32.ino`) if you need to double-check the exact pin assignments.

### Step 7: Assemble the Handle

1. **Place the Taptic Engine** into its designated slot inside the handle.
2. **Place the handle cover** on top of the handle.
3. **Mount the ESP32-S3, L298N, charger boards** into the electronics area of the handle.
   - Use **VHB tape** to secure any boards that don't snap-fit tightly.
4. **Place the electronics cover** on to close up the compartment.

### Step 8: Final Assembly

1. **Connect the battery wire** and **motor wire** coming out of the PVC pipe to the electronics in the handle.
2. **Press the handle assembly onto the top of the PVC pipe.**
3. **Tighten the motor clamps** at the bottom now that everything is in place.
4. **Double-check all connections** before powering on.

---

## You're Done!

To use the Smart Cane:
1. Power on the ESP32 — the LED should blink slowly (advertising via Bluetooth).
2. Open the Smart Cane app on an iPhone with LiDAR.
3. The phone should auto-connect — the ESP32 LED will go solid.
4. Press **Start System** in the app and start walking!

For software setup and troubleshooting, see the main [README.md](../README.md).
