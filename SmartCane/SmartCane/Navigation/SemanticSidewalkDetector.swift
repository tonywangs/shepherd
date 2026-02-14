//
//  SemanticSidewalkDetector.swift
//  SmartCane
//
//  Uses semantic segmentation (Core ML) to detect sidewalk boundaries
//  More robust than depth-based approach
//

import Foundation
import Vision
import CoreML
import ARKit
import UIKit

class SemanticSidewalkDetector {
    // Model and Vision request
    private var segmentationRequest: VNCoreMLRequest?
    private var isProcessing = false

    // Cached results for smooth operation
    private var lastBoundaries: SidewalkBoundaries?
    private var lastProcessTime: Date = .distantPast
    private let processingInterval: TimeInterval = 0.3  // Process every 300ms (not every frame)

    // Temporal smoothing
    private var previousCenterline: Float?
    private var previousLeftEdge: Float?
    private var previousRightEdge: Float?
    private let temporalSmoothingFactor: Float = 0.7

    // Segmentation classes (Cityscapes dataset standard)
    // These indices correspond to common semantic segmentation models
    private let roadClassIndices: Set<Int> = [0, 1]  // road, sidewalk (model-specific)
    private let sidewalkClassIndex = 1  // Typically sidewalk class

    init() {
        setupSegmentationModel()
    }

