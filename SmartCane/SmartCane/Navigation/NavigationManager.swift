//
//  NavigationManager.swift
//  SmartCane
//
//  GPS-based pedestrian navigation with turn-by-turn guidance
//

import Foundation
import CoreLocation
import Combine

@MainActor
class NavigationManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var state: NavigationState = .idle
    @Published var currentRoute: PedestrianRoute?
    @Published var currentStepIndex: Int = 0
    @Published var currentGuidance: NavigationGuidance?
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var distanceToNextManeuver: Double = 0
    @Published var distanceToDestination: Double = 0
    @Published var headingDegrees: Double = 0

    // MARK: - Dependencies

    private var routeService: RouteService?
    private var voiceManager: VoiceManager?
    private var locationManager: CLLocationManager?

    // MARK: - Internal State

    private var announcedInfrastructureIDs: Set<UUID> = []
    private var stepAdvancementThreshold: Double = 20.0   // meters
    private var arrivalThreshold: Double = 15.0            // meters
    private var infrastructureAnnounceRadius: Double = 30.0 // meters

    /// Pending destination — set when auth is not yet granted, retried when auth arrives
    private var pendingDestination: String?

    /// Continuation for waiting on a single location fix
    private var locationContinuation: CheckedContinuation<CLLocation, any Error>?

    // MARK: - Initialization

    func initialize(routeService: RouteService, voiceManager: VoiceManager?) {
        self.routeService = routeService
        self.voiceManager = voiceManager

        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager?.distanceFilter = 3.0
        locationManager?.activityType = .fitness

        // Request authorization eagerly so the dialog appears at app launch
        let status = locationManager?.authorizationStatus ?? .notDetermined
        print("[Navigation] Initialized, auth status: \(status.rawValue)")
        if status == .notDetermined {
            print("[Navigation] Requesting location authorization...")
            locationManager?.requestWhenInUseAuthorization()
        }
    }

    // MARK: - Public API

    func startNavigation(to destination: String) {
        print("[Navigation] startNavigation called with destination: '\(destination)'")

        guard let routeService = routeService else {
            print("[Navigation] ERROR: routeService is nil")
            state = .error("Route service not available")
            return
        }

        // Check authorization status
        let authStatus = locationManager?.authorizationStatus ?? .notDetermined
        print("[Navigation] Auth status at nav start: \(authStatus.rawValue)")

        switch authStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break // Good to go
        case .notDetermined:
            // Auth dialog may still be pending — store destination and retry when auth arrives
            print("[Navigation] Auth not determined yet, requesting and storing pending destination")
            state = .planning
            pendingDestination = destination
            locationManager?.requestWhenInUseAuthorization()
            voiceManager?.speak("Please allow location access to navigate", priority: true)
            return
        case .denied, .restricted:
            print("[Navigation] Auth denied/restricted")
            state = .error("Location access denied")
            voiceManager?.speak("Location access is required. Please enable it in Settings.", priority: true)
            return
        @unknown default:
            print("[Navigation] Unknown auth status")
            state = .error("Location unavailable")
            return
        }

        // We're authorized — proceed
        state = .planning
        pendingDestination = nil
        announcedInfrastructureIDs.removeAll()
        print("[Navigation] State -> planning, authorized")

        Task {
            do {
                // Get current location
                print("[Navigation] Getting current location...")
                let origin = try await getCurrentLocation()
                print("[Navigation] Got origin: \(origin.latitude), \(origin.longitude)")

                await performNavigation(from: origin, to: destination, using: routeService)
            } catch {
                print("[Navigation] ERROR in startNavigation task: \(error)")
                state = .error(error.localizedDescription)
                voiceManager?.speak("Navigation error: \(error.localizedDescription)", priority: true)
            }
        }
    }

    func stopNavigation() {
        state = .idle
        currentRoute = nil
        currentStepIndex = 0
        currentGuidance = nil
        distanceToNextManeuver = 0
        distanceToDestination = 0
        announcedInfrastructureIDs.removeAll()
        pendingDestination = nil
        locationManager?.stopUpdatingLocation()
        locationManager?.stopUpdatingHeading()
        voiceManager?.speak("Navigation stopped", priority: true)
        print("[Navigation] Stopped")
    }

    // MARK: - Location

    private func getCurrentLocation() async throws -> CLLocationCoordinate2D {
        // If we already have a recent location (< 10s old), use it
        if let existing = locationManager?.location,
           abs(existing.timestamp.timeIntervalSinceNow) < 10 {
            print("[Navigation] Using cached location: \(existing.coordinate.latitude), \(existing.coordinate.longitude)")
            return existing.coordinate
        }

        print("[Navigation] No recent location, requesting single fix...")

        // Request a single location fix and wait for delegate callback
        let location = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, any Error>) in
            self.locationContinuation = continuation
            self.locationManager?.requestLocation()
            print("[Navigation] requestLocation() called, waiting for delegate callback...")
        }
        self.locationContinuation = nil
        print("[Navigation] Got location fix: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        return location.coordinate
    }

    // MARK: - Navigation Flow

    private func performNavigation(from origin: CLLocationCoordinate2D, to destination: String, using routeService: RouteService) async {
        do {
            // Geocode destination
            print("[Navigation] Geocoding '\(destination)'...")
            let (destCoord, destName) = try await routeService.geocode(destination)
            print("[Navigation] Geocoded to: \(destCoord.latitude), \(destCoord.longitude) (\(destName))")

            // Fetch route
            print("[Navigation] Fetching route...")
            var route = try await routeService.fetchRoute(from: origin, to: destCoord, destinationName: destName)
            print("[Navigation] Route: \(route.steps.count) steps, \(Int(route.totalDistanceMeters))m")

            guard !route.steps.isEmpty else {
                state = .error("No route found")
                voiceManager?.speak("Could not find a walking route", priority: true)
                return
            }

            // Start navigating immediately
            currentRoute = route
            currentStepIndex = 0
            state = .navigating(stepIndex: 0)
            print("[Navigation] State -> navigating(0)")

            // Start GPS tracking
            locationManager?.startUpdatingLocation()
            locationManager?.startUpdatingHeading()

            // Announce start
            let firstInstruction = route.steps[0].instruction
            let totalDist = Int(route.totalDistanceMeters)
            let announcement = "Navigating to \(destName). \(firstInstruction). Total distance \(totalDist) meters."
            print("[Navigation] Announcing: \(announcement)")
            voiceManager?.speak(announcement, priority: true)

            updateGuidance()

            // Augment with infrastructure in background (non-blocking)
            Task {
                do {
                    try await routeService.augmentWithInfrastructure(&route)
                    self.currentRoute = route
                    print("[Navigation] Infrastructure enrichment complete")
                } catch {
                    print("[Navigation] Infrastructure enrichment failed: \(error)")
                }
            }

        } catch {
            print("[Navigation] performNavigation error: \(error)")
            state = .error(error.localizedDescription)
            voiceManager?.speak("Navigation error: \(error.localizedDescription)", priority: true)
        }
    }

    // MARK: - Location Processing

    private func processLocationUpdate(_ location: CLLocation) {
        guard case .navigating(let stepIndex) = state,
              let route = currentRoute else { return }

        userLocation = location.coordinate
        let coord = location.coordinate

        // Check arrival at destination
        let destDist = coord.distance(to: route.destination)
        distanceToDestination = destDist

        if destDist < arrivalThreshold {
            state = .arrived
            voiceManager?.speak("You have arrived at \(route.destinationName)", priority: true)
            locationManager?.stopUpdatingLocation()
            locationManager?.stopUpdatingHeading()
            print("[Navigation] Arrived at destination")
            return
        }

        // Check step advancement
        guard stepIndex < route.steps.count else { return }
        let currentStep = route.steps[stepIndex]
        let distToStepEnd = coord.distance(to: currentStep.endLocation)
        distanceToNextManeuver = distToStepEnd

        if distToStepEnd < stepAdvancementThreshold {
            let nextIndex = stepIndex + 1
            if nextIndex < route.steps.count {
                currentStepIndex = nextIndex
                state = .navigating(stepIndex: nextIndex)

                let nextStep = route.steps[nextIndex]
                voiceManager?.speak(nextStep.instruction, priority: true)
                print("[Navigation] Advanced to step \(nextIndex): \(nextStep.instruction)")
            } else {
                state = .arriving
                voiceManager?.speak("Approaching destination", priority: false)
            }
        }

        // Check nearby infrastructure
        checkNearbyInfrastructure(at: coord, stepIndex: stepIndex, route: route)

        // Update guidance
        updateGuidance()
    }

    private func checkNearbyInfrastructure(at coord: CLLocationCoordinate2D, stepIndex: Int, route: PedestrianRoute) {
        let stepsToCheck = [stepIndex, stepIndex + 1].filter { $0 < route.steps.count }

        for idx in stepsToCheck {
            for feature in route.steps[idx].infrastructure {
                guard !announcedInfrastructureIDs.contains(feature.id) else { continue }

                let dist = coord.distance(to: feature.coordinate)
                if dist < infrastructureAnnounceRadius {
                    announcedInfrastructureIDs.insert(feature.id)
                    voiceManager?.speak(feature.type.spokenWarning, priority: false)
                    print("[Navigation] Infrastructure alert: \(feature.type.rawValue) at \(Int(dist))m")
                }
            }
        }
    }

    private func updateGuidance() {
        guard let route = currentRoute,
              currentStepIndex < route.steps.count else {
            currentGuidance = nil
            return
        }

        let step = route.steps[currentStepIndex]

        var nearby: [InfrastructureFeature] = []
        if let loc = userLocation {
            let stepsToCheck = [currentStepIndex, currentStepIndex + 1].filter { $0 < route.steps.count }
            for idx in stepsToCheck {
                for feature in route.steps[idx].infrastructure {
                    if loc.distance(to: feature.coordinate) < 50 {
                        nearby.append(feature)
                    }
                }
            }
        }

        currentGuidance = NavigationGuidance(
            currentInstruction: step.instruction,
            distanceToNextManeuver: distanceToNextManeuver,
            nearbyInfrastructure: nearby
        )
    }
}

// MARK: - CLLocationManagerDelegate

extension NavigationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        print("[Navigation] didUpdateLocations: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        Task { @MainActor in
            if let continuation = self.locationContinuation {
                self.locationContinuation = nil
                continuation.resume(returning: location)
                return
            }
            self.processLocationUpdate(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let heading = newHeading.trueHeading
        Task { @MainActor in
            self.headingDegrees = heading
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[Navigation] didFailWithError: \(error)")
        Task { @MainActor in
            if let continuation = self.locationContinuation {
                self.locationContinuation = nil
                continuation.resume(throwing: error)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        print("[Navigation] didChangeAuthorization: \(status.rawValue) (0=notDetermined, 2=denied, 4=whenInUse)")
        Task { @MainActor in
            // If we have a pending destination and just got authorized, retry navigation
            if (status == .authorizedWhenInUse || status == .authorizedAlways),
               let dest = self.pendingDestination {
                print("[Navigation] Auth granted! Retrying navigation to '\(dest)'")
                self.pendingDestination = nil
                self.startNavigation(to: dest)
            }
        }
    }
}
