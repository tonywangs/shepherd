//
//  SteeringEngine.swift
//  SmartCane
//
//  Lateral steering decision algorithm
//  Outputs continuous steering: -1.0 (hard LEFT) to +1.0 (hard RIGHT)
//  Omni wheel provides lateral force proportional to command magnitude
//

import Foundation

struct SteeringDecision {
    let command: Float  // -1.0 = hard LEFT, 0.0 = NEUTRAL, +1.0 = hard RIGHT
    let confidence: Float  // 0.0 to 1.0
    let reason: String  // For debugging
}

class SteeringEngine {
    // Tuning parameters (adjust during testing)
    private let criticalThreshold: Float = 0.6  // meters - aggressive avoidance

    func computeSteering(zones: ObstacleZones, sensitivity: Float = 2.0) -> SteeringDecision {
        // Priority 1: No obstacles detected at all
        if !zones.centerHasObstacle && !zones.leftHasObstacle && !zones.rightHasObstacle {
            return SteeringDecision(command: 0.0, confidence: 1.0, reason: "Clear path")
        }

        let closestDist = [zones.leftDistance, zones.centerDistance, zones.rightDistance]
            .compactMap { $0 }.min() ?? sensitivity

        // All obstacles beyond sensitivity → no steering
        if closestDist >= sensitivity {
            return SteeringDecision(command: 0.0, confidence: 0.5, reason: "Obstacles beyond threshold")
        }

        // --- Center obstacle < 1.0m → ALWAYS steer ---
        if let centerDist = zones.centerDistance, centerDist < 1.0 {
            let avgLeft = zones.averageLeftDistance ?? sensitivity
            let avgRight = zones.averageRightDistance ?? sensitivity
            let direction: Float
            if avgLeft > avgRight + 0.15 { direction = -1.0 }
            else if avgRight > avgLeft + 0.15 { direction = 1.0 }
            else if abs(zones.lateralBias) > 0.05 { direction = -zones.lateralBias }
            else { direction = 1.0 }  // absolute fallback: steer right

            if centerDist < criticalThreshold {
                return SteeringDecision(command: direction > 0 ? 1.0 : -1.0, confidence: 1.0,
                    reason: "Critical center obstacle at \(String(format: "%.2f", centerDist))m")
            }
            let urgency = max(0.4, min(1.0, (1.0 - centerDist) / 0.8))
            return SteeringDecision(command: max(-1.0, min(1.0, direction * urgency)), confidence: 0.85,
                reason: "Center obstacle at \(String(format: "%.2f", centerDist))m - forced steer")
        }

        // --- Continuous steering for non-center-critical obstacles ---
        let proximityFactor = max(0.0, min(1.0, (sensitivity - closestDist) / (sensitivity - 0.2)))

        // lateralBias > 0 = obstacles on right → steer left (negative command)
        var steerDirection = -zones.lateralBias

        // Handle ambiguous bias (wall scenario) — tie-breaker
        if abs(zones.lateralBias) < 0.1 {
            let avgLeft = zones.averageLeftDistance ?? sensitivity
            let avgRight = zones.averageRightDistance ?? sensitivity
            if avgLeft > avgRight + 0.2 { steerDirection = -1.0 }
            else if avgRight > avgLeft + 0.2 { steerDirection = 1.0 }
            else { steerDirection = 0.3 }  // slight right default
        }

        let steerMagnitude = max(0.2, proximityFactor)
        let command = max(-1.0, min(1.0, steerDirection * steerMagnitude))

        // Critical threshold override
        if closestDist < criticalThreshold {
            return SteeringDecision(command: steerDirection >= 0 ? 1.0 : -1.0, confidence: 1.0,
                reason: "Critical obstacle at \(String(format: "%.2f", closestDist))m")
        }

        let confidence = min(1.0, abs(zones.lateralBias) * 2.0 + 0.3)
        let dirText = command < -0.1 ? "LEFT" : (command > 0.1 ? "RIGHT" : "NEUTRAL")
        return SteeringDecision(command: command, confidence: confidence,
            reason: "Steer \(dirText) (\(String(format: "%.2f", command))) bias:\(String(format: "%.2f", zones.lateralBias)) closest:\(String(format: "%.2f", closestDist))m")
    }
}
