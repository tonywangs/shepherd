//
//  ObstacleDetector.swift
//  SmartCane
//
//  Analyzes depth map and divides into left/center/right zones
//  Returns nearest obstacle distance in each zone
//

import Foundation
import ARKit
import Accelerate

// Zone analysis result
struct ObstacleZones {
    let leftDistance: Float?      // meters, nil if no obstacle
    let centerDistance: Float?
    let rightDistance: Float?

    let leftHasObstacle: Bool
    let centerHasObstacle: Bool
    let rightHasObstacle: Bool

    // Gap-seeking steering: direction of maximum clearance
    let gapDirection: Float        // -1.0 (gap is left) to +1.0 (gap is right), 0.0 = center
    let closestDistance: Float?    // nearest obstacle across all zones (meters)

    // Legacy (kept for UI/debug display)
    let lateralBias: Float             // -1.0 (obstacles biased left) to +1.0 (biased right)
    let averageLeftDistance: Float?     // avg depth of left-half pixels (x < 0.5 in display coords)
    let averageRightDistance: Float?    // avg depth of right-half pixels (x >= 0.5 in display coords)
}

class ObstacleDetector {
    // Detection parameters
    private let maxDetectionRange: Float = 4.0  // meters (extended for better forward visibility)
    private let minDetectionRange: Float = 0.2  // meters (too close to be useful)

    // Gap profiling: divide horizontal FOV into columns to find clearest path
    private let numGapColumns = 16

    // Running average buffer for gapDirection (smooths depth noise across frames)
    private let gapHistorySize = 5
    private var gapHistory: [Float] = []

    // Zone division (in camera frame coordinates)
    // Camera is 16:9, we divide horizontally into 3 zones
    private let leftZoneX: ClosedRange<Float> = 0.0...0.33
    private let centerZoneX: ClosedRange<Float> = 0.33...0.67
    private let rightZoneX: ClosedRange<Float> = 0.67...1.0

    // Vertical zone (focus on forward path, ignore floor/ceiling)
    private let verticalZone: ClosedRange<Float> = 0.35...0.65

    // Transform zone coordinates based on device orientation to fix coordinate mismatch
    private func getTransformedZones(for orientation: UIDeviceOrientation) -> (left: ClosedRange<Float>, center: ClosedRange<Float>, right: ClosedRange<Float>) {
        switch orientation {
        case .portrait:
            // 90° clockwise rotation: After rotation, what was on the right in raw coordinates
            // appears on the left in the display, and vice versa
            return (
                left: rightZoneX,      // Raw right → Display left
                center: centerZoneX,   // Center stays center
                right: leftZoneX       // Raw left → Display right
            )
        case .portraitUpsideDown:
            // 180° rotation: Complete flip
            return (
                left: leftZoneX,
                center: centerZoneX,
                right: rightZoneX
            )
        case .landscapeLeft, .landscapeRight:
            // No rotation needed in landscape (camera orientation matches display)
            return (
                left: leftZoneX,
                center: centerZoneX,
                right: rightZoneX
            )
        default:
            // Default to portrait behavior
            return (
                left: rightZoneX,
                center: centerZoneX,
                right: leftZoneX
            )
        }
    }

    func analyzeDepthFrame(_ frame: DepthFrame, orientation: UIDeviceOrientation = .portrait, terrainObstacles: TerrainObstacles? = nil) -> ObstacleZones {
        let depthMap = frame.depthMap

        // Lock pixel buffer for reading
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return ObstacleZones(leftDistance: nil, centerDistance: nil, rightDistance: nil,
                               leftHasObstacle: false, centerHasObstacle: false, rightHasObstacle: false,
                               gapDirection: 0.0, closestDistance: nil,
                               lateralBias: 0.0, averageLeftDistance: nil, averageRightDistance: nil)
        }

        // Depth map is Float32 format (meters)
        let buffer = baseAddress.assumingMemoryBound(to: Float32.self)

        // Get orientation-adjusted zones
        let zones = getTransformedZones(for: orientation)

