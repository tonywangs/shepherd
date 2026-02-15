//
//  ContentView.swift
//  SmartCane
//
//  Main UI - Simple status display for hackathon demo
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var caneController: SmartCaneController
    @ObservedObject var espBluetooth: ESPBluetoothManager
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
                    steeringSection

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

                    // Terrain Debug Panel
                    if caneController.terrainDebugMode {
                        VStack(alignment: .leading, spacing: 10) {
                            // Header
                            HStack {
                                Image(systemName: "leaf.fill")
                                    .foregroundColor(.green)
                                Text("Terrain Debug")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Spacer()
                                // Status indicator
                                Circle()
                                    .fill(caneController.terrainDetected ? Color.orange : Color.green)
                                    .frame(width: 12, height: 12)
                                Text(caneController.terrainDetected ? caneController.detectedTerrainType.capitalized : "Clear")
                                    .font(.caption)
                                    .foregroundColor(caneController.terrainDetected ? .orange : .green)
                            }

                            // Per-zone coverage bars
                            HStack(spacing: 20) {
                                Spacer()
                                terrainZoneBar(label: "LEFT", coverage: caneController.terrainLeftCoverage)
                                terrainZoneBar(label: "CENTER", coverage: caneController.terrainCenterCoverage)
                                terrainZoneBar(label: "RIGHT", coverage: caneController.terrainRightCoverage)
                                Spacer()
                            }
                            .frame(height: 150)  // Taller to accommodate new design
                            .padding(.vertical, 8)

                            // Segmentation overlay
                            if let overlayImage = caneController.terrainDebugImage {
                                ZStack {
                                    // Camera feed underneath (if available)
                                    if let cameraImage = caneController.cameraPreview {
                                        Image(uiImage: cameraImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 200)
                                            .clipped()
                                            .cornerRadius(12)
                                    }

                                    // Segmentation overlay on top
                                    Image(uiImage: overlayImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 200)
                                        .clipped()
                                        .cornerRadius(12)
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.green.opacity(0.5), lineWidth: 2)
                                )

                                // Color legend
                                HStack(spacing: 16) {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.green).frame(width: 12, height: 12)
                                        Text("Vegetation").font(.caption2).foregroundColor(.white)
                                    }
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.brown).frame(width: 12, height: 12)
                                        Text("Dirt").font(.caption2).foregroundColor(.white)
                                    }
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.gray).frame(width: 12, height: 12)
                                        Text("Road").font(.caption2).foregroundColor(.white)
                                    }
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.blue).frame(width: 12, height: 12)
                                        Text("Sidewalk").font(.caption2).foregroundColor(.white)
                                    }
                                }
                            } else {
                                Text("Enable camera preview to see segmentation overlay")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding()
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(15)
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.green.opacity(0.4), lineWidth: 1))
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

                            // Toggle Terrain Debug
                            Button(action: {
                                caneController.toggleTerrainDebugMode()
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: caneController.terrainDebugMode ? "leaf.circle.fill" : "leaf.circle")
                                        .font(.title3)
                                    Text(caneController.terrainDebugMode ? "Debug ON" : "Terrain")
                                        .font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background((caneController.terrainDebugMode ? Color.green : Color.gray).opacity(0.8))
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

                    // Voice Assistant (Vapi)
                    vapiSection

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
            print("[ContentView] View appeared")
            // Initialization now happens in SmartCaneApp.onAppear
        }
    }

    // MARK: - Steering Display Section

    @ViewBuilder
    private var steeringSection: some View {
        let cmd = caneController.steeringCommand
        let leftScale = CGFloat(1.0 + abs(min(cmd, 0)) * 0.3)
        let rightScale = CGFloat(1.0 + max(cmd, 0) * 0.3)
        let dotOffset = CGFloat(cmd) * 30
        let leftColor: Color = cmd < -0.1 ? .blue : Color.gray.opacity(0.3)
        let rightColor: Color = cmd > 0.1 ? .purple : Color.gray.opacity(0.3)

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
                    .foregroundColor(leftColor)
                    .scaleEffect(leftScale)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: cmd)

                // Center Display
                VStack(spacing: 8) {
                    Text(caneController.steeringCommandText)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(caneController.steeringColor)

                    // Motor Intensity Display
                    Text("Power: \(Int(caneController.motorIntensity))/255")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(caneController.motorIntensity > 0 ? .orange : .gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)

                    // Direction indicator
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 80, height: 80)

                        Circle()
                            .fill(caneController.steeringColor)
                            .frame(width: 60, height: 60)
                            .offset(x: dotOffset)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: cmd)
                    }

                    // Intensity Bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 6)
                                .cornerRadius(3)

                            Rectangle()
                                .fill(LinearGradient(
                                    gradient: Gradient(colors: [.green, .yellow, .orange, .red]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                .frame(width: geometry.size.width * CGFloat(caneController.motorIntensity / 255.0), height: 6)
                                .cornerRadius(3)
                                .animation(.easeOut(duration: 0.2), value: caneController.motorIntensity)
                        }
                    }
                    .frame(height: 6)
                    .padding(.horizontal, 8)
                }

                // Right Arrow
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(rightColor)
                    .scaleEffect(rightScale)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: cmd)
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
    }

    // MARK: - Vapi Voice Assistant Section

    @ViewBuilder
    private var vapiSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .foregroundColor(.mint)
                    .font(.title3)
                Text("Voice Assistant")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(caneController.isVapiCallActive ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(caneController.isVapiCallActive ? "Active" : "Inactive")
                        .font(.caption)
                        .foregroundColor(caneController.isVapiCallActive ? .green : .gray)
                }
            }

            HStack(spacing: 12) {
                Button(action: {
                    if caneController.isVapiCallActive {
                        caneController.stopVapiCall()
                    } else {
                        caneController.startVapiCall()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: caneController.isVapiCallActive ? "phone.down.fill" : "phone.fill")
                            .font(.title3)
                        Text(caneController.isVapiCallActive ? "End Call" : "Start Call")
                            .font(.subheadline)
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(caneController.isVapiCallActive ? Color.red.opacity(0.8) : Color.mint.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }

                if caneController.isVapiCallActive {
                    Button(action: {
                        caneController.toggleVapiMute()
                    }) {
                        let muted = caneController.vapiManager?.isMuted == true
                        VStack(spacing: 4) {
                            Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                                .font(.title3)
                            Text(muted ? "Unmute" : "Mute")
                                .font(.caption2)
                        }
                        .frame(width: 70)
                        .padding(.vertical, 12)
                        .background(muted ? Color.orange.opacity(0.8) : Color.gray.opacity(0.4))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
            }

            if let transcript = caneController.vapiTranscript {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "text.bubble.fill")
                        .font(.caption)
                        .foregroundColor(.mint)
                    Text(transcript)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(3)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.mint.opacity(0.1))
                .cornerRadius(8)
            }

            if let error = caneController.vapiError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.8))
                        .lineLimit(2)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.15))
        .cornerRadius(15)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(caneController.isVapiCallActive ? Color.mint.opacity(0.5) : Color.clear, lineWidth: 1)
        )
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

    @ViewBuilder
    private func terrainZoneBar(label: String, coverage: Float) -> some View {
        VStack(spacing: 6) {
            // Label at top
            Text(label)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)

            // Bar container (fixed size, no GeometryReader)
            ZStack(alignment: .bottom) {
                // Background (full height)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 70, height: 100)

                // Filled portion (proportional height)
                RoundedRectangle(cornerRadius: 6)
                    .fill(coverage > 0.15 ? Color.orange : Color.green.opacity(0.7))
                    .frame(width: 70, height: max(4, 100 * CGFloat(coverage)))

                // Threshold line at 15%
                Rectangle()
                    .fill(Color.red.opacity(0.5))
                    .frame(width: 70, height: 1)
                    .offset(y: -15)  // 15% of 100
            }
            .frame(width: 70, height: 100)

            // Percentage at bottom
            VStack(spacing: 2) {
                Text("\(Int(coverage * 100))%")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(coverage > 0.15 ? .orange : .white)

                Text(coverage > 0.15 ? "TERRAIN" : "clear")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(coverage > 0.15 ? .orange : .gray)
            }
        }
        .frame(width: 80)  // Fixed width prevents stacking
    }
}

#Preview {
    let espBT = ESPBluetoothManager()
    let controller = SmartCaneController()
    controller.initialize(espBluetooth: espBT)
    return ContentView(caneController: controller, espBluetooth: espBT)
}
