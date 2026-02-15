//
//  SurfaceClassifier.swift
//  SmartCane
//
//  Semantic segmentation-based terrain classifier.
//  Detects off-path surfaces (grass, dirt, bushes) using DeepLabV3.
//

import Foundation
import CoreML
import Vision
import UIKit

/// Types of off-path terrain the classifier can detect
enum OffPathTerrain: String {
    case grass
    case dirt
    case bushes
    case mixed
    case none
}

/// Per-zone terrain analysis result
struct TerrainObstacles {
    let leftHasTerrain: Bool
    let centerHasTerrain: Bool
    let rightHasTerrain: Bool

    let leftTerrainCoverage: Float    // 0.0-1.0
    let centerTerrainCoverage: Float
    let rightTerrainCoverage: Float

    let dominantTerrain: OffPathTerrain
    let segmentationMask: MLMultiArray?  // Raw class predictions for debug overlay
}

/// Classifies camera frames to detect off-path terrain using semantic segmentation.
class SurfaceClassifier {
    private var model: VNCoreMLModel?

    init?() {
        // Disabled until teammate pushes full SurfaceClassifier implementation.
        // The controller handles nil gracefully (terrain classification skipped).
        return nil
    }

    /// Classify terrain in a camera frame.
    /// - Parameters:
    ///   - pixelBuffer: Camera image
    ///   - orientation: Device orientation for coordinate transforms
    ///   - includeDebugMask: Whether to include the raw segmentation mask (expensive)
    ///   - completion: Called with TerrainObstacles result, or nil on failure
    func classifyTerrain(
        _ pixelBuffer: CVPixelBuffer,
        orientation: UIDeviceOrientation,
        includeDebugMask: Bool,
        completion: @escaping (TerrainObstacles?) -> Void
    ) {
        guard let model = model else {
            completion(nil)
            return
        }

        let request = VNCoreMLRequest(model: model) { request, error in
            guard error == nil,
                  let results = request.results as? [VNCoreMLFeatureValueObservation],
                  let multiArray = results.first?.featureValue.multiArrayValue else {
                completion(nil)
                return
            }

            let obstacles = self.analyzeSegmentation(multiArray, includeDebugMask: includeDebugMask)
            completion(obstacles)
        }

        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("[SurfaceClassifier] Classification failed: \(error)")
                completion(nil)
            }
        }
    }

    /// Analyze segmentation mask into per-zone terrain coverage.
    private func analyzeSegmentation(_ mask: MLMultiArray, includeDebugMask: Bool) -> TerrainObstacles {
        let height = mask.shape[0].intValue
        let width = mask.shape[1].intValue

        // Zone boundaries (same as ObstacleDetector)
        let leftEnd = width / 3
        let rightStart = width * 2 / 3

        // Only analyze lower portion of frame (terrain is on the ground)
        let yStart = height / 2

        var leftTerrainPixels = 0, leftTotalPixels = 0
        var centerTerrainPixels = 0, centerTotalPixels = 0
        var rightTerrainPixels = 0, rightTotalPixels = 0

        let step = 2  // Sample every 2nd pixel for performance
        for y in stride(from: yStart, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let classIndex = mask[[y, x] as [NSNumber]].intValue

                // PASCAL VOC class mapping:
                // 16 = pottedplant (vegetation proxy for grass/bushes)
                let isTerrain = (classIndex == 16)

                if x < leftEnd {
                    leftTotalPixels += 1
                    if isTerrain { leftTerrainPixels += 1 }
                } else if x >= rightStart {
                    rightTotalPixels += 1
                    if isTerrain { rightTerrainPixels += 1 }
                } else {
                    centerTotalPixels += 1
                    if isTerrain { centerTerrainPixels += 1 }
                }
            }
        }

        let leftCoverage = leftTotalPixels > 0 ? Float(leftTerrainPixels) / Float(leftTotalPixels) : 0
        let centerCoverage = centerTotalPixels > 0 ? Float(centerTerrainPixels) / Float(centerTotalPixels) : 0
        let rightCoverage = rightTotalPixels > 0 ? Float(rightTerrainPixels) / Float(rightTotalPixels) : 0

        let threshold: Float = 0.15  // 15% coverage = terrain detected
        let leftHas = leftCoverage > threshold
        let centerHas = centerCoverage > threshold
        let rightHas = rightCoverage > threshold

        // Determine dominant terrain type (simplified: all vegetation for now)
        let dominant: OffPathTerrain
        if leftHas || centerHas || rightHas {
            dominant = .grass  // DeepLabV3 pottedplant class → treat as grass
        } else {
            dominant = .none
        }

        return TerrainObstacles(
            leftHasTerrain: leftHas,
            centerHasTerrain: centerHas,
            rightHasTerrain: rightHas,
            leftTerrainCoverage: leftCoverage,
            centerTerrainCoverage: centerCoverage,
            rightTerrainCoverage: rightCoverage,
            dominantTerrain: dominant,
            segmentationMask: includeDebugMask ? mask : nil
        )
    }
}
