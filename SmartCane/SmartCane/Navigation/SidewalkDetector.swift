//
//  SidewalkDetector.swift
//  SmartCane
//
//  Detects sidewalk boundaries using depth discontinuity analysis
//  Uses LiDAR depth data to find curb edges and calculate centerline
//

import Foundation
import ARKit

// Result structure for sidewalk detection
struct SidewalkBoundaries {
    let leftEdgeX: Float?       // Pixel X coordinate of left curb edge (nil if not detected)
    let rightEdgeX: Float?      // Pixel X coordinate of right curb edge
    let centerlineX: Float?     // Pixel X coordinate of sidewalk centerline
    let widthMeters: Float?     // Width of detected sidewalk in meters
    let confidence: Float       // Detection confidence 0-1
    let userOffsetFromCenter: Float?  // How far user is from center (negative = left, positive = right)
    let segmentationMask: UIImage?  // NEW: Visual segmentation mask for overlay
}

enum ScanDirection {
    case leftToRight
    case rightToLeft
}

class SidewalkDetector {
    // Detection parameters
    private let edgeGradientThreshold: Float = 0.15  // 15cm depth change indicates edge
    private let minSidewalkWidth: Float = 1.0       // Minimum 1m wide to be valid sidewalk
    private let maxSidewalkWidth: Float = 4.0       // Maximum 4m wide sidewalk
    private let scanLines: [Float] = [0.4, 0.5, 0.6] // Y positions to scan (40%, 50%, 60% of height)

    // Temporal filtering
    private var previousCenterline: Float?
    private var previousLeftEdge: Float?
    private var previousRightEdge: Float?
    private let temporalSmoothingFactor: Float = 0.7  // Blend 70% previous, 30% new

    func detectBoundaries(_ frame: DepthFrame) -> SidewalkBoundaries {
        let depthMap = frame.depthMap

        // Lock pixel buffer for reading
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return SidewalkBoundaries(
                leftEdgeX: nil,
                rightEdgeX: nil,
                centerlineX: nil,
                widthMeters: nil,
                confidence: 0.0,
                userOffsetFromCenter: nil,
                segmentationMask: nil
            )
        }

        let buffer = baseAddress.assumingMemoryBound(to: Float32.self)
        let rowStride = bytesPerRow / MemoryLayout<Float32>.stride

        // Detect edges at multiple scan lines
        var leftEdges: [Float] = []
        var rightEdges: [Float] = []

        for scanLineY in scanLines {
            let y = Int(Float(height) * scanLineY)

            // Detect left edge (scan left to right)
            if let leftEdge = detectEdgeInScanLine(
                buffer: buffer,
                y: y,
                width: width,
                rowStride: rowStride,
                scanDirection: .leftToRight
            ) {
                leftEdges.append(leftEdge)
            }

            // Detect right edge (scan right to left)
            if let rightEdge = detectEdgeInScanLine(
                buffer: buffer,
                y: y,
                width: width,
                rowStride: rowStride,
                scanDirection: .rightToLeft
            ) {
                rightEdges.append(rightEdge)
            }
        }

        // Aggregate results (use median to filter outliers)
        let leftEdgeX = median(leftEdges)
        let rightEdgeX = median(rightEdges)

        // Apply temporal smoothing
        let smoothedLeftEdge = applyTemporalSmoothing(
            current: leftEdgeX,
            previous: previousLeftEdge,
            factor: temporalSmoothingFactor
        )
        let smoothedRightEdge = applyTemporalSmoothing(
            current: rightEdgeX,
            previous: previousRightEdge,
            factor: temporalSmoothingFactor
        )

        previousLeftEdge = smoothedLeftEdge
        previousRightEdge = smoothedRightEdge

        // Calculate centerline
        let centerlineX = calculateCenterline(
            leftEdge: smoothedLeftEdge,
            rightEdge: smoothedRightEdge
        )

        // Calculate sidewalk width and validate
        var widthMeters: Float? = nil
        var confidence: Float = 0.0

        if let left = smoothedLeftEdge, let right = smoothedRightEdge {
            // Calculate width in meters (approximate using depth at center)
            let centerX = Int((left + right) / 2)
            let centerY = Int(Float(height) * 0.5)
            let centerIndex = centerY * rowStride + centerX
            let centerDepth = buffer[centerIndex]

            // Approximate width using pixel distance and depth
            let pixelWidth = right - left
            let fovHorizontal: Float = 1.4  // iPhone LiDAR horizontal FOV ~80 degrees (1.4 radians)
            let pixelsPerRadian = Float(width) / fovHorizontal
            let widthRadians = pixelWidth / pixelsPerRadian
            widthMeters = centerDepth * tan(widthRadians)

            // Validate sidewalk width
            if let width = widthMeters,
               width >= minSidewalkWidth && width <= maxSidewalkWidth {
                confidence = calculateConfidence(
                    leftEdges: leftEdges,
                    rightEdges: rightEdges,
                    width: width
                )
            }
        }

