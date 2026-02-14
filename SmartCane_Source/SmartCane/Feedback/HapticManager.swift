//
//  HapticManager.swift
//  SmartCane
//
//  Haptic feedback with pulse frequency based on obstacle distance
//  Closer obstacle = faster pulses
//

import Foundation
import CoreHaptics

class HapticManager: ObservableObject {
    private var engine: CHHapticEngine?
    private var pulseTimer: Timer?

    private var currentDistance: Float = 2.0
    private let maxDistance: Float = 1.5
    private let minDistance: Float = 0.3

    func initialize() {
        // Check haptic support
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("[Haptics] Device does not support haptics")
            return
        }

        do {
            engine = try CHHapticEngine()
            try engine?.start()
            print("[Haptics] Engine started successfully")

            // Handle engine stop/reset
            engine?.stoppedHandler = { [weak self] reason in
                print("[Haptics] Engine stopped: \(reason.rawValue)")
                self?.restartEngine()
            }

            engine?.resetHandler = { [weak self] in
                print("[Haptics] Engine reset")
                self?.restartEngine()
            }

        } catch {
            print("[Haptics] Error creating engine: \(error)")
        }
    }

    private func restartEngine() {
        do {
            try engine?.start()
        } catch {
            print("[Haptics] Error restarting engine: \(error)")
        }
    }

    func updateDistance(_ distance: Float) {
        currentDistance = distance

        // Stop pulses if no obstacle nearby
        if distance > maxDistance {
            stopPulsing()
            return
        }

        // Calculate pulse frequency based on distance
        // Closer = faster pulses
        let pulseInterval = mapDistanceToPulseInterval(distance)
        startPulsing(interval: pulseInterval)
    }

    private func mapDistanceToPulseInterval(_ distance: Float) -> TimeInterval {
        // Map distance to pulse interval (seconds)
        // 0.3m -> 0.1s (10 Hz - very fast)
        // 1.5m -> 1.0s (1 Hz - slow)

        let normalizedDistance = (distance - minDistance) / (maxDistance - minDistance)
        let clampedDistance = max(0, min(1, normalizedDistance))

        // Exponential curve for better feel
        let interval = 0.1 + (0.9 * pow(clampedDistance, 2.0))
        return TimeInterval(interval)
    }

    private func startPulsing(interval: TimeInterval) {
        // Update existing timer if already running
        pulseTimer?.invalidate()

        pulseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.triggerPulse()
        }

        // Trigger immediately
        triggerPulse()
    }

    private func stopPulsing() {
        pulseTimer?.invalidate()
        pulseTimer = nil
    }

    private func triggerPulse() {
        guard let engine = engine else { return }

        // Create sharp haptic pulse
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)

        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("[Haptics] Error playing pattern: \(error)")
        }
    }

    func stop() {
        stopPulsing()
        engine?.stop()
    }
}
