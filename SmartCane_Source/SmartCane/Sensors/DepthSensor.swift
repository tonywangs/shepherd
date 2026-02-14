//
//  DepthSensor.swift
//  SmartCane
//
//  ARKit + LiDAR depth capture at 30-60fps
//

import Foundation
import ARKit
import Combine

// Depth data structure
struct DepthFrame {
    let depthMap: CVPixelBuffer
    let timestamp: TimeInterval
    let cameraTransform: simd_float4x4
}

class DepthSensor: NSObject, ObservableObject {
    @Published var latestDepthFrame: DepthFrame?

    private var arSession: ARSession?
    private let configuration = ARWorldTrackingConfiguration()

    override init() {
        super.init()
        setupARSession()
    }

    private func setupARSession() {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            print("[DepthSensor] ERROR: LiDAR not supported on this device!")
            return
        }

        arSession = ARSession()
        arSession?.delegate = self

        // Configure for LiDAR depth
        configuration.frameSemantics = .sceneDepth
        configuration.planeDetection = [.horizontal, .vertical]

        // Optimize for real-time performance
        configuration.videoFormat = ARWorldTrackingConfiguration
            .supportedVideoFormats
            .first { $0.framesPerSecond == 60 } ?? ARWorldTrackingConfiguration.supportedVideoFormats[0]

        print("[DepthSensor] ARKit configured for LiDAR at \(configuration.videoFormat.framesPerSecond)fps")
    }

    func start() {
        print("[DepthSensor] Starting ARKit session...")
        arSession?.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        print("[DepthSensor] Stopping ARKit session...")
        arSession?.pause()
    }
}

// MARK: - ARSessionDelegate
extension DepthSensor: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Extract scene depth (LiDAR)
        guard let sceneDepth = frame.sceneDepth else {
            return
        }

        let depthFrame = DepthFrame(
            depthMap: sceneDepth.depthMap,
            timestamp: frame.timestamp,
            cameraTransform: frame.camera.transform
        )

        // Publish on main thread (SwiftUI requirement)
        DispatchQueue.main.async { [weak self] in
            self?.latestDepthFrame = depthFrame
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("[DepthSensor] ERROR: \(error.localizedDescription)")
    }
}
