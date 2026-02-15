//
//  WaypointModels.swift
//  SmartCane
//
//  Data types for GPS pedestrian navigation
//

import Foundation
import CoreLocation

// MARK: - Route Models

struct PedestrianRoute {
    let origin: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D
    let destinationName: String
    var steps: [RouteStep]
    let overviewPolyline: [CLLocationCoordinate2D]
    let totalDistanceMeters: Double
    let totalDurationSeconds: Double
}

struct RouteStep {
    let instruction: String
    let maneuver: Maneuver
    let distanceMeters: Double
    let startLocation: CLLocationCoordinate2D
    let endLocation: CLLocationCoordinate2D
    let polyline: [CLLocationCoordinate2D]
    var infrastructure: [InfrastructureFeature]
}

enum Maneuver: String {
    case depart
    case turnLeft = "TURN_LEFT"
    case turnRight = "TURN_RIGHT"
    case turnSlightLeft = "TURN_SLIGHT_LEFT"
    case turnSlightRight = "TURN_SLIGHT_RIGHT"
    case turnSharpLeft = "TURN_SHARP_LEFT"
    case turnSharpRight = "TURN_SHARP_RIGHT"
    case straight = "STRAIGHT"
    case uturnLeft = "UTURN_LEFT"
    case uturnRight = "UTURN_RIGHT"
    case roundaboutLeft = "ROUNDABOUT_LEFT"
    case roundaboutRight = "ROUNDABOUT_RIGHT"
    case arrive
    case unknown

    var spokenDescription: String {
        switch self {
        case .depart: return "Head straight"
        case .turnLeft: return "Turn left"
        case .turnRight: return "Turn right"
        case .turnSlightLeft: return "Bear left"
        case .turnSlightRight: return "Bear right"
        case .turnSharpLeft: return "Sharp left"
        case .turnSharpRight: return "Sharp right"
        case .straight: return "Continue straight"
        case .uturnLeft, .uturnRight: return "Make a U-turn"
        case .roundaboutLeft: return "Take the roundabout left"
        case .roundaboutRight: return "Take the roundabout right"
        case .arrive: return "You have arrived"
        case .unknown: return "Continue"
        }
    }
}

// MARK: - Infrastructure Models

struct InfrastructureFeature: Identifiable {
    let id = UUID()
    let type: InfrastructureType
    let coordinate: CLLocationCoordinate2D
    let distanceFromRoute: Double
}

enum InfrastructureType: String {
    case crosswalk
    case trafficSignal
    case stopSign

    var spokenWarning: String {
        switch self {
        case .crosswalk: return "Crosswalk ahead"
        case .trafficSignal: return "Traffic signal ahead"
        case .stopSign: return "Stop sign ahead"
        }
    }
}

// MARK: - Navigation State

enum NavigationState: Equatable {
    case idle
    case planning
    case navigating(stepIndex: Int)
    case arriving
    case arrived
    case error(String)

    static func == (lhs: NavigationState, rhs: NavigationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.planning, .planning), (.arriving, .arriving), (.arrived, .arrived):
            return true
        case (.navigating(let a), .navigating(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }

    var isActive: Bool {
        switch self {
        case .navigating, .arriving: return true
        default: return false
        }
    }
}

struct NavigationGuidance {
    let currentInstruction: String
    let distanceToNextManeuver: Double
    let nearbyInfrastructure: [InfrastructureFeature]
}

// MARK: - CLLocationCoordinate2D Extension

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> Double {
        let from = CLLocation(latitude: latitude, longitude: longitude)
        let to = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return from.distance(from: to)
    }

    /// Bearing from this coordinate to another, in degrees (0-360, true north).
    func bearing(to other: CLLocationCoordinate2D) -> Double {
        let lat1 = latitude * .pi / 180.0
        let lat2 = other.latitude * .pi / 180.0
        let dLon = (other.longitude - longitude) * .pi / 180.0

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let rad = atan2(y, x)

        return (rad * 180.0 / .pi + 360.0).truncatingRemainder(dividingBy: 360.0)
    }
}
