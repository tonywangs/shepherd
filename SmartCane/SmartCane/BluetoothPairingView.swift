//
//  BluetoothPairingView.swift
//  SmartCane
//
//  Manual ESP32 pairing and motor control interface.
//  Ported from the Bluetooth branch's standalone app.
//

import SwiftUI

struct BluetoothPairingView: View {
    @ObservedObject var ble: ESPBluetoothManager
    @ObservedObject var controller: SmartCaneController

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Git Info
                Section("Build Info") {
                    HStack {
                        Image(systemName: "chevron.branch")
                            .foregroundColor(.orange)
                        Text("Branch:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(controller.gitBranch)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.primary)
                    }

                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.blue)
                        Text("Last commit:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(controller.gitLastCommit)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                }

                // MARK: - Bluetooth Pairing
                Section("Bluetooth") {
                    HStack {
                        Label(
                            ble.isBluetoothReady ? "Powered On" : "Unavailable",
                            systemImage: ble.isBluetoothReady
                                ? "bolt.horizontal.circle.fill"
                                : "bolt.horizontal.circle"
                        )
                        .foregroundStyle(ble.isBluetoothReady ? .green : .red)

                        Spacer()

                        Button(ble.isScanning ? "Stop Scan" : "Scan") {
                            ble.toggleScan()
                        }
                    }

                    if let connectedName = ble.connectedName {
                        HStack {
                            Text("Connected: \(connectedName)")
                            Spacer()
                            Button("Disconnect", role: .destructive) {
                                ble.disconnect()
                            }
                        }
                    }

                    if let statusMessage = ble.statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if ble.discoveredPeripherals.isEmpty {
                        Text("No ESP32 devices found yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(ble.discoveredPeripherals) { device in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                    Text("RSSI: \(device.rssi)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Pair") {
                                    ble.connect(device.peripheral)
                                }
                            }
                        }
                    }
                }

                // MARK: - Motor Control
                Section("Motor Control (10 Hz)") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Angle: \(ble.angle, specifier: "%.2f")")
                        Slider(value: $ble.angle, in: -180...180)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Distance: \(ble.distance, specifier: "%.2f")")
                        Slider(value: $ble.distance, in: 0...100)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mode: \(Int(ble.mode.rounded()))")
                        Slider(value: $ble.mode, in: 0...10, step: 1)
                    }
                }

                // MARK: - Steering Tuning
                Section("Steering Tuning (Debug)") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sensitivity: \(ble.steeringSensitivity, specifier: "%.2f")m")
                        Slider(value: $ble.steeringSensitivity, in: 0.5...3.0)
                        Text("Trigger steering when obstacle < \(ble.steeringSensitivity, specifier: "%.1f")m")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Magnitude: \(ble.steeringMagnitude, specifier: "%.2f")×")
                        Slider(value: $ble.steeringMagnitude, in: 0.1...3.0)
                        Text("Motor strength multiplier")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - Steering Algorithm (Debug)
                Section("Steering Algorithm (Debug)") {
                    // Temporal EMA Alpha
                    VStack(alignment: .leading, spacing: 6) {
                        Text("EMA Memory: \(controller.temporalAlpha, specifier: "%.3f")")
                        Slider(value: $controller.temporalAlpha, in: 0.02...0.25)
                        Text("Lower = longer memory, more stable. Higher = faster response.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Output Smoothing Alpha
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Output Smoothing: \(controller.smoothingAlpha, specifier: "%.2f")")
                        Slider(value: $controller.smoothingAlpha, in: 0.05...0.5)
                        Text("Lower = smoother steering. Higher = more responsive.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Center Deadband
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Center Deadband: \(controller.centerDeadband, specifier: "%.2f")m")
                        Slider(value: $controller.centerDeadband, in: 0.05...0.5)
                        Text("Min L/R difference to pick a side for center obstacles.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Lateral Deadband
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lateral Deadband: \(controller.lateralDeadband, specifier: "%.2f")m")
                        Slider(value: $controller.lateralDeadband, in: 0.05...0.5)
                        Text("Min L/R difference to pick a side for side obstacles.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Live EMA Readout
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Live EMA State").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("L: \(controller.emaLeftDist, specifier: "%.2f")m")
                            Spacer()
                            Text("Bias: \(controller.emaLateralBias, specifier: "%.3f")")
                            Spacer()
                            Text("R: \(controller.emaRightDist, specifier: "%.2f")m")
                        }
                        .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .navigationTitle("ESP32 Bluetooth")
        }
    }
}

#Preview {
    let espBT = ESPBluetoothManager()
    let controller = SmartCaneController()
    return BluetoothPairingView(ble: espBT, controller: controller)
}
