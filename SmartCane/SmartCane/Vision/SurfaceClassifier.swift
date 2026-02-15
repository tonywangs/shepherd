//
//  SurfaceClassifier.swift
//  SmartCane
//
//  Semantic segmentation for terrain detection (grass, dirt, bushes)
//  Uses DeepLabV3 trained on Cityscapes dataset
//

import Foundation
import Vision
import CoreML
import UIKit

/// Types of off-path terrain that users should avoid
enum OffPathTerrain: String, Sendable {
    case grass      // vegetation at ground level
    case dirt       // unpaved terrain
    case bushes     // vegetation obstacles
    case mixed      // combination
    case none
}

/// Result of terrain classification per zone
struct TerrainObstacles: Sendable {
    let leftHasTerrain: Bool
    let centerHasTerrain: Bool
    let rightHasTerrain: Bool
    let leftTerrainCoverage: Float      // 0.0-1.0
    let centerTerrainCoverage: Float
    let rightTerrainCoverage: Float
    let dominantTerrain: OffPathTerrain
    let segmentationMask: MLMultiArray?  // Optional, only populated when debug mode is ON
}

class SurfaceClassifier {
    private let model: VNCoreMLModel
    private var request: VNCoreMLRequest

    // Detection threshold (15% coverage indicates likely terrain)
    private let detectionThreshold: Float = 0.15

    // Cityscapes class indices (standard dataset)
    private let roadClass = 0          // safe - paved road
    private let sidewalkClass = 1      // safe - pedestrian path
    private let vegetationClass = 8    // grass, bushes - AVOID
    private let terrainClass = 9       // dirt, unpaved - AVOID
    private let personClass = 11       // person - for reference

    init?() {
        // Try to load the Cityscapes model (multiple potential names)
        let modelNames = [
            "DeepLabV3Cityscapes",
            "MobileViT_DeepLabV3",
            "cityscapes"
        ]

        var loadedModel: MLModel?
        var modelName: String?

        for name in modelNames {
            // Try .mlmodelc (compiled)
            if let modelURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc"),
               let mlModel = try? MLModel(contentsOf: modelURL) {
                loadedModel = mlModel
                modelName = name
                break
            }

            // Try .mlpackage (newer format)
            if let modelURL = Bundle.main.url(forResource: name, withExtension: "mlpackage"),
               let mlModel = try? MLModel(contentsOf: modelURL) {
                loadedModel = mlModel
                modelName = name
                break
            }

            // Try without extension (let system find it)
            if let modelURL = Bundle.main.url(forResource: name, withExtension: nil),
               let mlModel = try? MLModel(contentsOf: modelURL) {
                loadedModel = mlModel
                modelName = name
                break
            }
        }

        guard let mlModel = loadedModel,
              let visionModel = try? VNCoreMLModel(for: mlModel) else {
            print("[Surface] Failed to load Cityscapes model. Tried: \(modelNames.joined(separator: ", "))")
            print("[Surface] Terrain detection will be unavailable until model is added to project")
            return nil
        }

        self.model = visionModel
        self.request = VNCoreMLRequest(model: visionModel)
        self.request.imageCropAndScaleOption = .scaleFill

        print("[Surface] Loaded Cityscapes model: \(modelName ?? "unknown")")
    }

    /// Classify terrain in frame and return per-zone obstacles
    /// - Parameters:
    ///   - pixelBuffer: Camera frame to analyze
    ///   - orientation: Device orientation for correct coordinate mapping
    ///   - includeDebugMask: If true, includes full segmentation mask in result (memory intensive)
    ///   - completion: Called with TerrainObstacles result (nil on error)
    func classifyTerrain(
        _ pixelBuffer: CVPixelBuffer,
        orientation: UIDeviceOrientation,
        includeDebugMask: Bool = false,
        completion: @escaping @Sendable (TerrainObstacles?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                completion(nil)
                return
            }

            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: self.cgImageOrientation(from: orientation),
                options: [:]
            )

