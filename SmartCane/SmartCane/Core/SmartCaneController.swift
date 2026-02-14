//
//  SmartCaneController.swift
//  SmartCane
//
//  Main controller coordinating all subsystems
//

import Foundation
import SwiftUI
import Combine

@MainActor
class SmartCaneController: ObservableObject {
    // Published UI state
    @Published var isConnected = false
    @Published var isARRunning = false
    @Published var isSystemActive = false

    @Published var leftDistance: Float? = nil
    @Published var centerDistance: Float? = nil
    @Published var rightDistance: Float? = nil

    @Published var steeringCommand: Int8 = 0 // -1, 0, +1
    @Published var detectedObject: String? = nil
    @Published var detectedObjectDistance: Float? = nil
    @Published var latencyMs: Double = 0.0

    // Depth visualization
    @Published var depthVisualization: UIImage? = nil
    @Published var showDepthVisualization = false

    // Subsystems
    private var depthSensor: DepthSensor?
    private var obstacleDetector: ObstacleDetector?
    private var steeringEngine: SteeringEngine?
    private var bleManager: BLEManager?
    private var hapticManager: HapticManager?
    private var voiceManager: VoiceManager?
    private var depthVisualizer: DepthVisualizer?
    private var objectRecognizer: ObjectRecognizer?

    private var cancellables = Set<AnyCancellable>()
    private var isVisualizationInProgress = false
    private var isObjectRecognitionInProgress = false
    private var lastObjectRecognitionTime: Date = .distantPast
    private var latestDepthMap: CVPixelBuffer? = nil  // Store for distance calculation

    // Computed properties for UI
    var steeringCommandText: String {
        switch steeringCommand {
        case -1: return "← LEFT"
        case 0: return "→ NEUTRAL ←"
        case 1: return "RIGHT →"
        default: return "UNKNOWN"
        }
    }

    var steeringColor: Color {
        switch steeringCommand {
        case -1: return .blue
        case 0: return .green
        case 1: return .purple
        default: return .gray
        }
    }

    func initialize() {
        print("[Controller] Initializing Smart Cane System...")

        // Initialize simple subsystems first (no hardware dependencies)
        obstacleDetector = ObstacleDetector()
        steeringEngine = SteeringEngine()
        depthVisualizer = DepthVisualizer()
        objectRecognizer = ObjectRecognizer()

        print("[Controller] Core systems initialized")

        // Initialize hardware subsystems (these might fail on simulator)
        do {
            depthSensor = DepthSensor()
            print("[Controller] DepthSensor initialized")
        } catch {
            print("[Controller] WARNING: DepthSensor initialization failed: \(error)")
        }

        bleManager = BLEManager()
        print("[Controller] BLEManager initialized")

        hapticManager = HapticManager()
        print("[Controller] HapticManager initialized")

        // VoiceManager (with lazy initialization to prevent crashes)
        do {
            voiceManager = VoiceManager()
            print("[Controller] VoiceManager initialized")
        } catch {
            print("[Controller] WARNING: VoiceManager initialization failed: \(error)")
        }

        // Setup data pipeline
        setupDataPipeline()

        print("[Controller] System initialized. Ready to start.")
    }

    func toggleSystem() {
        isSystemActive.toggle()

        if isSystemActive {
            startSystem()
        } else {
            stopSystem()
        }
    }

    private func startSystem() {
        print("[Controller] Starting system...")

        // Start depth sensing
        depthSensor?.start()
        isARRunning = true

        // Start BLE scanning
        bleManager?.startScanning()

        // Initialize haptics
        hapticManager?.initialize()

        // Announce start
        if voiceManager != nil {
            voiceManager?.speak("Smart cane activated")
        } else {
            print("[Controller] Voice announcement skipped (VoiceManager disabled)")
        }
    }

    private func stopSystem() {
        print("[Controller] Stopping system...")

        // Stop depth sensing
        depthSensor?.stop()
        isARRunning = false

        // Send neutral command
        bleManager?.sendSteeringCommand(0)

        // Stop haptics
        hapticManager?.stop()

        // Announce stop
        if voiceManager != nil {
            voiceManager?.speak("Smart cane deactivated")
        } else {
            print("[Controller] Voice announcement skipped (VoiceManager disabled)")
        }
    }

    private func setupDataPipeline() {
        // Pipeline: Depth → Obstacle Detection → Steering → BLE + Haptics

        // 1. Depth sensor outputs frame data
        depthSensor?.$latestDepthFrame
            .compactMap { $0 }
            .sink { [weak self] depthFrame in
                self?.processDepthFrame(depthFrame)
            }
            .store(in: &cancellables)

        // 2. BLE connection status
        bleManager?.$isConnected
            .assign(to: &$isConnected)

        // 3. Monitor latency
        bleManager?.$lastLatencyMs
            .assign(to: &$latencyMs)
    }

