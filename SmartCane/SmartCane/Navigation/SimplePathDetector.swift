//
//  SimplePathDetector.swift
//  SmartCane
//
//  Simple but functional path detection using depth + basic heuristics
//  Works immediately without external models
//

import Foundation
import ARKit
import Accelerate

class SimplePathDetector {
    // Parameters
    private let minPathWidth: Float = 0.8   // 80cm minimum path width
    private let maxPathWidth: Float = 3.5   // 3.5m maximum path width
    private let groundHeightRange: ClosedRange<Float> = 0.35...0.75  // Focus on ground level

    // Temporal smoothing
    private var previousCenterline: Float?
    private var previousLeftEdge: Float?
    private var previousRightEdge: Float?
    private let smoothingFactor: Float = 0.75  // Heavy smoothing

    func detectBoundaries(_ frame: DepthFrame) -> SidewalkBoundaries {
        let depthMap = frame.depthMap

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return emptyBoundaries()
        }

        let buffer = baseAddress.assumingMemoryBound(to: Float32.self)
        let rowStride = bytesPerRow / MemoryLayout<Float32>.stride

        // Strategy: Find the "walkable path" by looking for the widest clear area at ground level
        let scanY = Int(Float(height) * 0.6)  // 60% down = ground level

        var depthProfile: [Float] = []

        // Build depth profile across width at ground level
        for x in stride(from: 0, to: width, by: 4) {
            let index = scanY * rowStride + x
            var depth = buffer[index]

            // Clean invalid values
            if depth.isNaN || depth.isInfinite || depth < 0.2 || depth > 4.0 {
                depth = 4.0  // Treat as "far away"
            }

            depthProfile.append(depth)
        }

        // Find the widest "clear zone" (consistent depth values)
        let clearZone = findWidestClearZone(depthProfile: depthProfile, width: width)

        guard let zone = clearZone else {
            return emptyBoundaries()
        }

        // Convert indices to pixel coordinates
        let leftEdgeX = Float(zone.start * 4)
        let rightEdgeX = Float(zone.end * 4)
        let centerlineX = (leftEdgeX + rightEdgeX) / 2.0

        // Apply temporal smoothing
        let smoothedLeft = applySmoothing(current: leftEdgeX, previous: previousLeftEdge)
        let smoothedRight = applySmoothing(current: rightEdgeX, previous: previousRightEdge)
        let smoothedCenter = applySmoothing(current: centerlineX, previous: previousCenterline)

        previousLeftEdge = smoothedLeft
        previousRightEdge = smoothedRight
        previousCenterline = smoothedCenter

        // Calculate width in meters
        let pixelWidth = smoothedRight - smoothedLeft
        let widthMeters = estimateWidth(pixelWidth: pixelWidth, width: width, depth: zone.avgDepth)

        // Calculate user offset from center
        let frameCenterX = Float(width) / 2.0
        let pixelOffset = frameCenterX - smoothedCenter
        let offsetMeters = estimateOffset(pixelOffset: pixelOffset, width: width, depth: zone.avgDepth)

        // Calculate confidence
        let confidence = calculateConfidence(
            width: widthMeters,
            depthVariance: zone.variance
        )

        return SidewalkBoundaries(
            leftEdgeX: smoothedLeft,
            rightEdgeX: smoothedRight,
            centerlineX: smoothedCenter,
            widthMeters: widthMeters,
            confidence: confidence,
            userOffsetFromCenter: offsetMeters,
            segmentationMask: nil  // Simple detector doesn't generate visual mask
        )
    }

    private func findWidestClearZone(depthProfile: [Float], width: Int) -> (start: Int, end: Int, avgDepth: Float, variance: Float)? {
        guard depthProfile.count > 10 else { return nil }

        var bestZone: (start: Int, end: Int, avgDepth: Float, variance: Float)? = nil
        var maxWidth = 0

        // Sliding window to find consistent depth regions
        let windowSize = 10  // ~40 pixels

        for start in 0..<(depthProfile.count - windowSize) {
            let window = Array(depthProfile[start..<(start + windowSize)])

            // Calculate window statistics
            let avgDepth = window.reduce(0, +) / Float(window.count)
            let variance = window.map { pow($0 - avgDepth, 2) }.reduce(0, +) / Float(window.count)

            // Look for low variance (consistent depth = clear path)
            if variance < 0.15 {  // Low variance threshold
                // Try to extend the zone
                var end = start + windowSize
                while end < depthProfile.count {
                    let nextDepth = depthProfile[end]
                    if abs(nextDepth - avgDepth) < 0.3 {  // Still consistent
                        end += 1
                    } else {
                        break
                    }
                }

                let zoneWidth = end - start
                if zoneWidth > maxWidth {
                    maxWidth = zoneWidth
                    bestZone = (start: start, end: end, avgDepth: avgDepth, variance: variance)
                }
            }
        }

        // Validate zone width
        if let zone = bestZone {
            let pixelWidth = Float((zone.end - zone.start) * 4)
            let estimatedWidth = estimateWidth(pixelWidth: pixelWidth, width: width, depth: zone.avgDepth)

            if estimatedWidth >= minPathWidth && estimatedWidth <= maxPathWidth {
                return zone
            }
        }

        return nil
    }

    private func estimateWidth(pixelWidth: Float, width: Int, depth: Float) -> Float {
        // Convert pixel width to meters using depth and FOV
        let fovHorizontal: Float = 1.4  // ~80 degrees
        let pixelsPerRadian = Float(width) / fovHorizontal
        let widthRadians = pixelWidth / pixelsPerRadian
        return depth * tan(widthRadians)
    }

    private func estimateOffset(pixelOffset: Float, width: Int, depth: Float) -> Float {
        // Convert pixel offset to meters
        let fovHorizontal: Float = 1.4
        let pixelsPerRadian = Float(width) / fovHorizontal
        let offsetRadians = pixelOffset / pixelsPerRadian
        return depth * tan(offsetRadians)
    }

    private func applySmoothing(current: Float, previous: Float?) -> Float {
        guard let prev = previous else { return current }
        return prev * smoothingFactor + current * (1.0 - smoothingFactor)
    }

    private func calculateConfidence(width: Float, depthVariance: Float) -> Float {
        var confidence: Float = 0.0

        // Width confidence (1-3m is ideal)
        if width >= 1.0 && width <= 3.0 {
            confidence += 0.5
        } else if width >= minPathWidth && width <= maxPathWidth {
            confidence += 0.3
        }

        // Depth consistency confidence
        if depthVariance < 0.1 {
            confidence += 0.5
        } else if depthVariance < 0.2 {
            confidence += 0.3
        }

        return min(confidence, 1.0)
    }

    private func emptyBoundaries() -> SidewalkBoundaries {
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
}