            do {
                try handler.perform([self.request])

                guard let results = self.request.results,
                      let observation = results.first as? VNCoreMLFeatureValueObservation,
                      let segmentationMask = observation.featureValue.multiArrayValue else {
                    print("[Surface] No segmentation results")
                    completion(nil)
                    return
                }

                // Analyze segmentation mask for terrain in each zone
                let obstacles = self.analyzeSegmentationMask(
                    segmentationMask,
                    orientation: orientation,
                    includeDebugMask: includeDebugMask
                )

                completion(obstacles)

            } catch {
                print("[Surface] Classification error: \(error)")
                completion(nil)
            }
        }
    }

    /// Analyze segmentation mask and detect terrain per zone
    private func analyzeSegmentationMask(
        _ mask: MLMultiArray,
        orientation: UIDeviceOrientation,
        includeDebugMask: Bool
    ) -> TerrainObstacles {
        let height = mask.shape[0].intValue
        let width = mask.shape[1].intValue

        // Define zones matching ObstacleDetector (0-0.33, 0.33-0.67, 0.67-1.0)
        let leftZone = 0..<Int(Float(width) * 0.33)
        let centerZone = Int(Float(width) * 0.33)..<Int(Float(width) * 0.67)
        let rightZone = Int(Float(width) * 0.67)..<width

        // Focus on forward path (vertical 0.35-0.65, matching ObstacleDetector)
        let lookAheadY = Int(Float(height) * 0.35)..<Int(Float(height) * 0.65)

        // Count terrain pixels per zone
        var leftVegCount = 0, leftTerrainCount = 0, leftTotalCount = 0
        var centerVegCount = 0, centerTerrainCount = 0, centerTotalCount = 0
        var rightVegCount = 0, rightTerrainCount = 0, rightTotalCount = 0

        // Sample every 4th pixel for performance (segmentation is expensive)
        let sampleStep = 4

        for y in stride(from: lookAheadY.lowerBound, to: lookAheadY.upperBound, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let classIndex = mask[[y, x] as [NSNumber]].intValue

                // Cityscapes classes (standard):
                let isVegetation = (classIndex == vegetationClass)  // grass, bushes
                let isTerrain = (classIndex == terrainClass)        // dirt, unpaved

                if leftZone.contains(x) {
                    leftTotalCount += 1
                    if isVegetation { leftVegCount += 1 }
                    if isTerrain { leftTerrainCount += 1 }
                } else if centerZone.contains(x) {
                    centerTotalCount += 1
                    if isVegetation { centerVegCount += 1 }
                    if isTerrain { centerTerrainCount += 1 }
                } else if rightZone.contains(x) {
                    rightTotalCount += 1
                    if isVegetation { rightVegCount += 1 }
                    if isTerrain { rightTerrainCount += 1 }
                }
            }
        }

        // Calculate coverage percentages
        let leftCoverage = Float(leftVegCount + leftTerrainCount) / Float(max(leftTotalCount, 1))
        let centerCoverage = Float(centerVegCount + centerTerrainCount) / Float(max(centerTotalCount, 1))
        let rightCoverage = Float(rightVegCount + rightTerrainCount) / Float(max(rightTotalCount, 1))

        // Threshold for terrain detection (15% coverage = likely terrain)
        let leftHas = leftCoverage > detectionThreshold
        let centerHas = centerCoverage > detectionThreshold
        let rightHas = rightCoverage > detectionThreshold

        // Determine dominant terrain type
        let totalVeg = leftVegCount + centerVegCount + rightVegCount
        let totalTerr = leftTerrainCount + centerTerrainCount + rightTerrainCount

        let dominant: OffPathTerrain
        if totalVeg == 0 && totalTerr == 0 {
            dominant = .none
        } else if totalVeg > totalTerr * 3 {
            dominant = .grass  // Mostly vegetation
        } else if totalTerr > totalVeg * 3 {
            dominant = .dirt   // Mostly terrain
        } else if totalVeg > 0 && totalTerr > 0 {
            dominant = .mixed  // Mix of both
        } else if totalVeg > 0 {
            dominant = .bushes // Some vegetation but not dominant
        } else {
            dominant = .dirt
        }

        // Log for debugging
        if leftHas || centerHas || rightHas {
            print("[Surface] L: \(Int(leftCoverage*100))% | C: \(Int(centerCoverage*100))% | R: \(Int(rightCoverage*100))% | Type: \(dominant.rawValue)")
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

    /// Convert device orientation to CGImagePropertyOrientation for Vision
    private func cgImageOrientation(from deviceOrientation: UIDeviceOrientation) -> CGImagePropertyOrientation {
        switch deviceOrientation {
        case .portrait:
            return .right
        case .portraitUpsideDown:
            return .left
        case .landscapeLeft:
            return .up
        case .landscapeRight:
            return .down
        default:
            return .right
        }
    }
}