        // Orientation handling for continuous model
        let flipHorizontal: Bool
        switch orientation {
        case .portrait:
            flipHorizontal = true   // raw X right = display left
        default:
            flipHorizontal = false
        }

        // Continuous weighting accumulators (legacy, kept for UI)
        var lateralWeightSum: Float = 0.0
        var totalInverseDepthSum: Float = 0.0
        var leftHalfDepthSum: Float = 0.0
        var leftHalfCount: Int = 0
        var rightHalfDepthSum: Float = 0.0
        var rightHalfCount: Int = 0

        // Gap profiling: average depth per horizontal column (display coordinates)
        var columnDepthSum = [Float](repeating: 0.0, count: numGapColumns)
        var columnCount = [Int](repeating: 0, count: numGapColumns)

        // Sample zones
        var leftMinDist: Float = Float.greatestFiniteMagnitude
        var centerMinDist: Float = Float.greatestFiniteMagnitude
        var rightMinDist: Float = Float.greatestFiniteMagnitude

        // Sample grid within each zone (for performance, don't check every pixel)
        let sampleStep = 8
        let rowStride = bytesPerRow / MemoryLayout<Float32>.stride

        for y in stride(from: Int(Float(height) * verticalZone.lowerBound),
                       to: Int(Float(height) * verticalZone.upperBound),
                       by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let normalizedX = Float(x) / Float(width)
                let index = y * rowStride + x

                var depth = buffer[index]

                // Filter invalid/out-of-range depths
                if depth.isNaN || depth.isInfinite || depth < minDetectionRange || depth > maxDetectionRange {
                    continue
                }

                // Filter floor/ground pixels to eliminate false positives
                if isLikelyFloor(depthBuffer: buffer, x: x, y: y,
                                width: width, height: height, rowStride: rowStride) {
                    continue
                }

                // Continuous weighting: map normalizedX to display coords [-1, +1]
                let rawPosition = (normalizedX - 0.5) * 2.0
                let horizontalPosition = flipHorizontal ? -rawPosition : rawPosition
                let inverseDepth = 1.0 / depth
                lateralWeightSum += inverseDepth * horizontalPosition
                totalInverseDepthSum += inverseDepth

                // Accumulate average distances per display-half
                let isLeftHalf = flipHorizontal ? (normalizedX >= 0.5) : (normalizedX < 0.5)
                if isLeftHalf {
                    leftHalfDepthSum += depth
                    leftHalfCount += 1
                } else {
                    rightHalfDepthSum += depth
                    rightHalfCount += 1
                }

                // Gap profiling: accumulate depth per column in display coordinates
                let displayX = flipHorizontal ? (1.0 - normalizedX) : normalizedX
                let colIdx = min(numGapColumns - 1, max(0, Int(displayX * Float(numGapColumns))))
                columnDepthSum[colIdx] += depth
                columnCount[colIdx] += 1

                // Categorize into zones using transformed coordinates
                if zones.left.contains(normalizedX) {
                    leftMinDist = min(leftMinDist, depth)
                } else if zones.center.contains(normalizedX) {
                    centerMinDist = min(centerMinDist, depth)
                } else if zones.right.contains(normalizedX) {
                    rightMinDist = min(rightMinDist, depth)
                }
            }
        }

        // Convert infinities to nil
        let left = leftMinDist.isFinite ? leftMinDist : nil
        let center = centerMinDist.isFinite ? centerMinDist : nil
        let right = rightMinDist.isFinite ? rightMinDist : nil

        // Compute continuous weighting fields (legacy)
        let computedLateralBias: Float
        if totalInverseDepthSum > 0 {
            computedLateralBias = max(-1.0, min(1.0, lateralWeightSum / totalInverseDepthSum))
        } else {
            computedLateralBias = 0.0
        }
        let avgLeftDist: Float? = leftHalfCount > 0 ? leftHalfDepthSum / Float(leftHalfCount) : nil
        let avgRightDist: Float? = rightHalfCount > 0 ? rightHalfDepthSum / Float(rightHalfCount) : nil

        // Gap profiling: find the direction with maximum average depth (most clearance)
        // 1. Compute average depth per column
        var columnAvg = [Float](repeating: 0.0, count: numGapColumns)
        for i in 0..<numGapColumns {
            columnAvg[i] = columnCount[i] > 0 ? columnDepthSum[i] / Float(columnCount[i]) : 0.0
        }

        // 2. Smooth columns with [0.25, 0.5, 0.25] kernel to reduce single-pixel noise
        var smoothedColumns = [Float](repeating: 0.0, count: numGapColumns)
        for i in 0..<numGapColumns {
            let l = i > 0 ? columnAvg[i - 1] : columnAvg[i]
            let c = columnAvg[i]
            let r = i < numGapColumns - 1 ? columnAvg[i + 1] : columnAvg[i]
            smoothedColumns[i] = 0.25 * l + 0.5 * c + 0.25 * r
        }

        // 3. Find the column with maximum clearance (deepest average depth = the gap)
        var bestColumn = numGapColumns / 2  // default to center
        var bestDepth: Float = 0.0
        for i in 0..<numGapColumns {
            if smoothedColumns[i] > bestDepth {
                bestDepth = smoothedColumns[i]
                bestColumn = i
            }
        }

        // 4. Convert column index to normalized direction: -1.0 (left) to +1.0 (right)
        let rawGapDirection: Float
        if bestDepth > 0 {
            rawGapDirection = (Float(bestColumn) / Float(numGapColumns - 1) - 0.5) * 2.0
        } else {
            rawGapDirection = 0.0  // No valid depth data
        }

        // 5. Smooth gapDirection with running average to eliminate frame-to-frame jitter.
        //    Without this, depth noise causes gapDirection to flip sign between frames,
        //    and the ESP32's leaky integrator never ramps up.
        gapHistory.append(rawGapDirection)
        if gapHistory.count > gapHistorySize {
            gapHistory.removeFirst()
        }
        let computedGapDirection = gapHistory.reduce(0.0, +) / Float(gapHistory.count)

        // Closest obstacle across all zones
        let closest = [left, center, right].compactMap { $0 }.min()

        return ObstacleZones(
            leftDistance: left,
            centerDistance: center,
            rightDistance: right,
            leftHasObstacle: left != nil,
            centerHasObstacle: center != nil,
            rightHasObstacle: right != nil,
            gapDirection: computedGapDirection,
            closestDistance: closest,
            lateralBias: computedLateralBias,
            averageLeftDistance: avgLeftDist,
            averageRightDistance: avgRightDist
        )
    }

    /// Detect if a depth region is likely floor/ground using depth gradients
    /// This helps eliminate false positives from ground detection
    private func isLikelyFloor(depthBuffer: UnsafePointer<Float32>,
                              x: Int, y: Int,
                              width: Int, height: Int,
                              rowStride: Int) -> Bool {
        // Sample depth at current position and below
        let currentIndex = y * rowStride + x
        let currentDepth = depthBuffer[currentIndex]

        // Check if we have a row below to compare
        guard y + 8 < height else { return false }

        let belowIndex = (y + 8) * rowStride + x
        let belowDepth = depthBuffer[belowIndex]

        // Floor characteristics:
        // 1. Depth increases gradually as we look down (floor slopes away)
        // 2. Depth change is consistent (not sudden like a wall edge)
        let depthDiff = belowDepth - currentDepth

        // If depth increases by more than 0.5m over 8 pixels vertically,
        // and depth is > 1.0m, it's likely floor (not close obstacle)
        if depthDiff > 0.5 && currentDepth > 1.0 {
            return true
        }

        // If depth is very similar vertically (< 0.1m difference),
        // but we're in lower part of frame, likely floor
        if abs(depthDiff) < 0.1 && Float(y) / Float(height) > 0.6 {
            return true
        }

        return false
    }
}