        // Calculate user offset from centerline
        let userOffsetFromCenter: Float?
        if let centerline = centerlineX {
            let frameCenterX = Float(width) / 2.0
            // Convert pixel offset to meters (approximate)
            let pixelOffset = frameCenterX - centerline
            let fovHorizontal: Float = 1.4
            let pixelsPerRadian = Float(width) / fovHorizontal
            let offsetRadians = pixelOffset / pixelsPerRadian

            // Use approximate depth of 2m for offset calculation
            let approximateDepth: Float = 2.0
            userOffsetFromCenter = approximateDepth * tan(offsetRadians)
        } else {
            userOffsetFromCenter = nil
        }

        return SidewalkBoundaries(
            leftEdgeX: smoothedLeftEdge,
            rightEdgeX: smoothedRightEdge,
            centerlineX: centerlineX,
            widthMeters: widthMeters,
            confidence: confidence,
            userOffsetFromCenter: userOffsetFromCenter,
            segmentationMask: nil  // Depth-based detector doesn't generate visual mask
        )
    }

    private func detectEdgeInScanLine(
        buffer: UnsafePointer<Float32>,
        y: Int,
        width: Int,
        rowStride: Int,
        scanDirection: ScanDirection
    ) -> Float? {
        let sampleStep = 5  // Sample every 5 pixels for performance

        switch scanDirection {
        case .leftToRight:
            // Scan from left toward center, looking for sharp depth increase (curb step)
            for x in stride(from: 0, to: width / 2, by: sampleStep) {
                let currentIndex = y * rowStride + x
                let nextIndex = y * rowStride + min(x + sampleStep, width - 1)

                let currentDepth = buffer[currentIndex]
                let nextDepth = buffer[nextIndex]

                // Filter invalid depths
                if currentDepth.isNaN || currentDepth.isInfinite ||
                   nextDepth.isNaN || nextDepth.isInfinite {
                    continue
                }

                // Detect sharp increase in depth (transition from road to sidewalk)
                let gradient = nextDepth - currentDepth
                if gradient > edgeGradientThreshold {
                    return Float(x)
                }
            }

        case .rightToLeft:
            // Scan from right toward center, looking for sharp depth increase
            for x in stride(from: width - 1, to: width / 2, by: -sampleStep) {
                let currentIndex = y * rowStride + x
                let prevIndex = y * rowStride + max(x - sampleStep, 0)

                let currentDepth = buffer[currentIndex]
                let prevDepth = buffer[prevIndex]

                // Filter invalid depths
                if currentDepth.isNaN || currentDepth.isInfinite ||
                   prevDepth.isNaN || prevDepth.isInfinite {
                    continue
                }

                // Detect sharp increase in depth (transition from sidewalk to road/grass)
                let gradient = prevDepth - currentDepth
                if gradient > edgeGradientThreshold {
                    return Float(x)
                }
            }
        }

        return nil
    }

    private func calculateCenterline(leftEdge: Float?, rightEdge: Float?) -> Float? {
        guard let left = leftEdge, let right = rightEdge else { return nil }

        let center = (left + right) / 2.0

        // Apply temporal smoothing
        if let previous = previousCenterline {
            let smoothed = previous * temporalSmoothingFactor + center * (1.0 - temporalSmoothingFactor)
            previousCenterline = smoothed
            return smoothed
        } else {
            previousCenterline = center
            return center
        }
    }

    private func applyTemporalSmoothing(
        current: Float?,
        previous: Float?,
        factor: Float
    ) -> Float? {
        guard let curr = current else { return previous }

        if let prev = previous {
            return prev * factor + curr * (1.0 - factor)
        } else {
            return curr
        }
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

    private func calculateConfidence(
        leftEdges: [Float],
        rightEdges: [Float],
        width: Float
    ) -> Float {
        // Confidence based on:
        // 1. Consistency of edge detections across scan lines
        // 2. Valid sidewalk width

        var confidence: Float = 0.0

        // Factor 1: Detection consistency (how many scan lines detected edges)
        let detectionRate = Float(min(leftEdges.count, rightEdges.count)) / Float(scanLines.count)
        confidence += detectionRate * 0.5

        // Factor 2: Width validity (closer to typical sidewalk width = higher confidence)
        let typicalWidth: Float = 2.0  // 2m is typical sidewalk width
        let widthDeviation = abs(width - typicalWidth)
        let widthScore = max(0.0, 1.0 - widthDeviation / maxSidewalkWidth)
        confidence += widthScore * 0.5

        return min(confidence, 1.0)
    }
}
