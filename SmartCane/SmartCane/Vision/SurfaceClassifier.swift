//
//  SurfaceClassifier.swift
//  SmartCane
//
//  Detects grass/vegetation by looking for green pixels in the camera frame.
//  No ML model needed — pure color analysis of the ARKit camera buffer.
//

import Foundation
import UIKit
import CoreML

// MARK: - Data Types

enum OffPathTerrain: String {
    case grass
    case dirt
    case bushes
    case mixed
    case none
}

struct TerrainObstacles {
    let leftTerrainCoverage: Float      // 0.0-1.0
    let centerTerrainCoverage: Float    // 0.0-1.0
    let rightTerrainCoverage: Float     // 0.0-1.0
    let dominantTerrain: OffPathTerrain
    let segmentationMask: MLMultiArray? // For debug overlay rendering

    static let coverageThreshold: Float = 0.15

    var leftHasTerrain: Bool { leftTerrainCoverage > Self.coverageThreshold }
    var centerHasTerrain: Bool { centerTerrainCoverage > Self.coverageThreshold }
    var rightHasTerrain: Bool { rightTerrainCoverage > Self.coverageThreshold }
}

// MARK: - SurfaceClassifier

class SurfaceClassifier {
    // Green detection thresholds
    private let greenDominance: Float = 20  // G must exceed R and B by this much
    private let minGreen: Float = 50        // Minimum green channel value
    private let sampleStep = 8              // Sample every 8th pixel for performance

    init() {
        print("[SurfaceClassifier] Green-pixel grass detector initialized")
    }

    // MARK: - Public API (matches SmartCaneController's call site)

    func classifyTerrain(
        _ pixelBuffer: CVPixelBuffer,
        orientation: UIDeviceOrientation,
        includeDebugMask: Bool,
        completion: @escaping (TerrainObstacles?) -> Void
    ) {
        // Run synchronously — ARKit recycles pixel buffers so we must read
        // before the next frame arrives. The work is lightweight (~26K samples)
        // and this is already throttled to 3Hz by SmartCaneController.
        let result = analyzeGreenPixels(
            pixelBuffer,
            orientation: orientation,
            includeDebugMask: includeDebugMask
        )
        completion(result)
    }

    // MARK: - Private

    /// Scan the camera frame for green pixels and map them to L/C/R zones.
    /// ARKit camera frames are bi-planar YCbCr (420f/420v).
    private func analyzeGreenPixels(
        _ pixelBuffer: CVPixelBuffer,
        orientation: UIDeviceOrientation,
        includeDebugMask: Bool
    ) -> TerrainObstacles? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        // Ensure bi-planar format (plane 0 = Y, plane 1 = CbCr)
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let cbcrBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            return nil
        }

        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let cbcrStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        let yPtr = yBase.assumingMemoryBound(to: UInt8.self)
        let cbcrPtr = cbcrBase.assumingMemoryBound(to: UInt8.self)

        // Zone counters (in raw camera coordinates — we remap for orientation later)
        var zoneGreen = [0, 0, 0]   // left, center, right
        var zoneTotal = [0, 0, 0]

        // Debug mask (80x80 grid, only populated when debug mode is on)
        let maskSize = 80
        var greenMask: [[Bool]]? = includeDebugMask
            ? Array(repeating: Array(repeating: false, count: maskSize), count: maskSize)
            : nil

        // Focus on lower 60% of raw frame (ground-facing region)
        let startY = Int(Float(height) * 0.4)

        for y in stride(from: startY, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                // Read Y (full res)
                let yVal = Float(yPtr[y * yStride + x])

                // Read Cb, Cr (half res, interleaved)
                let cbcrOffset = (y / 2) * cbcrStride + (x / 2) * 2
                let cb = Float(cbcrPtr[cbcrOffset])
                let cr = Float(cbcrPtr[cbcrOffset + 1])

                // YCbCr → RGB (BT.601 full range)
                let r = yVal + 1.402 * (cr - 128.0)
                let g = yVal - 0.344136 * (cb - 128.0) - 0.714136 * (cr - 128.0)
                let b = yVal + 1.772 * (cb - 128.0)

                // Determine which zone (raw X divided into thirds)
                let normalizedX = Float(x) / Float(width)
                let zone: Int
                if normalizedX < 0.33 { zone = 0 }
                else if normalizedX < 0.67 { zone = 1 }
                else { zone = 2 }

                zoneTotal[zone] += 1

                if isGreen(r: r, g: g, b: b) {
                    zoneGreen[zone] += 1

                    // Mark debug mask pixel
                    if greenMask != nil {
                        let mx = min(maskSize - 1, Int(normalizedX * Float(maskSize)))
                        let my = min(maskSize - 1, Int(Float(y) / Float(height) * Float(maskSize)))
                        greenMask![my][mx] = true
                    }
                }
            }
        }

        // Raw coverage per zone
        let rawCoverage: [Float] = (0..<3).map { i in
            zoneTotal[i] > 0 ? Float(zoneGreen[i]) / Float(zoneTotal[i]) : 0
        }

        // Remap zones for device orientation (must match ObstacleDetector's logic)
        let leftCoverage: Float
        let centerCoverage: Float
        let rightCoverage: Float
        switch orientation {
        case .portrait:
            // Raw right zone → display left, raw left zone → display right
            leftCoverage = rawCoverage[2]
            centerCoverage = rawCoverage[1]
            rightCoverage = rawCoverage[0]
        default:
            leftCoverage = rawCoverage[0]
            centerCoverage = rawCoverage[1]
            rightCoverage = rawCoverage[2]
        }

        // If no significant green anywhere, return nil
        let maxCoverage = max(leftCoverage, centerCoverage, rightCoverage)
        guard maxCoverage > 0.10 else { return nil }

        // Build MLMultiArray debug mask if requested
        let debugMask: MLMultiArray? = includeDebugMask
            ? buildDebugMask(from: greenMask!, size: maskSize)
            : nil

        return TerrainObstacles(
            leftTerrainCoverage: leftCoverage,
            centerTerrainCoverage: centerCoverage,
            rightTerrainCoverage: rightCoverage,
            dominantTerrain: .grass,
            segmentationMask: debugMask
        )
    }

    /// Simple green check: green channel clearly dominates red and blue.
    private func isGreen(r: Float, g: Float, b: Float) -> Bool {
        return g > (r + greenDominance) && g > (b + greenDominance) && g > minGreen
    }

    /// Convert the boolean green-pixel grid into an MLMultiArray for renderTerrainOverlay.
    /// Uses class index 16 which renders green in SmartCaneController's debug overlay.
    private func buildDebugMask(from grid: [[Bool]], size: Int) -> MLMultiArray? {
        guard let mask = try? MLMultiArray(
            shape: [NSNumber(value: size), NSNumber(value: size)],
            dataType: .int32
        ) else { return nil }

        for y in 0..<size {
            for x in 0..<size {
                mask[y * size + x] = grid[y][x] ? 16 : 0
            }
        }
        return mask
    }
}