    private func setupSegmentationModel() {
        // Try to load a semantic segmentation model
        // Note: User needs to add a .mlmodel file to the project
        // Options:
        // 1. DeepLabV3 from Apple
        // 2. Custom trained model
        // 3. Cityscapes-trained model

        do {
            // Try to load a semantic segmentation model
            // This will fail gracefully if model not present
            if let modelURL = Bundle.main.url(forResource: "DeepLabV3", withExtension: "mlmodelc") {
                let model = try MLModel(contentsOf: modelURL)
                let visionModel = try VNCoreMLModel(for: model)

                let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
                    self?.handleSegmentationResult(request: request, error: error)
                }

                request.imageCropAndScaleOption = .scaleFit
                segmentationRequest = request

                print("[SemanticSidewalkDetector] Model loaded successfully")
            } else {
                print("[SemanticSidewalkDetector] WARNING: No segmentation model found. Using fallback method.")
                print("[SemanticSidewalkDetector] Add DeepLabV3.mlmodel to project or use alternative approach.")
            }
        } catch {
            print("[SemanticSidewalkDetector] ERROR: Failed to load model: \(error)")
            print("[SemanticSidewalkDetector] Falling back to simple edge detection")
        }
    }

    func detectBoundaries(_ frame: DepthFrame) -> SidewalkBoundaries {
        // Throttle processing - don't run on every frame
        let now = Date()
        guard now.timeIntervalSince(lastProcessTime) > processingInterval else {
            // Return cached result
            return lastBoundaries ?? SidewalkBoundaries(
                leftEdgeX: nil, rightEdgeX: nil, centerlineX: nil,
                widthMeters: nil, confidence: 0.0, userOffsetFromCenter: nil
            )
        }

        guard !isProcessing else {
            return lastBoundaries ?? SidewalkBoundaries(
                leftEdgeX: nil, rightEdgeX: nil, centerlineX: nil,
                widthMeters: nil, confidence: 0.0, userOffsetFromCenter: nil
            )
        }

        lastProcessTime = now

        // If we have a segmentation model, use it
        if let request = segmentationRequest {
            performSemanticSegmentation(frame: frame, request: request)
        } else {
            // Fallback: Use simple horizon-based approach
            return fallbackHorizonDetection(frame: frame)
        }

        // Return last known boundaries while processing
        return lastBoundaries ?? SidewalkBoundaries(
            leftEdgeX: nil, rightEdgeX: nil, centerlineX: nil,
            widthMeters: nil, confidence: 0.0, userOffsetFromCenter: nil
        )
    }

    private func performSemanticSegmentation(frame: DepthFrame, request: VNCoreMLRequest) {
        isProcessing = true

        guard let pixelBuffer = frame.capturedImage else {
            isProcessing = false
            return
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try handler.perform([request])
            } catch {
                print("[SemanticSidewalkDetector] Error performing segmentation: \(error)")
                self?.isProcessing = false
            }
        }
    }

    private func handleSegmentationResult(request: VNRequest, error: Error?) {
        defer { isProcessing = false }

        if let error = error {
            print("[SemanticSidewalkDetector] Segmentation error: \(error)")
            return
        }

        guard let observations = request.results as? [VNPixelBufferObservation],
              let segmentationMap = observations.first?.pixelBuffer else {
            print("[SemanticSidewalkDetector] No segmentation results")
            return
        }

        // Process segmentation map to find sidewalk boundaries
        let boundaries = processSegmentationMap(segmentationMap)

        DispatchQueue.main.async { [weak self] in
            self?.lastBoundaries = boundaries
        }
    }

    private func processSegmentationMap(_ segmentationMap: CVPixelBuffer) -> SidewalkBoundaries {
        CVPixelBufferLockBaseAddress(segmentationMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(segmentationMap, .readOnly) }

        let width = CVPixelBufferGetWidth(segmentationMap)
        let height = CVPixelBufferGetHeight(segmentationMap)

        guard let baseAddress = CVPixelBufferGetBaseAddress(segmentationMap) else {
            return SidewalkBoundaries(
                leftEdgeX: nil, rightEdgeX: nil, centerlineX: nil,
                widthMeters: nil, confidence: 0.0, userOffsetFromCenter: nil
            )
        }

        // Assume segmentation map is UInt8 with class indices
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(segmentationMap)

        // Scan horizontal lines to find sidewalk edges
        var leftEdges: [Float] = []
        var rightEdges: [Float] = []

        // Sample at 40%, 50%, 60% height (ground level)
        let scanLines: [Float] = [0.5, 0.6, 0.7]

        for scanLineY in scanLines {
            let y = Int(Float(height) * scanLineY)

            // Find leftmost and rightmost sidewalk pixels
            var leftEdge: Int? = nil
            var rightEdge: Int? = nil

            // Scan left to right
            for x in 0..<width {
                let index = y * bytesPerRow + x
                let classIdx = Int(buffer[index])

                // Check if pixel is sidewalk/road class
                if roadClassIndices.contains(classIdx) {
                    if leftEdge == nil {
                        leftEdge = x
                    }
                    rightEdge = x  // Keep updating to get rightmost
                }
            }

            if let left = leftEdge {
                leftEdges.append(Float(left))
            }
            if let right = rightEdge {
                rightEdges.append(Float(right))
            }
        }

        // Calculate median edges
        let leftEdgeX = median(leftEdges)
        let rightEdgeX = median(rightEdges)

        // Apply temporal smoothing
        let smoothedLeft = applyTemporalSmoothing(
            current: leftEdgeX,
            previous: previousLeftEdge,
            factor: temporalSmoothingFactor
        )
        let smoothedRight = applyTemporalSmoothing(
            current: rightEdgeX,
            previous: previousRightEdge,
            factor: temporalSmoothingFactor
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

        // Calculate confidence based on detection consistency
        let confidence = calculateConfidence(leftEdges: leftEdges, rightEdges: rightEdges)

        // Calculate user offset from centerline
        var userOffsetFromCenter: Float? = nil
        if let centerline = centerlineX {
            let frameCenterX = Float(width) / 2.0
            let pixelOffset = frameCenterX - centerline

            // Convert to meters (approximate)
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
            userOffsetFromCenter: userOffsetFromCenter
        )
    }

    private func fallbackHorizonDetection(frame: DepthFrame) -> SidewalkBoundaries {
        // Simple fallback: Use Vision's horizon detection + depth analysis
        // This is more reliable than pure depth gradients

        guard let pixelBuffer = frame.capturedImage else {
            return SidewalkBoundaries(
                leftEdgeX: nil, rightEdgeX: nil, centerlineX: nil,
                widthMeters: nil, confidence: 0.0, userOffsetFromCenter: nil
            )
        }

        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])

            if let result = request.results?.first {
                let horizon = result.transform
                // Use horizon angle to estimate sidewalk region
                // This is a simplified approach
                print("[SemanticSidewalkDetector] Horizon detected at angle: \(result.angle)")
            }
        } catch {
            print("[SemanticSidewalkDetector] Horizon detection failed: \(error)")
        }

        // For now, return no detection
        return SidewalkBoundaries(
            leftEdgeX: nil, rightEdgeX: nil, centerlineX: nil,
            widthMeters: nil, confidence: 0.0, userOffsetFromCenter: nil
        )
    }

    // MARK: - Helper Methods

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
        let detectionRate = Float(min(leftEdges.count, rightEdges.count)) / 3.0  // 3 scan lines
        return min(detectionRate, 1.0)
    }
}
