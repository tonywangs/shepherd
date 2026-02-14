//
//  SemanticSidewalkDetector.swift
//  SmartCane
//
//  Uses DeepLabV3 semantic segmentation (Core ML) to detect walkable ground
//  and overlay a colored segmentation mask on the camera feed.
//
//  PASCAL VOC classes (21 total, indices 0-20):
//    0=background, 1=aeroplane, 2=bicycle, 3=bird, 4=boat, 5=bottle,
//    6=bus, 7=car, 8=cat, 9=chair, 10=cow, 11=diningtable, 12=dog,
//    13=horse, 14=motorbike, 15=person, 16=pottedplant, 17=sheep,
//    18=sofa, 19=train, 20=tvmonitor
//
//  Strategy: "background in lower 70% of frame" = walkable ground proxy.
//

import Foundation
import Vision
import CoreML
import ARKit
import UIKit

class SemanticSidewalkDetector {
    // Store the model (thread-safe) — create a fresh VNCoreMLRequest per inference
    private var visionModel: VNCoreMLModel?

    // Serial queue protects all mutable state and ensures one inference at a time
    private let queue = DispatchQueue(label: "com.smartcane.segmentation")
    private var isProcessing = false  // only read/written on `queue`

    // Cached results (read from any thread, written on main)
    private var lastBoundaries: SidewalkBoundaries?
    private var lastProcessTime: Date = .distantPast
    private let processingInterval: TimeInterval = 0.3  // Process every 300ms

    // Temporal smoothing (only accessed on `queue` during processing)
    private var previousCenterline: Float?
    private var previousLeftEdge: Float?
    private var previousRightEdge: Float?
    private let temporalSmoothingFactor: Float = 0.7

    // PASCAL VOC class -> RGBA color (R, G, B, A)
    // Class 0 (background) is handled specially per-pixel based on vertical position
    private let classColors: [Int: (UInt8, UInt8, UInt8, UInt8)] = {
        var map = [Int: (UInt8, UInt8, UInt8, UInt8)]()
        // Vehicles = Red (danger)
        map[6]  = (255, 50, 50, 140)   // bus
        map[7]  = (255, 50, 50, 140)   // car
        map[14] = (255, 50, 50, 140)   // motorbike
        map[19] = (255, 50, 50, 140)   // train
        // Caution = Orange/Yellow
        map[2]  = (255, 165, 0, 140)   // bicycle
        map[15] = (255, 255, 0, 140)   // person
        // Animals = Light blue
        map[3]  = (100, 180, 255, 100) // bird
        map[8]  = (100, 180, 255, 100) // cat
        map[10] = (100, 180, 255, 100) // cow
        map[12] = (100, 180, 255, 100) // dog
        map[13] = (100, 180, 255, 100) // horse
        map[17] = (100, 180, 255, 100) // sheep
        // Objects = Light blue
        map[1]  = (100, 180, 255, 100) // aeroplane
        map[4]  = (100, 180, 255, 100) // boat
        map[5]  = (100, 180, 255, 100) // bottle
        map[9]  = (100, 180, 255, 100) // chair
        map[11] = (100, 180, 255, 100) // diningtable
        map[16] = (100, 180, 255, 100) // pottedplant
        map[18] = (100, 180, 255, 100) // sofa
        map[20] = (100, 180, 255, 100) // tvmonitor
        return map
    }()

