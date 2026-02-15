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

    // Continuous weighting
    let lateralBias: Float             // -1.0 (obstacles biased left) to +1.0 (biased right)
    let averageLeftDistance: Float?     // avg depth of left-half pixels (x < 0.5 in display coords)
    let averageRightDistance: Float?    // avg depth of right-half pixels (x >= 0.5 in display coords)
}

class ObstacleDetector {
    // Detection parameters
    private let maxDetectionRange: Float = 4.0  // meters (extended for better forward visibility)
    private let minDetectionRange: Float = 0.2  // meters (too close to be useful)

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

        // Continuous weighting accumulators
        var lateralWeightSum: Float = 0.0
        var totalInverseDepthSum: Float = 0.0
        var leftHalfDepthSum: Float = 0.0
        var leftHalfCount: Int = 0
        var rightHalfDepthSum: Float = 0.0
        var rightHalfCount: Int = 0

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
        var left = leftMinDist.isFinite ? leftMinDist : nil
        var center = centerMinDist.isFinite ? centerMinDist : nil
        var right = rightMinDist.isFinite ? rightMinDist : nil

        // Merge terrain obstacles (inject virtual walls for terrain detection)
        if let terrain = terrainObstacles {
            let virtualWallDistance: Float = 0.6  // meters (treat terrain like a close wall)

            // Override zone distance if terrain detected AND (no real obstacle OR terrain is closer)
            if terrain.leftHasTerrain {
                left = min(left ?? Float.greatestFiniteMagnitude, virtualWallDistance)
            }
            if terrain.centerHasTerrain {
                center = min(center ?? Float.greatestFiniteMagnitude, virtualWallDistance)
            }
            if terrain.rightHasTerrain {
                right = min(right ?? Float.greatestFiniteMagnitude, virtualWallDistance)
            }

            if terrain.leftHasTerrain || terrain.centerHasTerrain || terrain.rightHasTerrain {
                print("[Obstacle] Terrain merged - L: \(left?.description ?? "nil"), C: \(center?.description ?? "nil"), R: \(right?.description ?? "nil")")
            }
        }

        // Compute continuous weighting fields
        let computedLateralBias: Float
        if totalInverseDepthSum > 0 {
            computedLateralBias = max(-1.0, min(1.0, lateralWeightSum / totalInverseDepthSum))
        } else {
            computedLateralBias = 0.0
        }
        let avgLeftDist: Float? = leftHalfCount > 0 ? leftHalfDepthSum / Float(leftHalfCount) : nil
        let avgRightDist: Float? = rightHalfCount > 0 ? rightHalfDepthSum / Float(rightHalfCount) : nil

        return ObstacleZones(
            leftDistance: left,
            centerDistance: center,
            rightDistance: right,
            leftHasObstacle: left != nil,
            centerHasObstacle: center != nil,
            rightHasObstacle: right != nil,
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
