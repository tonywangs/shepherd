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

struct SteeringTuning {
    var temporalAlpha: Float = 0.08      // EMA memory speed
    var smoothingAlpha: Float = 0.2       // Output smoothing speed
    var centerDeadband: Float = 0.15      // meters
    var lateralDeadband: Float = 0.2      // meters
}

class SteeringEngine {
    // Tuning parameters (adjust during testing)
    private let criticalThreshold: Float = 0.6  // meters - aggressive avoidance

    // Temporal smoothing (EMA) to eliminate hallway oscillation
    private var smoothedCommand: Float = 0.0
    private let smoothingAlpha: Float = 0.2  // 20% new frame, 80% previous

    // Temporal EMA of zone data for tiebreaking
    private var emaLeftDist: Float = 0.0
    private var emaRightDist: Float = 0.0
    private var emaLateralBias: Float = 0.0
    private var emaInitialized: Bool = false

    func computeSteering(zones: ObstacleZones, sensitivity: Float = 2.0, tuning: SteeringTuning = SteeringTuning()) -> SteeringDecision {
        updateTemporalEMA(zones: zones, sensitivity: sensitivity, tuning: tuning)
        let raw = computeRawSteering(zones: zones, sensitivity: sensitivity, tuning: tuning)
        return applySmoothing(raw, tuning: tuning)
    }

    func reset() {
        smoothedCommand = 0.0
        emaLeftDist = 0.0
        emaRightDist = 0.0
        emaLateralBias = 0.0
        emaInitialized = false
    }

    var currentEMAState: (left: Float, right: Float, bias: Float) {
        (emaLeftDist, emaRightDist, emaLateralBias)
    }

    private func updateTemporalEMA(zones: ObstacleZones, sensitivity: Float, tuning: SteeringTuning) {
        // Use sensitivity threshold as default value when zone reports nil (treating "clear" as "far")
        let leftVal = zones.averageLeftDistance ?? sensitivity
        let rightVal = zones.averageRightDistance ?? sensitivity
        let biasVal = zones.lateralBias

        if !emaInitialized {
            // First sample - initialize directly
            emaLeftDist = leftVal
            emaRightDist = rightVal
            emaLateralBias = biasVal
            emaInitialized = true
        } else {
            // Apply EMA: new_ema = alpha * new_value + (1 - alpha) * old_ema
            emaLeftDist = tuning.temporalAlpha * leftVal + (1.0 - tuning.temporalAlpha) * emaLeftDist
            emaRightDist = tuning.temporalAlpha * rightVal + (1.0 - tuning.temporalAlpha) * emaRightDist
            emaLateralBias = tuning.temporalAlpha * biasVal + (1.0 - tuning.temporalAlpha) * emaLateralBias
        }
    }

    private func applySmoothing(_ decision: SteeringDecision, tuning: SteeringTuning) -> SteeringDecision {
        // Safety-critical commands bypass smoothing (confidence 1.0 + max magnitude)
        if decision.confidence >= 1.0 && abs(decision.command) >= 1.0 {
            smoothedCommand = decision.command
            return decision
        }

        smoothedCommand = tuning.smoothingAlpha * decision.command + (1.0 - tuning.smoothingAlpha) * smoothedCommand
        return SteeringDecision(
            command: smoothedCommand,
            confidence: decision.confidence,
            reason: decision.reason + " [sm:\(String(format: "%.2f", smoothedCommand))]"
        )
    }

    private func computeRawSteering(zones: ObstacleZones, sensitivity: Float = 2.0, tuning: SteeringTuning) -> SteeringDecision {
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
            let avgLeft = emaLeftDist
            let avgRight = emaRightDist
            let direction: Float
            if avgLeft > avgRight + tuning.centerDeadband { direction = -1.0 }
            else if avgRight > avgLeft + tuning.centerDeadband { direction = 1.0 }
            else if abs(emaLateralBias) > 0.05 { direction = -emaLateralBias }
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
            let avgLeft = emaLeftDist
            let avgRight = emaRightDist
            if avgLeft > avgRight + tuning.lateralDeadband { steerDirection = -1.0 }
            else if avgRight > avgLeft + tuning.lateralDeadband { steerDirection = 1.0 }
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
