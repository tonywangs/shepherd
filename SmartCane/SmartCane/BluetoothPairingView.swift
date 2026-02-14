//
//  BluetoothPairingView.swift
//  SmartCane
//
//  Manual ESP32 pairing and motor control interface.
//  Ported from the Bluetooth branch's standalone app.
//

import SwiftUI

struct BluetoothPairingView: View {
    @StateObject private var ble = ESPBluetoothManager()

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
            }
            .navigationTitle("ESP32 Bluetooth")
        }
    }
}

#Preview {
    BluetoothPairingView()
}
