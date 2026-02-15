//
//  RouteMapView.swift
//  SmartCane
//
//  Map tab showing the active route, step waypoints, and infrastructure features
//

import SwiftUI
import MapKit

struct RouteMapView: View {
    @ObservedObject var navigationManager: NavigationManager
    @State private var showMicroWaypoints = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let route = navigationManager.currentRoute {
                activeRouteMap(route: route)
            } else {
                noRouteView
            }
        }
    }

    // MARK: - No Route

    private var noRouteView: some View {
        VStack(spacing: 16) {
            Image(systemName: "map")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("No Active Route")
                .font(.title2)
                .bold()
                .foregroundColor(.white)
            Text("Start navigation from the main tab to see the route here")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Active Route Map

    private func activeRouteMap(route: PedestrianRoute) -> some View {
        let polylineCoords = route.overviewPolyline
        let region = Self.regionForCoordinates(polylineCoords, userLocation: navigationManager.userLocation)

        return VStack(spacing: 0) {
            // Route info header
            routeHeader(route: route)

            // Map
            Map(initialPosition: .region(region)) {
                // Route polyline
                if polylineCoords.count >= 2 {
                    MapPolyline(coordinates: polylineCoords)
                        .stroke(.cyan, lineWidth: 5)
                }

                // Origin marker
                Annotation("Start", coordinate: route.origin) {
                    ZStack {
                        Circle()
                            .fill(.green)
                            .frame(width: 24, height: 24)
                        Image(systemName: "figure.walk")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                }

                // Destination marker
                Annotation(route.destinationName.components(separatedBy: ",").first ?? "End", coordinate: route.destination) {
                    ZStack {
                        Circle()
                            .fill(.red)
                            .frame(width: 24, height: 24)
                        Image(systemName: "flag.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                }

                // Step waypoints (turn points)
                ForEach(Array(route.steps.enumerated()), id: \.offset) { index, step in
                    if step.maneuver != .depart && step.maneuver != .unknown {
                        Annotation("", coordinate: step.startLocation) {
                            stepMarker(index: index, step: step, isCurrentStep: index == navigationManager.currentStepIndex)
                        }
                    }
                }

                // Infrastructure features
                ForEach(allInfrastructure(from: route)) { feature in
                    Annotation("", coordinate: feature.coordinate) {
                        infrastructureMarker(feature: feature)
                    }
                }

                // Micro-waypoints (when toggled on)
                if showMicroWaypoints {
                    let waypoints = navigationManager.waypointTracker.waypoints
                    let currentIdx = navigationManager.waypointTracker.currentIndex
                    ForEach(Array(waypoints.enumerated()), id: \.offset) { index, wp in
                        Annotation("", coordinate: wp.coordinate) {
                            Circle()
                                .fill(index == currentIdx ? Color.yellow : Color.mint.opacity(0.7))
                                .frame(width: index == currentIdx ? 12 : 8,
                                       height: index == currentIdx ? 12 : 8)
                                .overlay(
                                    index == currentIdx ?
                                        Circle()
                                            .stroke(Color.yellow, lineWidth: 2)
                                            .frame(width: 18, height: 18)
                                        : nil
                                )
                        }
                    }
                }

                // User location
                if let userLoc = navigationManager.userLocation {
                    Annotation("You", coordinate: userLoc) {
                        ZStack {
                            Circle()
                                .fill(.blue.opacity(0.3))
                                .frame(width: 32, height: 32)
                            Circle()
                                .fill(.blue)
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle().stroke(.white, lineWidth: 2)
                                )
                        }
                    }
                }
            }
            .mapStyle(.standard)

            // Step list
            stepList(route: route)
        }
    }

    // MARK: - Route Header

    private func routeHeader(route: PedestrianRoute) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(route.destinationName.components(separatedBy: ",").first ?? route.destinationName)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Label("\(Int(route.totalDistanceMeters))m", systemImage: "figure.walk")
                        .font(.caption)
                        .foregroundColor(.cyan)
                    Label("\(Int(route.totalDurationSeconds / 60)) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Label("\(route.steps.count) steps", systemImage: "arrow.triangle.turn.up.right.diamond")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            // Micro-waypoint toggle
            Button {
                showMicroWaypoints.toggle()
            } label: {
                Image(systemName: "circle.grid.3x3.fill")
                    .font(.system(size: 14))
                    .foregroundColor(showMicroWaypoints ? .cyan : .gray)
                    .padding(6)
                    .background(showMicroWaypoints ? Color.cyan.opacity(0.2) : Color.gray.opacity(0.2))
                    .cornerRadius(6)
            }

            // Nav state badge
            stateBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
    }

    private var stateBadge: some View {
        Group {
            switch navigationManager.state {
            case .navigating:
                Label("Active", systemImage: "location.fill")
                    .font(.caption2)
                    .bold()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.3))
                    .foregroundColor(.cyan)
                    .cornerRadius(8)
            case .arrived:
                Label("Arrived", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .bold()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.3))
                    .foregroundColor(.green)
                    .cornerRadius(8)
            case .planning:
                Label("Planning", systemImage: "ellipsis")
                    .font(.caption2)
                    .bold()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.3))
                    .foregroundColor(.gray)
                    .cornerRadius(8)
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Step List

    private func stepList(route: PedestrianRoute) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(route.steps.enumerated()), id: \.offset) { index, step in
                    stepCard(index: index, step: step)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.black)
        .frame(height: 80)
    }

    private func stepCard(index: Int, step: RouteStep) -> some View {
        let isCurrent = index == navigationManager.currentStepIndex
        let isPast = index < navigationManager.currentStepIndex

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: maneuverIcon(step.maneuver))
                    .font(.caption)
                    .foregroundColor(isCurrent ? .cyan : isPast ? .gray : .white)
                Text("\(Int(step.distanceMeters))m")
                    .font(.caption2)
                    .foregroundColor(isCurrent ? .cyan : .gray)
            }
            Text(step.instruction)
                .font(.caption2)
                .foregroundColor(isPast ? .gray : .white)
                .lineLimit(2)

            // Infrastructure badges
            if !step.infrastructure.isEmpty {
                HStack(spacing: 2) {
                    ForEach(Array(Set(step.infrastructure.map(\.type))), id: \.rawValue) { type in
                        Image(systemName: infraIcon(type))
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .frame(width: 140)
        .padding(8)
        .background(isCurrent ? Color.cyan.opacity(0.15) : Color.gray.opacity(0.15))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isCurrent ? Color.cyan : Color.clear, lineWidth: 1.5)
        )
    }

    // MARK: - Map Markers

    private func stepMarker(index: Int, step: RouteStep, isCurrentStep: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isCurrentStep ? Color.cyan : Color.white.opacity(0.9))
                .frame(width: 20, height: 20)
            Image(systemName: maneuverIcon(step.maneuver))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isCurrentStep ? .white : .black)
        }
    }

    private func infrastructureMarker(feature: InfrastructureFeature) -> some View {
        ZStack {
            Circle()
                .fill(infraColor(feature.type))
                .frame(width: 18, height: 18)
            Image(systemName: infraIcon(feature.type))
                .font(.system(size: 9))
                .foregroundColor(.white)
        }
    }

    // MARK: - Helpers

    private func allInfrastructure(from route: PedestrianRoute) -> [InfrastructureFeature] {
        route.steps.flatMap(\.infrastructure)
    }

    private func maneuverIcon(_ maneuver: Maneuver) -> String {
        switch maneuver {
        case .turnLeft, .turnSharpLeft: return "arrow.turn.up.left"
        case .turnRight, .turnSharpRight: return "arrow.turn.up.right"
        case .turnSlightLeft: return "arrow.up.left"
        case .turnSlightRight: return "arrow.up.right"
        case .uturnLeft, .uturnRight: return "arrow.uturn.down"
        case .straight: return "arrow.up"
        case .depart: return "figure.walk"
        case .arrive: return "flag.fill"
        default: return "circle.fill"
        }
    }

    private func infraIcon(_ type: InfrastructureType) -> String {
        switch type {
        case .crosswalk: return "figure.walk"
        case .trafficSignal: return "light.beacon.max"
        case .stopSign: return "hand.raised.fill"
        }
    }

    private func infraColor(_ type: InfrastructureType) -> Color {
        switch type {
        case .crosswalk: return .yellow
        case .trafficSignal: return .orange
        case .stopSign: return .red
        }
    }

    private static func regionForCoordinates(_ coords: [CLLocationCoordinate2D], userLocation: CLLocationCoordinate2D?) -> MKCoordinateRegion {
        var allCoords = coords
        if let user = userLocation { allCoords.append(user) }
        guard !allCoords.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.4275, longitude: -122.1697),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }

        var minLat = allCoords[0].latitude
        var maxLat = allCoords[0].latitude
        var minLng = allCoords[0].longitude
        var maxLng = allCoords[0].longitude

        for c in allCoords {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude)
            maxLng = max(maxLng, c.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.4 + 0.002,
            longitudeDelta: (maxLng - minLng) * 1.4 + 0.002
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
