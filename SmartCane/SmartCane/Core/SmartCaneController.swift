//
//  SmartCaneController.swift
//  SmartCane
//
//  Main controller coordinating all subsystems
//

import Foundation
import SwiftUI
import Combine
import UIKit
import CoreML

@MainActor
class SmartCaneController: ObservableObject {
    // Published UI state
    @Published var isConnected = false
    @Published var isARRunning = false
    @Published var isSystemActive = false

    @Published var leftDistance: Float? = nil
    @Published var centerDistance: Float? = nil
    @Published var rightDistance: Float? = nil

    @Published var steeringCommand: Float = 0.0 // -1.0 to +1.0 continuous
    @Published var motorIntensity: Float = 0.0 // 0-255, actual motor power being sent
    @Published var detectedObject: String? = nil
    @Published var detectedObjectDistance: Float? = nil

    // Depth visualization
    @Published var depthVisualization: UIImage? = nil
    @Published var showDepthVisualization = false

    // Camera preview with detection overlay
    @Published var cameraPreview: UIImage? = nil
    @Published var detectedPersonBox: CGRect? = nil
    @Published var showCameraPreview = false
    @Published var deviceOrientation: UIDeviceOrientation = .portrait

    // Terrain detection state
    @Published var terrainDebugMode: Bool = false        // Toggle: classify but don't inject walls
    @Published var terrainDetected: Bool = false         // Is any terrain currently detected?
    @Published var detectedTerrainType: String = "none"  // grass, dirt, bushes, mixed, none
    @Published var terrainLeftCoverage: Float = 0        // 0.0-1.0 per zone
    @Published var terrainCenterCoverage: Float = 0
    @Published var terrainRightCoverage: Float = 0
    @Published var terrainDebugImage: UIImage? = nil     // Segmentation overlay for debug UI

    // Vapi voice assistant
    @Published var isVapiCallActive = false
    @Published var vapiTranscript: String?
    @Published var vapiError: String?

    // Gap-seeking debug readouts (read-only for UI)
    @Published var gapDirection: Float = 0.0

    // Subsystems
    private var depthSensor: DepthSensor?
    private var obstacleDetector: ObstacleDetector?
    private var steeringEngine: SteeringEngine?
    private var hapticManager: HapticManager?
    private var voiceManager: VoiceManager?
    private var depthVisualizer: DepthVisualizer?
    private var objectRecognizer: ObjectRecognizer?
    private var surfaceClassifier: SurfaceClassifier?
    private var espBluetooth: ESPBluetoothManager?
    var vapiManager: VapiManager?
    private var gameController: GameControllerManager?
    var navigationManager: NavigationManager?

    private var cancellables = Set<AnyCancellable>()
    private var isVisualizationInProgress = false
    private var isObjectRecognitionInProgress = false
    private var lastObjectRecognitionTime: Date = .distantPast
    private var latestDepthMap: CVPixelBuffer? = nil  // Store for distance calculation
    private var latestCameraImage: CVPixelBuffer? = nil  // Store for camera preview
    private var isCameraPreviewInProgress = false
    private var lastCameraPreviewTime: Date = .distantPast

    // Terrain classification state
    private var lastTerrainClassificationTime: Date = .distantPast
    private var latestTerrainObstacles: TerrainObstacles? = nil
    private var lastTerrainAnnouncementTime: Date = .distantPast
    private let terrainAnnouncementCooldown: TimeInterval = 5.0  // 5 seconds between alerts

    // Frame watchdog — detects depth pipeline stalls
    private var lastFrameTime: Date = .distantPast
    private var frameWatchdogTimer: Timer?
    private let frameStaleThreshold: TimeInterval = 0.5  // 500ms without a frame = stale

    // Computed properties for UI
    var steeringCommandText: String {
        if steeringCommand < -0.1 {
            return "← LEFT \(String(format: "%.2f", steeringCommand))"
        } else if steeringCommand > 0.1 {
            return "RIGHT +\(String(format: "%.2f", steeringCommand)) →"
        } else {
            return "→ NEUTRAL ←"
        }
    }