    private func processDepthFrame(_ frame: DepthFrame) {
        guard isSystemActive else { return }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Store depth map for object distance calculation
        latestDepthMap = frame.depthMap

        // Step 1: Detect obstacles in zones
        guard let zones = obstacleDetector?.analyzeDepthFrame(frame) else { return }

        // Update UI
        leftDistance = zones.leftDistance
        centerDistance = zones.centerDistance
        rightDistance = zones.rightDistance

        // Step 2: Compute steering decision
        guard let steering = steeringEngine?.computeSteering(zones: zones) else { return }

        // Update UI
        steeringCommand = steering.command

        // Step 3: Send to ESP32 via BLE
        bleManager?.sendSteeringCommand(steering.command)

        // Step 4: Update haptics based on closest obstacle
        let closestDistance = [zones.leftDistance, zones.centerDistance, zones.rightDistance]
            .compactMap { $0 }
            .min() ?? 2.0

        hapticManager?.updateDistance(closestDistance)

        // Step 4.5: Generate depth visualization if enabled (non-blocking)
        if showDepthVisualization && !isVisualizationInProgress {
            isVisualizationInProgress = true

            // Run on background thread to avoid blocking steering pipeline
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self,
                      let visualizer = self.depthVisualizer else {
                    self?.isVisualizationInProgress = false
                    return
                }

                // Generate visualization
                let image = visualizer.visualize(depthMap: frame.depthMap)

                // Update UI on main thread
                DispatchQueue.main.async {
                    self.depthVisualization = image
                    self.isVisualizationInProgress = false
                }
            }
        }

        // Step 5: Object recognition (Phase 2 - runs async, doesn't block steering)
        // Throttle to prevent overwhelming Vision framework (max 1 call per 5 seconds)
        if let cameraImage = frame.capturedImage,
           !isObjectRecognitionInProgress,
           Date().timeIntervalSince(lastObjectRecognitionTime) > 5.0 {

            isObjectRecognitionInProgress = true
            lastObjectRecognitionTime = Date()

            // Capture pixel buffer before async closure
            let pixelBufferToProcess = cameraImage

            // Use lightweight person detection instead of heavy scene classification
            objectRecognizer?.detectPerson(pixelBufferToProcess) { [weak self] detectionResult in
                guard let self = self else { return }

                // Move all processing to main thread to access main actor properties
                DispatchQueue.main.async {
                    if let result = detectionResult {
                        // Calculate distance from stored depth map at detected object location
                        let distance: Float?
                        if let depthMap = self.latestDepthMap {
                            distance = self.calculateDistance(from: depthMap, at: result.boundingBox)
                        } else {
                            distance = nil
                        }

                        self.detectedObject = result.objectName
                        self.detectedObjectDistance = distance

                        // Only announce if cooldown has passed (ObjectRecognizer handles this)
                        let now = Date()
                        if now.timeIntervalSince(self.lastObjectRecognitionTime) > 3.0 {
                            if let dist = distance {
                                self.voiceManager?.speak("\(result.objectName) ahead at \(String(format: "%.1f", dist)) meters")
                            } else {
                                self.voiceManager?.speak("\(result.objectName) ahead")
                            }
                        }

                        print("[Controller] Detected \(result.objectName) at \(distance.map { String(format: "%.2fm", $0) } ?? "unknown") distance")
                        self.isObjectRecognitionInProgress = false
                    } else {
                        self.detectedObject = nil
                        self.detectedObjectDistance = nil
                        self.isObjectRecognitionInProgress = false
                    }
                }
            }
        }

        // Calculate processing time
        let processingTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("[Controller] Frame processed in \(String(format: "%.2f", processingTime))ms")
    }

    func testVoice() {
        if voiceManager != nil {
            voiceManager?.speak("Voice system working correctly")
        } else {
            print("[Controller] Voice test skipped (VoiceManager disabled)")
        }
    }

    func toggleDepthVisualization() {
        showDepthVisualization.toggle()
        if !showDepthVisualization {
            depthVisualization = nil
        }
    }

    // Calculate distance from depth map at bounding box location
    nonisolated private func calculateDistance(from depthMap: CVPixelBuffer, at boundingBox: CGRect) -> Float? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let buffer = baseAddress.assumingMemoryBound(to: Float32.self)

        // Convert normalized bounding box to pixel coordinates
        // Note: Vision uses bottom-left origin, need to flip Y
        let centerX = Int(boundingBox.midX * CGFloat(width))
        let centerY = Int((1.0 - boundingBox.midY) * CGFloat(height))

        // Sample multiple points in the bounding box and average
        var depthValues: [Float] = []
        let sampleSize = 5

        for dy in -sampleSize...sampleSize {
            for dx in -sampleSize...sampleSize {
                let x = min(max(centerX + dx, 0), width - 1)
                let y = min(max(centerY + dy, 0), height - 1)

                let index = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
                let depth = buffer[index]

                // Filter out invalid depth values
                if depth > 0 && depth < 10.0 {
                    depthValues.append(depth)
                }
            }
        }

        // Return median depth (more robust than mean)
        guard !depthValues.isEmpty else { return nil }
        let sorted = depthValues.sorted()
        return sorted[sorted.count / 2]
    }
}
