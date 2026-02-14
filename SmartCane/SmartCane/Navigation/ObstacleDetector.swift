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
    private let verticalZone: ClosedRange<Float> = 0.3...0.7

    func analyzeDepthFrame(_ frame: DepthFrame) -> ObstacleZones {
        let depthMap = frame.depthMap

        // Lock pixel buffer for reading
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return ObstacleZones(leftDistance: nil, centerDistance: nil, rightDistance: nil,
                               leftHasObstacle: false, centerHasObstacle: false, rightHasObstacle: false)
        }

        // Depth map is Float32 format (meters)
        let buffer = baseAddress.assumingMemoryBound(to: Float32.self)

        // Sample zones
        var leftMinDist: Float = Float.greatestFiniteMagnitude
        var centerMinDist: Float = Float.greatestFiniteMagnitude
        var rightMinDist: Float = Float.greatestFiniteMagnitude

        // Sample grid within each zone (for performance, don't check every pixel)
        let sampleStep = 8

        for y in stride(from: Int(Float(height) * verticalZone.lowerBound),
                       to: Int(Float(height) * verticalZone.upperBound),
                       by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let normalizedX = Float(x) / Float(width)
                let index = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x

                var depth = buffer[index]

                // Filter invalid/out-of-range depths
                if depth.isNaN || depth.isInfinite || depth < minDetectionRange || depth > maxDetectionRange {
                    continue
                }

                // Categorize into zones
                if leftZoneX.contains(normalizedX) {
                    leftMinDist = min(leftMinDist, depth)
                } else if centerZoneX.contains(normalizedX) {
                    centerMinDist = min(centerMinDist, depth)
                } else if rightZoneX.contains(normalizedX) {
                    rightMinDist = min(rightMinDist, depth)
                }
            }
        }

        // Convert infinities to nil
        let left = leftMinDist.isFinite ? leftMinDist : nil
        let center = centerMinDist.isFinite ? centerMinDist : nil
        let right = rightMinDist.isFinite ? rightMinDist : nil

        return ObstacleZones(
            leftDistance: left,
            centerDistance: center,
            rightDistance: right,
            leftHasObstacle: left != nil,
            centerHasObstacle: center != nil,
            rightHasObstacle: right != nil
        )
    }
}