    var steeringColor: Color {
        if steeringCommand < -0.1 {
            return .blue
        } else if steeringCommand > 0.1 {
            return .purple
        } else {
            return .green
        }
    }

    func initialize(espBluetooth: ESPBluetoothManager? = nil) {
        self.espBluetooth = espBluetooth
        print("[Controller] Initializing Smart Cane System...")

        // Initialize simple subsystems first (no hardware dependencies)
        obstacleDetector = ObstacleDetector()
        steeringEngine = SteeringEngine()
        depthVisualizer = DepthVisualizer()
        objectRecognizer = ObjectRecognizer()

        // Initialize terrain classifier (may be nil if model not available)
        surfaceClassifier = SurfaceClassifier()
        if surfaceClassifier != nil {
            print("[Controller] Terrain classification enabled")
        } else {
            print("[Controller] Terrain classification unavailable (model not loaded)")
        }

        // Initialize game controller manager (Joy-Con override)
        gameController = GameControllerManager()
        print("[Controller] Game controller manager initialized")

        // Monitor device orientation
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.deviceOrientation = UIDevice.current.orientation
            print("[Controller] Device orientation changed: \(UIDevice.current.orientation.rawValue)")
        }

        print("[Controller] Core systems initialized")

        // Initialize hardware subsystems (these might fail on simulator)
        do {
            depthSensor = DepthSensor()
            print("[Controller] DepthSensor initialized")
        } catch {
            print("[Controller] WARNING: DepthSensor initialization failed: \(error)")
        }

        hapticManager = HapticManager()
        print("[Controller] HapticManager initialized")

        // VoiceManager (with lazy initialization to prevent crashes)
        do {
            voiceManager = VoiceManager()
            print("[Controller] VoiceManager initialized")
        } catch {
            print("[Controller] WARNING: VoiceManager initialization failed: \(error)")
        }

        // Initialize Vapi voice assistant
        // TODO: Replace with your Vapi public key
        vapiManager = VapiManager(publicKey: "81547ebe-da3d-44c1-8063-020598a9316f")
        print("[Controller] VapiManager initialized")

        // Subscribe to Vapi state changes
        setupVapiSubscriptions()

        // Initialize GPS navigation
        let routeService = RouteService(googleApiKey: Secrets.googleAPIKey,
                                         openRouteServiceApiKey: Secrets.openRouteServiceAPIKey)
        navigationManager = NavigationManager()
        navigationManager?.initialize(routeService: routeService, voiceManager: voiceManager)
        print("[Controller] NavigationManager initialized")

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

        // Initialize haptics
        hapticManager?.initialize()

        // Start frame watchdog
        startFrameWatchdog()

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

        // Zero out ESP32 motor
        espBluetooth?.angle = 0
        espBluetooth?.distance = 500
        espBluetooth?.mode = 0

        // Zero out UI state
        motorIntensity = 0.0
        steeringCommand = 0.0

        // Reset steering smoother so next session starts fresh
        steeringEngine?.reset()

        // Stop frame watchdog
        frameWatchdogTimer?.invalidate()
        frameWatchdogTimer = nil

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

