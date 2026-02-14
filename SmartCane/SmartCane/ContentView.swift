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
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    Text("Smart Cane")
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(.white)

                    // Status Section
                    VStack(spacing: 15) {
                        // BLE Status
                        HStack {
                            Circle()
                                .fill(caneController.isConnected ? Color.green : Color.red)
                                .frame(width: 20, height: 20)
                            Text(caneController.isConnected ? "BLE Connected" : "BLE Disconnected")
                                .foregroundColor(.white)
                        }

                        // LiDAR Status
                        HStack {
                            Circle()
                                .fill(caneController.isARRunning ? Color.green : Color.orange)
                                .frame(width: 20, height: 20)
                            Text(caneController.isARRunning ? "LiDAR Active" : "LiDAR Inactive")
                                .foregroundColor(.white)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)

                    Divider()
                        .background(Color.white)

                    // Distance Readings
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Obstacle Detection")
                            .font(.headline)
                            .foregroundColor(.white)

                        HStack(spacing: 20) {
                            VStack {
                                Text("Left")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                Text(caneController.leftDistance.map { String(format: "%.2fm", $0) } ?? "--")
                                    .font(.title2)
                                    .foregroundColor(.cyan)
                            }

                            VStack {
                                Text("Center")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                Text(caneController.centerDistance.map { String(format: "%.2fm", $0) } ?? "--")
                                    .font(.title2)
                                    .foregroundColor(.green)
                            }

                            VStack {
                                Text("Right")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                Text(caneController.rightDistance.map { String(format: "%.2fm", $0) } ?? "--")
                                    .font(.title2)
                                    .foregroundColor(.cyan)
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)

                    // Depth Map Visualization
                    if caneController.showDepthVisualization {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Depth Map Visualization")
                                .font(.headline)
                                .foregroundColor(.white)

                            if let depthImage = caneController.depthVisualization {
                                Image(uiImage: depthImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 200)
                                    .cornerRadius(8)
                            } else {
                                // Loading state
                                ZStack {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(height: 200)
                                        .cornerRadius(8)

                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                }
                            }

                            // Color legend
                            HStack(spacing: 5) {
                                Text("0.2m")
                                    .font(.caption2)
                                    .foregroundColor(.white)

                                // Gradient bar
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        .red, .orange, .yellow, .green, .cyan, .blue
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(height: 20)
                                .cornerRadius(4)

                                Text("3.0m")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                    }

                    // Object Detection Display
                    if let object = caneController.detectedObject {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Detected Object")
                                .font(.headline)
                                .foregroundColor(.white)

                            Text(object)
                                .font(.title2)
                                .bold()
                                .foregroundColor(.yellow)
                                .padding()
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(10)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                    }

                    // Steering Display
                    VStack(spacing: 10) {
                        Text("Steering Command")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text(caneController.steeringCommandText)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(caneController.steeringColor)
                            .padding()
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(15)
                    }

                    Divider()
                        .background(Color.white)

                    // Control Buttons
                    VStack(spacing: 15) {
                        Button(action: {
                            caneController.toggleSystem()
                        }) {
                            HStack {
                                Image(systemName: caneController.isSystemActive ? "stop.circle.fill" : "play.circle.fill")
                                Text(caneController.isSystemActive ? "Stop System" : "Start System")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(caneController.isSystemActive ? Color.red : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }

                        Button(action: {
                            caneController.testVoice()
                        }) {
                            HStack {
                                Image(systemName: "speaker.wave.2.fill")
                                Text("Test Voice")
                            }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }

                        Button(action: {
                            caneController.toggleDepthVisualization()
                        }) {
                            HStack {
                                Image(systemName: caneController.showDepthVisualization ? "eye.slash.fill" : "eye.fill")
                                Text(caneController.showDepthVisualization ? "Hide Depth Map" : "Show Depth Map")
                            }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(caneController.showDepthVisualization ? Color.orange : Color.indigo)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }

                    // Debug Info
                    Text("Latency: \(String(format: "%.1f", caneController.latencyMs))ms")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding()
            }
        }
        .onAppear {
            print("[ContentView] View appeared, initializing controller...")
            caneController.initialize()
        }
    }
}

#Preview {
    ContentView()
}
