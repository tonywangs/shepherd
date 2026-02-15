//
//  NavigationSteering.swift
//  SmartCane
//
//  Merges route-following navigation bias into obstacle avoidance steering.
//  Uses ARKit for smooth 60Hz heading, micro-waypoints for fine-grained
//  route progression, and a priority system where obstacles always win.
//

import Foundation
import CoreLocation
import simd

// MARK: - Types

struct CaneHeading {
    let degrees: Double   // 0-360, true north
    let source: HeadingSource
}

enum HeadingSource {
    case arkit
    case compass
    case hybrid
}

struct MicroWaypoint {
    let coordinate: CLLocationCoordinate2D
    let routeStepIndex: Int
}

// MARK: - Angle Helpers

/// Normalize angle to 0..<360
private func normalizeAngle360(_ angle: Double) -> Double {
    var a = angle.truncatingRemainder(dividingBy: 360.0)
    if a < 0 { a += 360.0 }
    return a
}

/// Normalize angle to -180..<180
private func normalizeAngle180(_ angle: Double) -> Double {
    var a = angle.truncatingRemainder(dividingBy: 360.0)
    if a > 180.0 { a -= 360.0 }
    if a < -180.0 { a += 360.0 }
    return a
}

// MARK: - CaneHeadingProvider

/// Fuses ARKit camera transform (60Hz, jitter-free) with compass heading (drift correction).
@MainActor
class CaneHeadingProvider {

    private(set) var currentHeading: CaneHeading = CaneHeading(degrees: 0, source: .compass)

    private var compassOffset: Double = 0.0
    private var isCalibrated: Bool = false
    private var lastARYawDeg: Double = 0.0
    private var compassBadSince: Date? = nil

    /// Called at 60Hz from processDepthFrame with the ARKit camera transform.
    func updateFromARKit(cameraTransform: simd_float4x4) {
        // Extract forward vector: camera looks along -Z in ARKit coordinates
        let forward = -simd_float3(
            cameraTransform.columns.2.x,
            cameraTransform.columns.2.y,
            cameraTransform.columns.2.z
        )

        // Project onto horizontal XZ plane
        let flatForward = simd_float2(forward.x, forward.z)
        guard simd_length(flatForward) > 0.001 else { return }

        // atan2(x, z) gives angle from +Z axis (north in ARKit world space)
        let arYawRad = atan2(flatForward.x, flatForward.y)
        let arYawDeg = Double(arYawRad) * 180.0 / .pi
        lastARYawDeg = normalizeAngle360(arYawDeg)

        if isCalibrated {
            let heading = normalizeAngle360(lastARYawDeg + compassOffset)
            currentHeading = CaneHeading(degrees: heading, source: .hybrid)
        }
    }

    /// Called at ~1Hz from CLLocationManager heading delegate.
    func updateFromCompass(trueHeading: Double, accuracy: Double) {
        guard trueHeading >= 0 else { return } // negative = invalid

        if !isCalibrated {
            // One-time calibration: compute offset between compass and ARKit yaw
            compassOffset = normalizeAngle180(trueHeading - lastARYawDeg)
            isCalibrated = true
            currentHeading = CaneHeading(degrees: trueHeading, source: .compass)
            print("[HeadingProvider] Calibrated: compassOffset=\(String(format: "%.1f", compassOffset))°")
            return
        }

        // Track compass quality
        if accuracy > 25 {
            if compassBadSince == nil { compassBadSince = Date() }
        } else {
            compassBadSince = nil
        }

        // Slow drift correction: only if compass is good and not stale for 3s+
        let compassBadDuration = compassBadSince.map { Date().timeIntervalSince($0) } ?? 0
        if accuracy < 15 && compassBadDuration == 0 {
            let desiredOffset = normalizeAngle180(trueHeading - lastARYawDeg)
            let diff = normalizeAngle180(desiredOffset - compassOffset)
            compassOffset += diff * 0.02  // lerp alpha
            compassOffset = normalizeAngle180(compassOffset)
        }
    }
}

// MARK: - MicroWaypointTracker

/// Interpolates route polylines into dense ~6m waypoints for fine-grained progression.
@MainActor
class MicroWaypointTracker {

    private(set) var waypoints: [MicroWaypoint] = []
    private(set) var currentIndex: Int = 0

    var nextWaypoint: MicroWaypoint? {
        guard currentIndex < waypoints.count else { return nil }
        return waypoints[currentIndex]
    }

    /// Build micro-waypoints from a full route. Interpolates gaps > spacing meters.
    func buildFromRoute(_ route: PedestrianRoute, spacing: Double = 6.0) {
        waypoints.removeAll()
        currentIndex = 0

        for (stepIdx, step) in route.steps.enumerated() {
            let poly = step.polyline
            guard poly.count >= 2 else {
                if let coord = poly.first {
                    waypoints.append(MicroWaypoint(coordinate: coord, routeStepIndex: stepIdx))
                }
                continue
            }

            for i in 0..<(poly.count - 1) {
                let a = poly[i]
                let b = poly[i + 1]
                let dist = a.distance(to: b)

                waypoints.append(MicroWaypoint(coordinate: a, routeStepIndex: stepIdx))

                if dist > spacing {
                    // Interpolate intermediate points
                    let segments = Int(ceil(dist / spacing))
                    for s in 1..<segments {
                        let t = Double(s) / Double(segments)
                        let lat = a.latitude + (b.latitude - a.latitude) * t
                        let lon = a.longitude + (b.longitude - a.longitude) * t
                        waypoints.append(MicroWaypoint(
                            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            routeStepIndex: stepIdx
                        ))
                    }
                }
            }

            // Add final point of the last segment in this step
            if let last = poly.last {
                waypoints.append(MicroWaypoint(coordinate: last, routeStepIndex: stepIdx))
            }
        }

        print("[MicroWaypoints] Built \(waypoints.count) waypoints from \(route.steps.count) steps")
    }

