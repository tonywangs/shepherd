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

    private var cancellables = Set<AnyCancellable>()
    private var isVisualizationInProgress = false

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

        // TEMPORARY: VoiceManager disabled due to initialization crash
        // voiceManager = VoiceManager()
        print("[Controller] VoiceManager SKIPPED (temporarily disabled)")

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
        // TODO: Integrate VNRecognizeObjectsRequest

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
}
