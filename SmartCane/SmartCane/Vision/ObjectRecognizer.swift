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

class ObjectRecognizer: ObservableObject {
    @Published var detectedObjects: [String] = []

    private var lastAnnouncementTime: Date = .distantPast
    private let announcementCooldown: TimeInterval = 3.0 // seconds between announcements

    // Process camera frame for object detection
    func processFrame(_ pixelBuffer: CVPixelBuffer, completion: @escaping (String?) -> Void) {
        // Use Vision framework for object recognition
        let request = VNRecognizeAnimalsRequest { request, error in
            if let error = error {
                print("[Vision] Error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            self.handleDetectionResults(request.results, completion: completion)
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
    func classifyScene(_ pixelBuffer: CVPixelBuffer, completion: @escaping (String?) -> Void) {
        let request = VNClassifyImageRequest { request, error in
            if let error = error {
                print("[Vision] Error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            self.handleClassificationResults(request.results, completion: completion)
        }

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

    private func handleDetectionResults(_ results: [Any]?, completion: @escaping (String?) -> Void) {
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

    private func handleClassificationResults(_ results: [Any]?, completion: @escaping (String?) -> Void) {
        guard let observations = results as? [VNClassificationObservation] else {
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
            if now.timeIntervalSince(lastAnnouncementTime) > announcementCooldown {
                lastAnnouncementTime = now
                completion(className)
            }
        }

        completion(nil)
    }

    // TODO: Integrate with ARFrame in DepthSensor
    // Extract capturedImage from ARFrame and pass to processFrame()
    //
    // Example integration:
    // func session(_ session: ARSession, didUpdate frame: ARFrame) {
    //     let pixelBuffer = frame.capturedImage
    //     objectRecognizer.processFrame(pixelBuffer) { objectName in
    //         if let name = objectName {
    //             voiceManager.speak("\(name) ahead")
    //         }
    //     }
    // }
}