        // 2. ESP32 connection status
        espBluetooth?.$connectedName
            .map { $0 != nil }
            .assign(to: &$isConnected)
    }

    private func setupVapiSubscriptions() {
        vapiManager?.$isCallActive
            .receive(on: DispatchQueue.main)
            .assign(to: &$isVapiCallActive)

        vapiManager?.$lastTranscript
            .receive(on: DispatchQueue.main)
            .assign(to: &$vapiTranscript)

        vapiManager?.$callError
            .receive(on: DispatchQueue.main)
            .assign(to: &$vapiError)
    }

    // MARK: - Vapi Voice Assistant Controls

    func startVapiCall() {
        vapiManager?.startCall()
    }

    func stopVapiCall() {
        vapiManager?.stopCall()
    }

    func toggleVapiMute() {
        vapiManager?.toggleMute()
    }

    /// Build a compact sensor summary string for the Vapi assistant
    private func buildSensorSummary(zones: ObstacleZones, steering: SteeringDecision) -> String {
        let left = zones.leftDistance.map { String(format: "%.1fm", $0) } ?? "clear"
        let center = zones.centerDistance.map { String(format: "%.1fm", $0) } ?? "clear"
        let right = zones.rightDistance.map { String(format: "%.1fm", $0) } ?? "clear"

        let steerDir: String
        if steering.command < -0.1 { steerDir = "LEFT(\(String(format: "%.2f", steering.command)))" }
        else if steering.command > 0.1 { steerDir = "RIGHT(\(String(format: "%.2f", steering.command)))" }
        else { steerDir = "STRAIGHT" }

        var summary = "L:\(left) C:\(center) R:\(right) Steer:\(steerDir)"

        if let obj = detectedObject {
            let dist = detectedObjectDistance.map { String(format: "%.1fm", $0) } ?? "?"
            summary += " \(obj):\(dist)"
        }

        return summary
    }

    private func processDepthFrame(_ frame: DepthFrame) {
        guard isSystemActive else { return }

        lastFrameTime = Date()
        let startTime = CFAbsoluteTimeGetCurrent()

        // Update ARKit heading at 60Hz (Layer 1)
        navigationManager?.headingProvider.updateFromARKit(cameraTransform: frame.cameraTransform)

        // Store depth map and camera image for object detection and preview
        latestDepthMap = frame.depthMap
        latestCameraImage = frame.capturedImage

        // Step 0: Classify terrain (throttled to ~3Hz for performance)
        let now = Date()
        if now.timeIntervalSince(lastTerrainClassificationTime) > 0.33,
           let classifier = surfaceClassifier,
           let capturedImage = frame.capturedImage {

            lastTerrainClassificationTime = now

            classifier.classifyTerrain(
                capturedImage,
                orientation: deviceOrientation,
                includeDebugMask: terrainDebugMode  // Only include mask when debug mode is ON
            ) { [weak self] obstacles in
                DispatchQueue.main.async {
                    self?.updateTerrainState(obstacles)
                }
            }
        }

        // Step 1: Detect obstacles in zones (pass orientation for coordinate transform)
        // Pass terrain obstacles for merging (nil when debug mode is ON to disable steering impact)
        guard let zones = obstacleDetector?.analyzeDepthFrame(
            frame,
            orientation: deviceOrientation,
            terrainObstacles: terrainDebugMode ? nil : latestTerrainObstacles
        ) else { return }

        // Update UI
        leftDistance = zones.leftDistance
        centerDistance = zones.centerDistance
        rightDistance = zones.rightDistance

        // Step 2: Gap-seeking steering — steer toward the clearest path
        guard let steering = steeringEngine?.computeSteering(
            zones: zones,
            sensitivity: espBluetooth?.steeringSensitivity ?? 2.0,
            proximityExponent: espBluetooth?.proximityExponent ?? 0.6,
            closeFloor: espBluetooth?.closeFloor ?? 0.5
        ) else { return }

        // Step 2.5: Merge navigation bias (Layer 5 — obstacles always win)
        var finalCommand = steering.command
        if let nav = navigationManager, nav.state.isActive {
            let navBias = nav.biasComputer.navBias
            let alpha = 1.0 - steering.confidence  // 0 when obstacle close, 1 when clear
            let beta: Float = 0.3                   // nav weight when path is clear
            finalCommand = max(-1.0, min(1.0, steering.command + navBias * beta * alpha))
        }

        // Update UI
        steeringCommand = finalCommand
        gapDirection = zones.gapDirection

        // Step 3: Send to ESP32 via 12-byte protocol
        let mergedSteering = SteeringDecision(command: finalCommand, confidence: steering.confidence, reason: steering.reason)
        updateESPMotor(steering: mergedSteering, zones: zones)

        // Step 4: Update haptics based on closest obstacle
        let closestDistance = [zones.leftDistance, zones.centerDistance, zones.rightDistance]
            .compactMap { $0 }
            .min() ?? 2.0

        hapticManager?.updateDistance(closestDistance)

        // Step 4.1: Send sensor data to Vapi voice assistant (if call active)
        if isVapiCallActive {
            let summary = buildSensorSummary(zones: zones, steering: steering)
            vapiManager?.sendSensorUpdate(summary)

            // Urgent alert for critical center obstacle
            if let centerDist = zones.centerDistance, centerDist < 0.6 {
                vapiManager?.sendUrgentAlert("Stop. Obstacle directly ahead at \(String(format: "%.1f", centerDist)) meters.")
            }
        }

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

                // Generate visualization with current orientation
                let image = visualizer.visualize(depthMap: frame.depthMap, orientation: self.deviceOrientation)

                // Update UI on main thread
                DispatchQueue.main.async {
                    self.depthVisualization = image
                    self.isVisualizationInProgress = false
                }
            }
        }

        // Step 5a: Update camera preview (if enabled) - runs more frequently than object detection
        if showCameraPreview,
           let cameraImage = frame.capturedImage,
           !isCameraPreviewInProgress,
           Date().timeIntervalSince(lastCameraPreviewTime) > 0.1 {  // ~10fps for smoother preview

            isCameraPreviewInProgress = true
            lastCameraPreviewTime = Date()

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }

                let ciImage = CIImage(cvPixelBuffer: cameraImage)
                let context = CIContext()

                guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                    DispatchQueue.main.async { self.isCameraPreviewInProgress = false }
                    return
                }

                // Get current device orientation
                let orientation = self.getImageOrientation()

                // Create UIImage with proper orientation
                let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)

                DispatchQueue.main.async {
                    // Always update live preview (don't freeze when detection happens)
                    self.cameraPreview = image
                    self.isCameraPreviewInProgress = false
                }
            }
        }

        // Step 5b: Object recognition (Phase 2 - runs async, doesn't block steering)
        // Throttle to ~2Hz (VNDetectHumanRectanglesRequest is lightweight)
        if let cameraImage = frame.capturedImage,
           !isObjectRecognitionInProgress,
           Date().timeIntervalSince(lastObjectRecognitionTime) > 0.5 {

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
                        self.detectedPersonBox = result.boundingBox

                        // Generate camera preview with bounding box from stored camera image
                        if self.showCameraPreview, let cameraImage = self.latestCameraImage {
                            self.generateCameraPreview(from: cameraImage, boundingBox: result.boundingBox)
                        }

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
                        self.detectedPersonBox = nil
                        self.isObjectRecognitionInProgress = false
                    }
                }
            }
        }

        // Calculate processing time
        let processingTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("[Controller] Frame processed in \(String(format: "%.2f", processingTime))ms")
    }

    // MARK: - Frame Watchdog

    private func startFrameWatchdog() {
        lastFrameTime = Date()
        frameWatchdogTimer?.invalidate()
        frameWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkFrameStaleness()
            }
        }
    }

    private func checkFrameStaleness() {
        guard isSystemActive else { return }
        // Don't zero steering while Joy-Con is actively overriding
        guard gameController?.overrideSteer == nil else { return }

        let elapsed = Date().timeIntervalSince(lastFrameTime)
        guard elapsed > frameStaleThreshold else { return }

        print("[Controller] WARNING: Depth frames stale (\(String(format: "%.1f", elapsed))s) — zeroing steering")

        // Safe fallback: stop all motor output
        steeringCommand = 0.0
        motorIntensity = 0.0
        espBluetooth?.angle = 0
        espBluetooth?.distance = 500
        espBluetooth?.mode = 0
        hapticManager?.stop()
        steeringEngine?.reset()
    }

    /// Map steering decision into ESP32 12-byte motor packet.
    /// ESP32 normalizes field 1 by dividing by 255 (kMotorInputScale = 1/255).
    /// So we must send values on a ±255 scale for full motor range.
    /// The leaky integrator (tau=0.55s) smooths the input on the ESP32 side.
    private func updateESPMotor(steering: SteeringDecision, zones: ObstacleZones) {
        guard let esp = espBluetooth else { return }

        // Emergency kill: any Joy-Con face button forces motor to 0
        if gameController?.killMotor == true {
            esp.angle = 0
            esp.distance = 500
            esp.mode = 0
            motorIntensity = 0
            return
        }

        let magnitude = esp.steeringMagnitude  // default 1.0, UI slider
        let baseScale = esp.motorBaseScale     // default 80, UI slider
        let closestDist = zones.closestDistance ?? 5.0

        // Joy-Con override: use manual input when joystick is active
        let command = (gameController?.overrideSteer).map { $0 * 2.5 } ?? steering.command

        // Field 1: command scaled to ESP32's input range.
        // ESP32 divides by 255 to normalize. baseScale × magnitude sets the ceiling.
        // e.g. baseScale=80 × magnitude=1.0 × command=1.0 → 80 → inputNorm=0.31 → PWM≈80
        let steer = command * baseScale * magnitude

        // Field 2: haptic proximity (closer = faster pulses on ESP32)
        let hapticDist = min(500.0, closestDist * 125.0)

        // UI: approximate steady-state PWM the motor will reach
        motorIntensity = min(255.0, fabsf(steer))

        esp.angle = steer
        esp.distance = hapticDist
        esp.mode = 1

        print("[Controller] ESP32 -> field1: \(String(format: "%+.1f", steer)), cmd: \(String(format: "%+.2f", steering.command)), gap: \(String(format: "%+.2f", zones.gapDirection)), closest: \(String(format: "%.2f", closestDist))m")
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

    func toggleCameraPreview() {
        showCameraPreview.toggle()
        if !showCameraPreview {
            cameraPreview = nil
            detectedPersonBox = nil
        }
    }

    // Get correct image orientation based on device orientation
    private func getImageOrientation() -> UIImage.Orientation {
        switch deviceOrientation {
        case .portrait:
            return .right        // Fixed: back to original for portrait
        case .portraitUpsideDown:
            return .left         // Fixed: back to original for portrait
        case .landscapeLeft:
            return .up           // Keep as is (works in landscape)
        case .landscapeRight:
            return .down         // Keep as is (works in landscape)
        default:
            return .right        // Default to portrait
        }
    }

    // Generate camera preview with bounding box overlay
    private func generateCameraPreview(from pixelBuffer: CVPixelBuffer, boundingBox: CGRect) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()

            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

            // Get orientation and determine output size
            let orientation = self.getImageOrientation()
            let needsRotation = orientation == .right || orientation == .left
            let size = needsRotation ?
                CGSize(width: cgImage.height, height: cgImage.width) :
                CGSize(width: cgImage.width, height: cgImage.height)

            UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
            guard let ctx = UIGraphicsGetCurrentContext() else { return }

            // Save state before rotation
            ctx.saveGState()

            // Apply rotation based on orientation
            switch orientation {
            case .right:  // Portrait (fixed: back to original)
                ctx.translateBy(x: size.width / 2, y: size.height / 2)
                ctx.rotate(by: .pi / 2)
                ctx.translateBy(x: -CGFloat(cgImage.width) / 2, y: -CGFloat(cgImage.height) / 2)
            case .left:  // Portrait upside down (fixed: back to original)
                ctx.translateBy(x: size.width / 2, y: size.height / 2)
                ctx.rotate(by: -.pi / 2)
                ctx.translateBy(x: -CGFloat(cgImage.width) / 2, y: -CGFloat(cgImage.height) / 2)
            case .up:  // Landscape left (keep as is)
                // No rotation needed
                break
            case .down:  // Landscape right (keep as is)
                ctx.translateBy(x: size.width / 2, y: size.height / 2)
                ctx.rotate(by: .pi)
                ctx.translateBy(x: -CGFloat(cgImage.width) / 2, y: -CGFloat(cgImage.height) / 2)
            default:
                break
            }

            // Draw camera image
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

            // Restore state for drawing bounding box
            ctx.restoreGState()

            // Convert normalized bounding box to image coordinates (adjusted for rotation)
            let rect: CGRect
            switch orientation {
            case .right:  // Portrait - 90° CW (fixed: back to original)
                rect = CGRect(
                    x: boundingBox.minY * size.width,
                    y: (1.0 - boundingBox.maxX) * size.height,
                    width: boundingBox.height * size.width,
                    height: boundingBox.width * size.height
                )
            case .left:  // Portrait upside down - 90° CCW (fixed: back to original)
                rect = CGRect(
                    x: (1.0 - boundingBox.maxY) * size.width,
                    y: boundingBox.minX * size.height,
                    width: boundingBox.height * size.width,
                    height: boundingBox.width * size.height
                )
            case .up:  // Landscape left - no rotation (keep as is)
                rect = CGRect(
                    x: boundingBox.minX * size.width,
                    y: (1.0 - boundingBox.maxY) * size.height,
                    width: boundingBox.width * size.width,
                    height: boundingBox.height * size.height
                )
            case .down:  // Landscape right - 180° (keep as is)
                rect = CGRect(
                    x: (1.0 - boundingBox.maxX) * size.width,
                    y: boundingBox.minY * size.height,
                    width: boundingBox.width * size.width,
                    height: boundingBox.height * size.height
                )
            default:
                rect = .zero
            }

            // Draw bounding box
            ctx.setStrokeColor(UIColor.yellow.cgColor)
            ctx.setLineWidth(4.0)
            ctx.stroke(rect)

            // Draw label background
            let labelText = "Person"
            let labelFont = UIFont.boldSystemFont(ofSize: 20)
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: UIColor.white
            ]
            let labelSize = labelText.size(withAttributes: labelAttributes)
            let labelRect = CGRect(
                x: rect.minX,
                y: rect.minY - labelSize.height - 4,
                width: labelSize.width + 8,
                height: labelSize.height + 4
            )

            ctx.setFillColor(UIColor.yellow.cgColor)
            ctx.fill(labelRect)

            // Draw label text
            let textPoint = CGPoint(x: labelRect.minX + 4, y: labelRect.minY + 2)
            labelText.draw(at: textPoint, withAttributes: labelAttributes)

            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            DispatchQueue.main.async {
                self.cameraPreview = image
            }
        }
    }

    /// Calculate distance to detected person using LiDAR depth data
    ///
    /// **How Person Distance Detection Works:**
    ///
    /// 1. **Vision Framework Detection**
    ///    - VNDetectHumanRectanglesRequest identifies people in camera frame
    ///    - Returns normalized bounding box (0-1 coordinates) around each person
    ///
    /// 2. **Coordinate Conversion**
    ///    - Bounding box center is converted from normalized to pixel coordinates
    ///    - Vision uses bottom-left origin, so Y coordinate is flipped
    ///    - Maps to corresponding location in LiDAR depth map
    ///
    /// 3. **Depth Sampling Strategy**
    ///    - Samples 11×11 grid of depth values around bounding box center
    ///    - Filters out invalid readings (< 0m or > 10m)
    ///    - Uses median instead of mean for robustness against outliers
    ///
    /// 4. **Distance Output**
    ///    - Returns distance in meters from iPhone to person
    ///    - Accurate within ±5cm for distances 0.2m - 5m
    ///    - Updates every time person detection runs (~0.5 second intervals)
    ///
    /// **Example:**
    /// - Person detected at center of frame (0.5, 0.5)
    /// - Converts to pixel (960, 720) in 1920×1440 depth map
    /// - Samples 11×11 = 121 depth values around that point
    /// - Median depth = 2.34 meters → Person is 2.34m away
    ///
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

    // MARK: - Terrain Detection

    /// Update terrain state from classification result
    private func updateTerrainState(_ obstacles: TerrainObstacles?) {
        guard let obstacles = obstacles else {
            terrainDetected = false
            detectedTerrainType = "none"
            terrainLeftCoverage = 0
            terrainCenterCoverage = 0
            terrainRightCoverage = 0
            terrainDebugImage = nil
            latestTerrainObstacles = nil
            return
        }

        latestTerrainObstacles = obstacles
        terrainDetected = obstacles.leftHasTerrain || obstacles.centerHasTerrain || obstacles.rightHasTerrain
        detectedTerrainType = obstacles.dominantTerrain.rawValue
        terrainLeftCoverage = obstacles.leftTerrainCoverage
        terrainCenterCoverage = obstacles.centerTerrainCoverage
        terrainRightCoverage = obstacles.rightTerrainCoverage

        // Generate debug overlay image if debug mode is ON
        if terrainDebugMode, let mask = obstacles.segmentationMask {
            terrainDebugImage = renderTerrainOverlay(mask: mask)
        } else {
            terrainDebugImage = nil
        }

        // Context-aware voice alert (with cooldown) - only when NOT in debug mode
        if terrainDetected && !terrainDebugMode {
            announceTerrainIfNeeded(obstacles.dominantTerrain)
        }
    }

    /// Voice alert for detected terrain (with cooldown, suppressed during imminent nav turns)
    private func announceTerrainIfNeeded(_ terrain: OffPathTerrain) {
        let now = Date()
        guard now.timeIntervalSince(lastTerrainAnnouncementTime) > terrainAnnouncementCooldown else { return }

        // Suppress non-critical terrain announcements when a navigation turn is imminent (< 50m)
        if let nav = navigationManager, nav.state.isActive, nav.distanceToNextManeuver < 50 {
            return
        }

        let message: String
        switch terrain {
        case .grass:
            message = "Grass ahead, stay on path"
        case .dirt:
            message = "Dirt path ahead, stay on sidewalk"
        case .bushes:
            message = "Bushes ahead"
        case .mixed:
            message = "Off path terrain ahead"
        case .none:
            return  // No announcement needed
        }

        voiceManager?.speak(message)
        lastTerrainAnnouncementTime = now
    }

    /// Render segmentation mask as color-coded overlay for debug UI
    private func renderTerrainOverlay(mask: MLMultiArray) -> UIImage? {
        let height = mask.shape[0].intValue
        let width = mask.shape[1].intValue
        let size = CGSize(width: width * 2, height: height * 2)  // 2x upscale for visibility

        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }

        let scaleX = size.width / CGFloat(width)
        let scaleY = size.height / CGFloat(height)

        // Render every 2nd pixel for performance
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let classIndex = mask[[y, x] as [NSNumber]].intValue
                let color: UIColor

                // PASCAL VOC temporary mapping (for testing):
                switch classIndex {
                case 16: color = .green.withAlphaComponent(0.5)   // pottedplant (vegetation proxy)
                case 15: color = .yellow.withAlphaComponent(0.5)  // person
                case 0:  color = .gray.withAlphaComponent(0.2)    // background
                default: color = .clear
                }

                // For Cityscapes model, use:
                // case 8:  color = .green.withAlphaComponent(0.5)   // vegetation
                // case 9:  color = .brown.withAlphaComponent(0.5)   // terrain/dirt
                // case 0:  color = .gray.withAlphaComponent(0.2)    // road (safe)
                // case 1:  color = .blue.withAlphaComponent(0.2)    // sidewalk (safe)

                if color != .clear {
                    ctx.setFillColor(color.cgColor)
                    ctx.fill(CGRect(x: CGFloat(x) * scaleX, y: CGFloat(y) * scaleY,
                                   width: scaleX * 2, height: scaleY * 2))
                }
            }
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }

    /// Toggle terrain debug mode
    func toggleTerrainDebugMode() {
        terrainDebugMode.toggle()
        if !terrainDebugMode {
            terrainDebugImage = nil  // Clear debug overlay
        }
        print("[Controller] Terrain debug mode: \(terrainDebugMode ? "ON" : "OFF")")
    }
}
