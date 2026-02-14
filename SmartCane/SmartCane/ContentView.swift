//
//  ContentView.swift
//  SmartCane
//
//  Main UI - Simple status display for hackathon demo
//

import SwiftUI

struct ContentView: View {
    @StateObject private var caneController = SmartCaneController()
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    var isLandscape: Bool {
        horizontalSizeClass == .regular || verticalSizeClass == .compact
    }

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "wand.and.rays")
                                .font(.system(size: 40))
                                .foregroundColor(.cyan)

                            Text("Smart Cane")
                                .font(.largeTitle)
                                .bold()
                                .foregroundColor(.white)
                        }

                        Text("AI-Powered Navigation Assistant")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.top)

                    // Status Section - Enhanced
                    HStack(spacing: 20) {
                        // BLE Status
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(caneController.isConnected ? Color.green.opacity(0.3) : Color.red.opacity(0.3))
                                    .frame(width: 32, height: 32)

                                Circle()
                                    .fill(caneController.isConnected ? Color.green : Color.red)
                                    .frame(width: 16, height: 16)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bluetooth")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(caneController.isConnected ? "Connected" : "Searching")
                                    .font(.subheadline)
                                    .bold()
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(12)

                        // LiDAR Status
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(caneController.isARRunning ? Color.green.opacity(0.3) : Color.orange.opacity(0.3))
                                    .frame(width: 32, height: 32)

                                Circle()
                                    .fill(caneController.isARRunning ? Color.green : Color.orange)
                                    .frame(width: 16, height: 16)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("LiDAR")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(caneController.isARRunning ? "Active" : "Inactive")
                                    .font(.subheadline)
                                    .bold()
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(12)
                    }

                    Divider()
                        .background(Color.white)

                    // Distance Readings - Enhanced Visual Display
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Image(systemName: "sensor.fill")
                                .foregroundColor(.cyan)
                            Text("Obstacle Detection")
                                .font(.headline)
                                .foregroundColor(.white)
                        }

                        HStack(spacing: 15) {
                            // Left Zone
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.left")
                                    .font(.title3)
                                    .foregroundColor(.cyan)
                                Text("Left")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(formatDistance(caneController.leftDistance))
                                    .font(.title2)
                                    .bold()
                                    .foregroundColor(getDistanceColor(caneController.leftDistance))

                                // Distance bar
                                if let dist = caneController.leftDistance {
                                    GeometryReader { geometry in
                                        ZStack(alignment: .leading) {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(height: 4)

                                            Rectangle()
                                                .fill(getDistanceColor(dist))
                                                .frame(width: geometry.size.width * CGFloat(min(dist / 4.0, 1.0)), height: 4)
                                        }
                                    }
                                    .frame(height: 4)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(12)

                            // Center Zone
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.up")
                                    .font(.title3)
                                    .foregroundColor(.green)
                                Text("Center")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(formatDistance(caneController.centerDistance))
                                    .font(.title2)
                                    .bold()
                                    .foregroundColor(getDistanceColor(caneController.centerDistance))

                                // Distance bar
                                if let dist = caneController.centerDistance {
                                    GeometryReader { geometry in
                                        ZStack(alignment: .leading) {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(height: 4)

                                            Rectangle()
                                                .fill(getDistanceColor(dist))
                                                .frame(width: geometry.size.width * CGFloat(min(dist / 4.0, 1.0)), height: 4)
                                        }
                                    }
                                    .frame(height: 4)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(12)

                            // Right Zone
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.right")
                                    .font(.title3)
                                    .foregroundColor(.cyan)
                                Text("Right")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(formatDistance(caneController.rightDistance))
                                    .font(.title2)
                                    .bold()
                                    .foregroundColor(getDistanceColor(caneController.rightDistance))

                                // Distance bar
                                if let dist = caneController.rightDistance {
                                    GeometryReader { geometry in
                                        ZStack(alignment: .leading) {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(height: 4)

                                            Rectangle()
                                                .fill(getDistanceColor(dist))
                                                .frame(width: geometry.size.width * CGFloat(min(dist / 4.0, 1.0)), height: 4)
                                        }
                                    }
                                    .frame(height: 4)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(15)

                    // Steering Display - Enhanced
                    VStack(spacing: 15) {
                        HStack {
                            Image(systemName: "location.north.fill")
                                .foregroundColor(.cyan)
                            Text("Steering Command")
                                .font(.headline)
                                .foregroundColor(.white)
                        }

                        HStack(spacing: 20) {
                            // Left Arrow
                            Image(systemName: "arrow.left.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(caneController.steeringCommand == -1 ? .blue : Color.gray.opacity(0.3))
                                .scaleEffect(caneController.steeringCommand == -1 ? 1.2 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: caneController.steeringCommand)

                            // Center Display
                            VStack(spacing: 8) {
                                Text(caneController.steeringCommandText)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(caneController.steeringColor)

                                // Direction indicator
                                ZStack {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 80, height: 80)

                                    Circle()
                                        .fill(caneController.steeringColor)
                                        .frame(width: 60, height: 60)
                                        .offset(x: CGFloat(caneController.steeringCommand) * 15)
                                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: caneController.steeringCommand)
                                }
                            }

                            // Right Arrow
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(caneController.steeringCommand == 1 ? .purple : Color.gray.opacity(0.3))
                                .scaleEffect(caneController.steeringCommand == 1 ? 1.2 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: caneController.steeringCommand)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.gray.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(caneController.steeringColor.opacity(0.5), lineWidth: 2)
                                )
                        )
                    }
                    .padding()
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(15)

                    Divider()
                        .background(Color.white)

                    // Depth Map Visualization
                    if caneController.showDepthVisualization {
                        VStack(alignment: .center, spacing: 10) {
                            HStack {
                                Image(systemName: "chart.bar.fill")
                                    .foregroundColor(.cyan)
                                Text("Depth Map Visualization")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }

                            if let depthImage = caneController.depthVisualization {
                                GeometryReader { containerGeometry in
                                    ZStack {
                                        Image(uiImage: depthImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: containerGeometry.size.width, height: isLandscape ? 280 : 240)
                                            .clipped()
                                            .cornerRadius(12)

                                        // Zone dividers overlay - constrained to image bounds
                                        ZStack {
                                            let imageWidth = containerGeometry.size.width
                                            let imageHeight = isLandscape ? CGFloat(280) : CGFloat(240)

                                            // Left/Center divider at 33%
                                            Rectangle()
                                                .fill(Color.yellow.opacity(0.8))
                                                .frame(width: 2, height: imageHeight)
                                                .position(x: imageWidth * 0.33, y: imageHeight / 2)

                                            // Center/Right divider at 67%
                                            Rectangle()
                                                .fill(Color.yellow.opacity(0.8))
                                                .frame(width: 2, height: imageHeight)
                                                .position(x: imageWidth * 0.67, y: imageHeight / 2)

                                            // Zone labels
                                            Text("L")
                                                .font(.system(size: 20, weight: .bold))
                                                .foregroundColor(.white)
                                                .shadow(color: .black, radius: 2)
                                                .position(x: imageWidth * 0.165, y: 25)

                                            VStack(spacing: 2) {
                                                Text("C")
                                                    .font(.system(size: 20, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .shadow(color: .black, radius: 2)
                                                Text("~0.5m")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(.yellow)
                                                    .shadow(color: .black, radius: 2)
                                            }
                                            .position(x: imageWidth * 0.5, y: 30)

                                            Text("R")
                                                .font(.system(size: 20, weight: .bold))
                                                .foregroundColor(.white)
                                                .shadow(color: .black, radius: 2)
                                                .position(x: imageWidth * 0.835, y: 25)
                                        }
                                    }
                                }
                                .frame(height: isLandscape ? 280 : 240)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.cyan.opacity(0.5), lineWidth: 2)
                                )
                            } else {
                                // Loading state
                                ZStack {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(height: isLandscape ? 280 : 240)
                                        .cornerRadius(12)

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

                    // Camera Preview with Person Detection
                    if caneController.showCameraPreview {
                        VStack(alignment: .center, spacing: 10) {
                            HStack {
                                Image(systemName: "camera.fill")
                                    .foregroundColor(.yellow)
                                Text("Live Camera + Detection")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }

                            if let cameraImage = caneController.cameraPreview {
                                GeometryReader { containerGeometry in
                                    ZStack {
                                        Image(uiImage: cameraImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: containerGeometry.size.width, height: isLandscape ? 280 : 240)
                                            .clipped()
                                            .cornerRadius(12)

                                        // Zone dividers overlay - constrained to image bounds
                                        ZStack {
                                            let imageWidth = containerGeometry.size.width
                                            let imageHeight = isLandscape ? CGFloat(280) : CGFloat(240)

                                            // Left/Center divider at 33%
                                            Rectangle()
                                                .fill(Color.yellow.opacity(0.8))
                                                .frame(width: 2, height: imageHeight)
                                                .position(x: imageWidth * 0.33, y: imageHeight / 2)

                                            // Center/Right divider at 67%
                                            Rectangle()
                                                .fill(Color.yellow.opacity(0.8))
                                                .frame(width: 2, height: imageHeight)
                                                .position(x: imageWidth * 0.67, y: imageHeight / 2)

                                            // Zone labels
                                            Text("L")
                                                .font(.system(size: 20, weight: .bold))
                                                .foregroundColor(.white)
                                                .shadow(color: .black, radius: 3)
                                                .position(x: imageWidth * 0.165, y: 25)

                                            VStack(spacing: 2) {
                                                Text("C")
                                                    .font(.system(size: 20, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .shadow(color: .black, radius: 3)
                                                Text("~0.5m")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(.yellow)
                                                    .shadow(color: .black, radius: 3)
                                            }
                                            .position(x: imageWidth * 0.5, y: 30)

                                            Text("R")
                                                .font(.system(size: 20, weight: .bold))
                                                .foregroundColor(.white)
                                                .shadow(color: .black, radius: 3)
                                                .position(x: imageWidth * 0.835, y: 25)
                                        }
                                    }
                                }
                                .frame(height: isLandscape ? 280 : 240)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.yellow.opacity(0.5), lineWidth: 2)
                                )
                            } else {
                                ZStack {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(height: isLandscape ? 280 : 240)
                                        .cornerRadius(12)

                                    VStack(spacing: 8) {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        Text("Initializing camera...")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                            }

                            // Detection info
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                                Text("Yellow box shows detected person")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(15)
                    }

                    // Object Detection Display (Dynamic)
                    if let object = caneController.detectedObject {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundColor(.yellow)
                                    .font(.title3)
                                Text("Detected Object")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(object.capitalized)
                                        .font(.title)
                                        .bold()
                                        .foregroundColor(.yellow)

                                    if let distance = caneController.detectedObjectDistance {
                                        HStack(spacing: 8) {
                                            Image(systemName: "ruler")
                                                .font(.caption)
                                                .foregroundColor(.cyan)
                                            Text(String(format: "%.2f meters away", distance))
                                                .font(.title3)
                                                .foregroundColor(.cyan)
                                        }
                                    }
                                }
                                Spacer()

                                // Visual distance indicator
                                if let distance = caneController.detectedObjectDistance {
                                    ZStack {
                                        Circle()
                                            .stroke(Color.yellow.opacity(0.3), lineWidth: 3)
                                            .frame(width: 60, height: 60)

                                        Circle()
                                            .trim(from: 0, to: min(CGFloat(3.0 / max(distance, 0.1)), 1.0))
                                            .stroke(Color.yellow, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                            .frame(width: 60, height: 60)
                                            .rotationEffect(.degrees(-90))

                                        Text(String(format: "%.1f", distance))
                                            .font(.caption)
                                            .bold()
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.yellow.opacity(0.2), Color.orange.opacity(0.1)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(15)
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(Color.yellow.opacity(0.5), lineWidth: 2)
                        )
                        .shadow(color: Color.yellow.opacity(0.3), radius: 10)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: caneController.detectedObject)
                    }

                    // Control Buttons - Enhanced Design
                    VStack(spacing: 15) {
                        // Main System Toggle
                        Button(action: {
                            caneController.toggleSystem()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: caneController.isSystemActive ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.title2)
                                Text(caneController.isSystemActive ? "Stop System" : "Start System")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: caneController.isSystemActive ?
                                        [Color.red, Color.red.opacity(0.8)] :
                                        [Color.green, Color.green.opacity(0.8)]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(15)
                            .shadow(color: (caneController.isSystemActive ? Color.red : Color.green).opacity(0.4), radius: 8)
                        }

                        // Secondary controls row 1
                        HStack(spacing: 12) {
                            // Toggle Depth Visualization
                            Button(action: {
                                caneController.toggleDepthVisualization()
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: caneController.showDepthVisualization ? "eye.slash.fill" : "eye.fill")
                                        .font(.title3)
                                    Text(caneController.showDepthVisualization ? "Hide Depth" : "Show Depth")
                                        .font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background((caneController.showDepthVisualization ? Color.orange : Color.indigo).opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }

                            // Toggle Camera Preview
                            Button(action: {
                                caneController.toggleCameraPreview()
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: caneController.showCameraPreview ? "video.slash.fill" : "video.fill")
                                        .font(.title3)
                                    Text(caneController.showCameraPreview ? "Hide Camera" : "Show Camera")
                                        .font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background((caneController.showCameraPreview ? Color.purple : Color.teal).opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                        }

                        // Secondary controls row 2
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
                            .background(Color.blue.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }

                    // Debug Info - Enhanced
                    HStack(spacing: 8) {
                        Image(systemName: "speedometer")
                            .font(.caption)
                            .foregroundColor(.cyan)
                        Text("Latency: \(String(format: "%.1f", caneController.latencyMs))ms")
                            .font(.caption)
                            .foregroundColor(.gray)

                        Spacer()

                        if caneController.isSystemActive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("System Active")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
        }
        .onAppear {
            print("[ContentView] View appeared, initializing controller...")
            caneController.initialize()
        }
    }

    // Helper function to format distance display
    private func formatDistance(_ distance: Float?) -> String {
        guard let dist = distance else { return "Clear" }

        if dist > 4.0 {
            return "Clear"  // Beyond detection range
        } else {
            return String(format: "%.2fm", dist)
        }
    }

    // Helper function to get color based on distance (closer = more red)
    private func getDistanceColor(_ distance: Float?) -> Color {
        guard let dist = distance else { return .green }  // No obstacle = green

        if dist < 0.5 {
            return .red      // Very close - immediate danger
        } else if dist < 1.0 {
            return .orange   // Close - caution
        } else if dist < 2.0 {
            return .yellow   // Moderate - be aware
        } else if dist <= 4.0 {
            return .green    // Safe - far enough away
        } else {
            return .green    // Clear
        }
    }
}

#Preview {
    ContentView()
}
