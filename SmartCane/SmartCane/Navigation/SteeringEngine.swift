//
//  SteeringEngine.swift
//  SmartCane
//
//  Lateral steering decision algorithm
//  CRITICAL: Only outputs LEFT (-1), NEUTRAL (0), or RIGHT (+1)
//  No forward/backward commands - omni wheel provides lateral force only
//

import Foundation

struct SteeringDecision {
    let command: Int8  // -1 = LEFT, 0 = NEUTRAL, +1 = RIGHT
    let confidence: Float  // 0.0 to 1.0
    let reason: String  // For debugging
}

class SteeringEngine {
    // Tuning parameters (adjust during testing)
    private let obstacleThreshold: Float = 1.2  // meters - below this triggers avoidance
    private let criticalThreshold: Float = 0.6  // meters - aggressive avoidance

    func computeSteering(zones: ObstacleZones, sidewalkBoundaries: SidewalkBoundaries? = nil) -> SteeringDecision {
        // NEW PRIORITY 0: Sidewalk boundary enforcement (highest priority, but low confidence)
        // Only applies gentle corrections when user drifts from centerline
        if let boundaries = sidewalkBoundaries,
           let offset = boundaries.userOffsetFromCenter,
           boundaries.confidence > 0.6 {

            // User is drifting off centerline
            let driftThreshold: Float = 0.3  // 30cm offset triggers correction

            if offset < -driftThreshold {
                // User drifting LEFT, steer RIGHT to recenter
                return SteeringDecision(
                    command: 1,  // RIGHT
                    confidence: 0.6,
                    reason: "Sidewalk: Recenter from left drift (\(String(format: "%.2f", offset))m)"
                )
            } else if offset > driftThreshold {
                // User drifting RIGHT, steer LEFT to recenter
                return SteeringDecision(
                    command: -1,  // LEFT
                    confidence: 0.6,
                    reason: "Sidewalk: Recenter from right drift (\(String(format: "%.2f", offset))m)"
                )
            }

            // Within acceptable centerline tolerance, continue to obstacle check
        }

        // PRIORITY 1: Clear path ahead - no steering needed
        if !zones.centerHasObstacle && !zones.leftHasObstacle && !zones.rightHasObstacle {
            return SteeringDecision(command: 0, confidence: 1.0, reason: "Clear path")
        }

        // PRIORITY 2: Center obstacle - steer toward more open side
        if zones.centerHasObstacle, let centerDist = zones.centerDistance {
            if centerDist < obstacleThreshold {
                return avoidCenterObstacle(zones: zones, centerDist: centerDist)
            }
        }

        // Priority 3: Side obstacles - steer away
        if zones.leftHasObstacle, let leftDist = zones.leftDistance {
            if leftDist < obstacleThreshold {
                return SteeringDecision(command: 1, confidence: 0.8, reason: "Avoid left obstacle at \(leftDist)m")
            }
        }

        if zones.rightHasObstacle, let rightDist = zones.rightDistance {
            if rightDist < obstacleThreshold {
                return SteeringDecision(command: -1, confidence: 0.8, reason: "Avoid right obstacle at \(rightDist)m")
            }
        }

        // Default: No steering needed
        return SteeringDecision(command: 0, confidence: 0.5, reason: "Obstacles outside threshold")
    }

    private func avoidCenterObstacle(zones: ObstacleZones, centerDist: Float) -> SteeringDecision {
        // Compare left vs right free space
        let leftSpace = zones.leftDistance ?? 2.0  // Assume clear if no reading
        let rightSpace = zones.rightDistance ?? 2.0

        // Critical obstacle ahead - steer aggressively toward clearer side
        if centerDist < criticalThreshold {
            if leftSpace > rightSpace {
                return SteeringDecision(command: -1, confidence: 1.0,
                                      reason: "Critical center obstacle - steer LEFT (left space: \(leftSpace)m)")
            } else {
                return SteeringDecision(command: 1, confidence: 1.0,
                                      reason: "Critical center obstacle - steer RIGHT (right space: \(rightSpace)m)")
            }
        }

        // Normal avoidance - gentler steering
        if leftSpace > rightSpace + 0.3 {  // 30cm bias to prefer one side clearly
            return SteeringDecision(command: -1, confidence: 0.7,
                                  reason: "Center obstacle - prefer left (left: \(leftSpace)m, right: \(rightSpace)m)")
        } else if rightSpace > leftSpace + 0.3 {
            return SteeringDecision(command: 1, confidence: 0.7,
                                  reason: "Center obstacle - prefer right (left: \(leftSpace)m, right: \(rightSpace)m)")
        } else {
            // Ambiguous - default to slight right (arbitrary choice)
            return SteeringDecision(command: 1, confidence: 0.5,
                                  reason: "Center obstacle - ambiguous, default right")
        }
    }
}
