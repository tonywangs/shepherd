//
//  SteeringEngine.swift
//  SmartCane
//
//  Gap-seeking steering algorithm.
//  Steers toward the direction of maximum clearance (the gap), not away from obstacles.
//  Magnitude is proportional to obstacle proximity.
//  No iPhone-side smoothing — the ESP32's leaky integrator handles temporal smoothing.
//
//  Output: continuous steering command from -1.0 (hard LEFT) to +1.0 (hard RIGHT).
//

import Foundation

struct SteeringDecision {
    let command: Float      // -1.0 = hard LEFT, 0.0 = NEUTRAL, +1.0 = hard RIGHT
    let confidence: Float   // 0.0 to 1.0 (maps to proximity)
    let reason: String      // For debugging / serial log
}

class SteeringEngine {

    /// Gap-seeking steering: steer toward the direction of maximum clearance.
    ///
    /// - `gapDirection` (from ObstacleDetector) is the horizontal angle of the deepest
    ///   average column in the depth map. It tells us WHERE the opening is, not where
    ///   the obstacle mass is. A small correction means "the gap is right next to center."
    ///
    /// - `proximityFactor` scales the correction by urgency: far obstacles get gentle
    ///   nudges, close ones get strong steering.
    ///
    /// - No EMA / output smoothing here — the ESP32's leaky integrator (tau=0.55s)
    ///   provides physically-motivated temporal smoothing at 50Hz on the motor loop.
    ///
    func computeSteering(zones: ObstacleZones,
                         sensitivity: Float = 2.0,
                         proximityExponent: Float = 0.6,
                         closeFloor: Float = 0.5) -> SteeringDecision {

        // Nothing within detection range → no steering needed
        guard let closestDist = zones.closestDistance, closestDist < sensitivity else {
            return SteeringDecision(command: 0.0, confidence: 0.0, reason: "Clear")
        }

        // How urgent: 0.0 at sensitivity threshold, 1.0 at minimum range (0.2m)
        let linearProximity = max(0.0, min(1.0,
            (sensitivity - closestDist) / (sensitivity - 0.2)
        ))
        // Exponent < 1 ramps faster near threshold; > 1 ramps slower.
        let proximityFactor = powf(linearProximity, proximityExponent)

        // Boost gap direction with cube root (pow 0.33) so moderate gaps produce
        // meaningful motor force. Cube root is steeper than sqrt near zero:
        //   ±0.1 → ±0.46,  ±0.3 → ±0.67,  ±0.5 → ±0.79,  ±1.0 → ±1.0
        let gap = zones.gapDirection
        let absGap = min(fabsf(gap), 1.0)
        let boostedGap = gap >= 0
            ? powf(absGap, 0.33)
            : -powf(absGap, 0.33)

        // Steer toward the gap, scaled by urgency
        var command = max(-1.0, min(1.0, boostedGap * proximityFactor))

        // Close obstacle floor: if something is within 1m, enforce minimum command
        // so the ESP32 integrator has enough input to overcome motor friction.
        if closestDist < 1.0 && fabsf(command) < closeFloor && fabsf(gap) > 0.02 {
            command = command >= 0 ? max(command, closeFloor) : min(command, -closeFloor)
        }

        let dirText = command < -0.1 ? "LEFT" : (command > 0.1 ? "RIGHT" : "NEUTRAL")
        return SteeringDecision(
            command: command,
            confidence: proximityFactor,
            reason: "\(dirText) gap:\(String(format: "%.2f", zones.gapDirection))→\(String(format: "%.2f", boostedGap)) prox:\(String(format: "%.2f", proximityFactor)) closest:\(String(format: "%.1f", closestDist))m"
        )
    }

    func reset() {
        // No internal state — all smoothing lives on the ESP32's leaky integrator
    }
}
