//
//  ContentView.swift
//  SmartCane
//
//  Main UI - Simple status display for hackathon demo
//

import SwiftUI

struct ContentView: View {
    @StateObject private var caneController = SmartCaneController()

    var body: some View {
        VStack(spacing: 20) {
            // Status Section
            Text("Smart Cane")
                .font(.largeTitle)
                .bold()

            // BLE Connection Status
            HStack {
                Circle()
                    .fill(caneController.isConnected ? Color.green : Color.red)
                    .frame(width: 20, height: 20)
                Text(caneController.isConnected ? "Connected" : "Disconnected")
            }

            // ARKit Status
            HStack {
                Circle()
                    .fill(caneController.isARRunning ? Color.green : Color.orange)
                    .frame(width: 20, height: 20)
                Text(caneController.isARRunning ? "LiDAR Active" : "LiDAR Inactive")
            }

            Divider()

            // Live Data Display
            VStack(alignment: .leading, spacing: 10) {
                Text("Obstacle Detection")
                    .font(.headline)

                HStack {
                    ZoneIndicator(label: "Left", distance: caneController.leftDistance)
                    ZoneIndicator(label: "Center", distance: caneController.centerDistance)
                    ZoneIndicator(label: "Right", distance: caneController.rightDistance)
                }

                Text("Steering: \(caneController.steeringCommandText)")
                    .font(.title2)
                    .bold()
                    .foregroundColor(caneController.steeringColor)

                if let object = caneController.detectedObject {
                    Text("Detected: \(object)")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)

            Divider()

            // Control Buttons
            VStack(spacing: 15) {
                Button(action: {
                    caneController.toggleSystem()
                }) {
                    Text(caneController.isSystemActive ? "Stop System" : "Start System")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(caneController.isSystemActive ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                Button(action: {
                    caneController.testVoice()
                }) {
                    Text("Test Voice")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }

            Spacer()

            // Debug Info
            Text("Latency: \(String(format: "%.1f", caneController.latencyMs))ms")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .onAppear {
            caneController.initialize()
        }
    }
}

struct ZoneIndicator: View {
    let label: String
    let distance: Float?

    var color: Color {
        guard let dist = distance else { return .gray }
        if dist < 0.5 { return .red }
        if dist < 1.0 { return .orange }
        if dist < 1.5 { return .yellow }
        return .green
    }

    var body: some View {
        VStack {
            Text(label)
                .font(.caption)
            Rectangle()
                .fill(color)
                .frame(width: 60, height: 100)
            if let dist = distance {
                Text(String(format: "%.2fm", dist))
                    .font(.caption2)
            } else {
                Text("--")
                    .font(.caption2)
            }
        }
    }
}

#Preview {
    ContentView()
}