    // Background (class 0) colors
    private let walkableColor: (UInt8, UInt8, UInt8, UInt8) = (0, 255, 0, 100)  // Green, semi-transparent
    private let skyColor: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)           // Transparent

    init() {
        setupSegmentationModel()
    }

    private func setupSegmentationModel() {
        do {
            // FIX A: Use correct model filename "DeepLabV3Int8LUT"
            if let modelURL = Bundle.main.url(forResource: "DeepLabV3Int8LUT", withExtension: "mlmodelc") {
                let model = try MLModel(contentsOf: modelURL)
                visionModel = try VNCoreMLModel(for: model)
                print("[SemanticSidewalkDetector] Model loaded successfully")
            } else {
                print("[SemanticSidewalkDetector] WARNING: No segmentation model found.")
                print("[SemanticSidewalkDetector] Add DeepLabV3Int8LUT.mlmodel to project.")
            }
        } catch {
            print("[SemanticSidewalkDetector] ERROR: Failed to load model: \(error)")
        }
    }

    func detectBoundaries(_ frame: DepthFrame) -> SidewalkBoundaries {
        let now = Date()
        guard now.timeIntervalSince(lastProcessTime) > processingInterval else {
            return lastBoundaries ?? emptyBoundaries()
        }

        guard visionModel != nil else {
            return lastBoundaries ?? emptyBoundaries()
        }

        guard let pixelBuffer = frame.capturedImage else {
            return lastBoundaries ?? emptyBoundaries()
        }

        lastProcessTime = now

        // Dispatch inference to serial queue — skips if already busy
        queue.async { [weak self] in
            self?.runInference(pixelBuffer: pixelBuffer)
        }

        return lastBoundaries ?? emptyBoundaries()
    }

    /// Runs on `self.queue` — serialized, one inference at a time.
    private func runInference(pixelBuffer: CVPixelBuffer) {
        guard !isProcessing, let model = visionModel else { return }
        isProcessing = true

        // Create a fresh request for this inference (not shared, no concurrency issue)
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("[SemanticSidewalkDetector] Error performing segmentation: \(error)")
            isProcessing = false
            return
        }

        // Process results synchronously on this serial queue
        defer { isProcessing = false }

        // FIX B: DeepLabV3 returns VNCoreMLFeatureValueObservation, NOT VNPixelBufferObservation
        guard let observations = request.results as? [VNCoreMLFeatureValueObservation],
              let firstObservation = observations.first,
              let multiArray = firstObservation.featureValue.multiArrayValue else {
            print("[SemanticSidewalkDetector] No segmentation results (cast failed)")
            return
        }

        print("[SemanticSidewalkDetector] Segmentation result: \(multiArray.shape)")

        // FIX C+D: Process MLMultiArray (Int32, 513x513) with correct PASCAL VOC class mapping
        let boundaries = processSegmentationResult(multiArray)

        DispatchQueue.main.async { [weak self] in
            self?.lastBoundaries = boundaries
        }
    }

    // FIX C+D: Read Int32 values from MLMultiArray, map PASCAL VOC classes to colors
    private func processSegmentationResult(_ multiArray: MLMultiArray) -> SidewalkBoundaries {
        let shape = multiArray.shape
        // DeepLabV3 output shape is [1, 513, 513] or [513, 513]
        let height: Int
        let width: Int
        if shape.count == 3 {
            height = shape[1].intValue
            width = shape[2].intValue
        } else if shape.count == 2 {
            height = shape[0].intValue
            width = shape[1].intValue
        } else {
            print("[SemanticSidewalkDetector] Unexpected shape: \(shape)")
            return emptyBoundaries()
        }

        let pointer = multiArray.dataPointer.bindMemory(to: Int32.self, capacity: height * width)
        let groundThresholdY = Int(Float(height) * 0.3)  // Upper 30% = not ground

        // --- Generate colored mask ---
        var rgbaData = [UInt8](repeating: 0, count: width * height * 4)

        // Also track walkable pixels per scan line for boundary extraction
        // Scan at 50%, 60%, 70% height
        let scanLineRatios: [Float] = [0.5, 0.6, 0.7]
        var leftEdges: [Float] = []
        var rightEdges: [Float] = []

        for y in 0..<height {
            var rowLeftEdge: Int? = nil
            var rowRightEdge: Int? = nil

            for x in 0..<width {
                let classIdx = Int(pointer[y * width + x])
                let rgbaIndex = (y * width + x) * 4

                if classIdx == 0 {
                    // Background class
                    if y >= groundThresholdY {
                        // Lower 70% of frame: walkable ground (green)
                        rgbaData[rgbaIndex + 0] = walkableColor.0
                        rgbaData[rgbaIndex + 1] = walkableColor.1
                        rgbaData[rgbaIndex + 2] = walkableColor.2
                        rgbaData[rgbaIndex + 3] = walkableColor.3

                        // Track edges for this row
                        if rowLeftEdge == nil { rowLeftEdge = x }
                        rowRightEdge = x
                    } else {
                        // Upper 30%: transparent (sky/buildings)
                        rgbaData[rgbaIndex + 3] = 0
                    }
                } else if let color = classColors[classIdx] {
                    rgbaData[rgbaIndex + 0] = color.0
                    rgbaData[rgbaIndex + 1] = color.1
                    rgbaData[rgbaIndex + 2] = color.2
                    rgbaData[rgbaIndex + 3] = color.3
                } else {
                    // Unknown class: transparent
                    rgbaData[rgbaIndex + 3] = 0
                }
            }

            // Collect edges for scan lines
            for ratio in scanLineRatios {
                let scanY = Int(ratio * Float(height))
                if y == scanY {
                    if let left = rowLeftEdge { leftEdges.append(Float(left)) }
                    if let right = rowRightEdge { rightEdges.append(Float(right)) }
                }
            }
        }

        // Create UIImage from RGBA buffer
        let maskImage = createImage(from: &rgbaData, width: width, height: height)

        // --- Extract boundaries ---
        let leftEdgeX = median(leftEdges)
        let rightEdgeX = median(rightEdges)

        let smoothedLeft = applyTemporalSmoothing(
            current: leftEdgeX, previous: previousLeftEdge, factor: temporalSmoothingFactor
        )
        let smoothedRight = applyTemporalSmoothing(
            current: rightEdgeX, previous: previousRightEdge, factor: temporalSmoothingFactor
        )
        previousLeftEdge = smoothedLeft
        previousRightEdge = smoothedRight

        // Calculate centerline
        var centerlineX: Float? = nil
        if let left = smoothedLeft, let right = smoothedRight {
            let center = (left + right) / 2.0
            if let previous = previousCenterline {
                centerlineX = previous * temporalSmoothingFactor + center * (1.0 - temporalSmoothingFactor)
            } else {
                centerlineX = center
            }
            previousCenterline = centerlineX
        }

        // Calculate confidence
        let confidence = calculateConfidence(leftEdges: leftEdges, rightEdges: rightEdges)

        // Calculate user offset from center
        var userOffsetFromCenter: Float? = nil
        if let centerline = centerlineX {
            let frameCenterX = Float(width) / 2.0
            let pixelOffset = frameCenterX - centerline
            let fovHorizontal: Float = 1.4  // ~80 degrees
            let pixelsPerRadian = Float(width) / fovHorizontal
            let offsetRadians = pixelOffset / pixelsPerRadian
            let approximateDepth: Float = 2.0
            userOffsetFromCenter = approximateDepth * tan(offsetRadians)
        }

        // Estimate width in meters
        var widthMeters: Float? = nil
        if let left = smoothedLeft, let right = smoothedRight {
            let pixelWidth = right - left
            let fovHorizontal: Float = 1.4
            let pixelsPerRadian = Float(width) / fovHorizontal
            let widthRadians = pixelWidth / pixelsPerRadian
            let approximateDepth: Float = 2.0
            widthMeters = approximateDepth * tan(widthRadians)
        }

        return SidewalkBoundaries(
            leftEdgeX: smoothedLeft,
            rightEdgeX: smoothedRight,
            centerlineX: centerlineX,
            widthMeters: widthMeters,
            confidence: confidence,
            userOffsetFromCenter: userOffsetFromCenter,
            segmentationMask: maskImage
        )
    }

    // MARK: - Image Creation

    private func createImage(from rgbaData: inout [UInt8], width: Int, height: Int) -> UIImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let dataProvider = CGDataProvider(data: Data(rgbaData) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: dataProvider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    // MARK: - Helpers

    private func emptyBoundaries() -> SidewalkBoundaries {
        return SidewalkBoundaries(
            leftEdgeX: nil, rightEdgeX: nil, centerlineX: nil,
            widthMeters: nil, confidence: 0.0, userOffsetFromCenter: nil,
            segmentationMask: nil
        )
    }

    private func median(_ values: [Float]) -> Float? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        } else {
            return sorted[count / 2]
        }
    }

    private func applyTemporalSmoothing(current: Float?, previous: Float?, factor: Float) -> Float? {
        guard let curr = current else { return previous }
        if let prev = previous {
            return prev * factor + curr * (1.0 - factor)
        } else {
            return curr
        }
    }

    private func calculateConfidence(leftEdges: [Float], rightEdges: [Float]) -> Float {
        let detectionRate = Float(min(leftEdges.count, rightEdges.count)) / 3.0
        return min(detectionRate, 1.0)
    }
}
