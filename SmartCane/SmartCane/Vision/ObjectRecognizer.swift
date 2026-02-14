//
//  ObjectRecognizer.swift
//  SmartCane
//
//  Phase 2: Object recognition using Vision framework
//  Identifies obstacles and announces them via voice
//

import Foundation
import Vision
import CoreImage
import AVFoundation
import Combine

// Detection result with bounding box for distance calculation
struct DetectionResult: Sendable {
    let objectName: String
    let boundingBox: CGRect  // Normalized coordinates (0-1)
}

class ObjectRecognizer: ObservableObject {
    @Published var detectedObjects: [String] = []

    private var lastAnnouncementTime: Date = .distantPast
    private let announcementCooldown: TimeInterval = 3.0 // seconds between announcements

    // Process camera frame for object detection
    func processFrame(_ pixelBuffer: CVPixelBuffer, completion: @escaping @Sendable (String?) -> Void) {
        // Use Vision framework for object recognition
        let request = VNRecognizeAnimalsRequest { [weak self] request, error in
            if let error = error {
                print("[Vision] Error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            self?.handleDetectionResults(request.results, completion: completion)
        }

        // Perform request
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("[Vision] Failed to perform request: \(error)")
                completion(nil)
            }
        }
    }

    // Alternative: Use scene classification
    func classifyScene(_ pixelBuffer: CVPixelBuffer, completion: @escaping @Sendable (String?) -> Void) {
        // Create request on background queue to avoid blocking
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                completion(nil)
                return
            }

            let request = VNClassifyImageRequest { request, error in
                if let error = error {
                    print("[Vision] Error: \(error.localizedDescription)")
                    completion(nil)
                    return
                }

                // Handle results inline to avoid Sendable issues
                guard let observations = request.results as? [VNClassificationObservation] else {
                    completion(nil)
                    return
                }

                // Get highest confidence classification
                guard let topObservation = observations.first,
                      topObservation.confidence > 0.3 else {
                    completion(nil)
                    return
                }

                let className = topObservation.identifier
                print("[Vision] Classified: \(className) (confidence: \(topObservation.confidence))")

                // Filter for relevant objects
                let relevantKeywords = ["wall", "door", "person", "chair", "table", "car", "tree"]
                let isRelevant = relevantKeywords.contains { className.lowercased().contains($0) }

                if isRelevant {
                    // Throttle announcements
                    let now = Date()
                    if now.timeIntervalSince(self.lastAnnouncementTime) > self.announcementCooldown {
                        self.lastAnnouncementTime = now
                        completion(className)
                        return
                    }
                }

                completion(nil)
            }

            // Specify orientation for proper image handling
            let options: [VNImageOption: Any] = [
                .cameraIntrinsics: NSNull() // Indicate we don't have intrinsics
            ]

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                               orientation: .right, // iPhone default orientation
                                               options: options)

            do {
                try handler.perform([request])
            } catch {
                print("[Vision] Failed to perform request: \(error)")
                completion(nil)
            }
        }
    }

    private func handleDetectionResults(_ results: [Any]?, completion: @escaping @Sendable (String?) -> Void) {
        guard let observations = results as? [VNRecognizedObjectObservation] else {
            completion(nil)
            return
        }

        // Get highest confidence detection
        guard let topObservation = observations.first,
              topObservation.confidence > 0.5 else {
            completion(nil)
            return
        }

        // Get label
        guard let topLabel = topObservation.labels.first else {
            completion(nil)
            return
        }

        let objectName = topLabel.identifier
        print("[Vision] Detected: \(objectName) (confidence: \(topLabel.confidence))")

        // Throttle announcements
        let now = Date()
        if now.timeIntervalSince(lastAnnouncementTime) > announcementCooldown {
            lastAnnouncementTime = now
            completion(objectName)
        } else {
            completion(nil)
        }
    }

    // Lightweight person detection with bounding box (better for real-time use)
    func detectPerson(_ pixelBuffer: CVPixelBuffer, completion: @escaping @Sendable (DetectionResult?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                completion(nil)
                return
            }

            let request = VNDetectHumanRectanglesRequest { request, error in
                if let error = error {
                    print("[Vision] Person detection error: \(error.localizedDescription)")
                    completion(nil)
                    return
                }

                // Check if any humans detected
                if let observations = request.results as? [VNHumanObservation],
                   let topObservation = observations.first {
                    // Get the bounding box (normalized coordinates)
                    let boundingBox = topObservation.boundingBox

                    // Throttle announcements
                    let now = Date()
                    if now.timeIntervalSince(self.lastAnnouncementTime) > self.announcementCooldown {
                        self.lastAnnouncementTime = now
                        let result = DetectionResult(objectName: "person", boundingBox: boundingBox)
                        completion(result)
                    } else {
                        // Still return result for distance calculation, but don't announce
                        let result = DetectionResult(objectName: "person", boundingBox: boundingBox)
                        completion(result)
                    }
                } else {
                    completion(nil)
                }
            }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                               orientation: .right,
                                               options: [:])

            do {
                try handler.perform([request])
            } catch {
                print("[Vision] Failed to perform person detection: \(error)")
                completion(nil)
            }
        }
    }
}