    /// Advance waypoint index based on user position.
    /// Returns the routeStepIndex if a step boundary was crossed, nil otherwise.
    func advance(userLocation: CLLocationCoordinate2D) -> Int? {
        guard currentIndex < waypoints.count else { return nil }

        let target = waypoints[currentIndex]
        let distToTarget = userLocation.distance(to: target.coordinate)

        // Direct proximity check
        if distToTarget < 5.0 {
            return advanceToNext()
        }

        // Perpendicular projection check (are we past the waypoint along the segment?)
        if currentIndex > 0 {
            let prev = waypoints[currentIndex - 1].coordinate
            let curr = target.coordinate

            let t = perpendicularProjection(point: userLocation, segmentA: prev, segmentB: curr)
            if t > 0.8 {
                return advanceToNext()
            }
        }

        return nil
    }

    func reset() {
        waypoints.removeAll()
        currentIndex = 0
    }

    // MARK: - Private

    private func advanceToNext() -> Int? {
        let oldStepIndex = waypoints[currentIndex].routeStepIndex
        currentIndex += 1

        guard currentIndex < waypoints.count else { return nil }

        let newStepIndex = waypoints[currentIndex].routeStepIndex
        if newStepIndex != oldStepIndex {
            return newStepIndex  // Step boundary crossed
        }
        return nil
    }

    /// Compute projection parameter t of point onto segment A→B.
    /// t=0 means at A, t=1 means at B.
    private func perpendicularProjection(
        point: CLLocationCoordinate2D,
        segmentA: CLLocationCoordinate2D,
        segmentB: CLLocationCoordinate2D
    ) -> Double {
        // Use local flat-earth approximation (fine for <1km segments)
        let cosLat = cos(segmentA.latitude * .pi / 180.0)
        let ax = segmentA.longitude * cosLat
        let ay = segmentA.latitude
        let bx = segmentB.longitude * cosLat
        let by = segmentB.latitude
        let px = point.longitude * cosLat
        let py = point.latitude

        let dx = bx - ax
        let dy = by - ay
        let lenSq = dx * dx + dy * dy
        guard lenSq > 1e-12 else { return 0 }

        let t = ((px - ax) * dx + (py - ay) * dy) / lenSq
        return max(0, min(1, t))
    }
}

// MARK: - NavigationBiasComputer

/// Computes a steering bias toward the next micro-waypoint, with wrong-way detection.
@MainActor
class NavigationBiasComputer {

    private(set) var navBias: Float = 0.0
    private(set) var headingErrorDegrees: Double = 0.0

    // Wrong-way tracking
    private var lastWaypointDistance: Double? = nil
    private var distanceIncreasingStart: Date? = nil
    private var lastTurnAroundAnnouncement: Date = .distantPast
    private let wrongWayThreshold: TimeInterval = 5.0
    private let turnAroundCooldown: TimeInterval = 15.0

    /// Compute navigation bias given current heading and next waypoint.
    func compute(caneHeading: Double, userLocation: CLLocationCoordinate2D, nextWaypoint: MicroWaypoint?) {
        guard let wp = nextWaypoint else {
            navBias = 0
            headingErrorDegrees = 0
            return
        }

        let bearingToWP = userLocation.bearing(to: wp.coordinate)
        headingErrorDegrees = normalizeAngle180(bearingToWP - caneHeading)

        // Bias: clamp headingError/45 to -1..+1
        navBias = Float(max(-1.0, min(1.0, headingErrorDegrees / 45.0)))

        // Wrong-way tracking
        let dist = userLocation.distance(to: wp.coordinate)
        if let prev = lastWaypointDistance, dist > prev + 1.0 {
            // Distance increasing
            if distanceIncreasingStart == nil {
                distanceIncreasingStart = Date()
            }
        } else {
            distanceIncreasingStart = nil
        }
        lastWaypointDistance = dist
    }

    /// True if the user has been going the wrong way long enough to warrant a voice alert.
    var shouldAnnounceTurnAround: Bool {
        guard abs(headingErrorDegrees) > 90 else { return false }
        guard let start = distanceIncreasingStart else { return false }
        guard Date().timeIntervalSince(start) > wrongWayThreshold else { return false }
        guard Date().timeIntervalSince(lastTurnAroundAnnouncement) > turnAroundCooldown else { return false }
        return true
    }

    /// Call after announcing turn-around to start cooldown.
    func didAnnounceTurnAround() {
        lastTurnAroundAnnouncement = Date()
        distanceIncreasingStart = nil
    }

    func reset() {
        navBias = 0
        headingErrorDegrees = 0
        lastWaypointDistance = nil
        distanceIncreasingStart = nil
        lastTurnAroundAnnouncement = .distantPast
    }
}
