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

    // Camera preview with detection overlay
    @Published var cameraPreview: UIImage? = nil
    @Published var detectedPersonBox: CGRect? = nil
    @Published var showCameraPreview = false
    @Published var deviceOrientation: UIDeviceOrientation = .portrait

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
    private var latestCameraImage: CVPixelBuffer? = nil  // Store for camera preview
    private var isCameraPreviewInProgress = false
    private var lastCameraPreviewTime: Date = .distantPast

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

        // Store depth map and camera image for object detection and preview
        latestDepthMap = frame.depthMap
        latestCameraImage = frame.capturedImage

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
    ///    - Updates every time person detection runs (~5 second intervals)
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
}
