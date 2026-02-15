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
                Section("Steering Tuning") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sensitivity: \(ble.steeringSensitivity, specifier: "%.1f")m")
                        Slider(value: $ble.steeringSensitivity, in: 0.5...4.0)
                        Text("Start steering when obstacle closer than this")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Motor Base Scale: \(ble.motorBaseScale, specifier: "%.0f")")
                        Slider(value: $ble.motorBaseScale, in: 10...255)
                        Text("Raw speed sent to ESP32 (÷255 on device). Higher = stronger motor.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Magnitude: \(ble.steeringMagnitude, specifier: "%.1f")×")
                        Slider(value: $ble.steeringMagnitude, in: 0.1...3.0)
                        Text("Extra multiplier on base scale")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Proximity Exponent: \(ble.proximityExponent, specifier: "%.2f")")
                        Slider(value: $ble.proximityExponent, in: 0.2...1.5)
                        Text("Lower = ramps up faster with distance. 1.0 = linear.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Close Floor: \(ble.closeFloor, specifier: "%.2f")")
                        Slider(value: $ble.closeFloor, in: 0.0...1.0)
                        Text("Min |command| when obstacle < 1m. 0 = disabled.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - Steering Debug
                Section("Steering Debug (Live)") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Gap Direction:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.2f", controller.gapDirection))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(
                                    controller.gapDirection < -0.1 ? .blue :
                                    controller.gapDirection > 0.1 ? .purple : .green
                                )
                        }
                        Text("Where the clearest path is: -1 = left, 0 = center, +1 = right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Steering Command:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.2f", controller.steeringCommand))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(
                                    controller.steeringCommand < -0.1 ? .blue :
                                    controller.steeringCommand > 0.1 ? .purple : .green
                                )
                        }
                        Text("gap × proximity — sent to ESP32 as command × magnitude")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Motor Power:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(controller.motorIntensity))/255")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(controller.motorIntensity > 0 ? .orange : .secondary)
                        }
                        Text("Estimated steady-state PWM on ESP32")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
