//
//  RouteService.swift
//  SmartCane
//
//  Google Routes API + Overpass API for pedestrian navigation
//

import Foundation
import CoreLocation

class RouteService {
    private let apiKey: String
    private let session = URLSession.shared

    init(googleApiKey: String) {
        self.apiKey = googleApiKey
    }

    // MARK: - Geocoding

    func geocode(_ address: String) async throws -> (CLLocationCoordinate2D, String) {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw RouteError.invalidAddress
        }

        let urlString = "https://maps.googleapis.com/maps/api/geocode/json?address=\(encoded)&key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw RouteError.invalidAddress }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw RouteError.geocodingFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let geometry = first["geometry"] as? [String: Any],
              let location = geometry["location"] as? [String: Double],
              let lat = location["lat"],
              let lng = location["lng"] else {
            throw RouteError.geocodingFailed
        }

        let formattedAddress = first["formatted_address"] as? String ?? address
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)

        print("[RouteService] Geocoded '\(address)' -> \(lat), \(lng)")
        return (coordinate, formattedAddress)
    }

    // MARK: - Route Fetching

    func fetchRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, destinationName: String) async throws -> PedestrianRoute {
        let url = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("routes.legs.steps.navigationInstruction,routes.legs.steps.startLocation,routes.legs.steps.endLocation,routes.legs.steps.distanceMeters,routes.legs.steps.polyline,routes.legs.polyline,routes.legs.distanceMeters,routes.legs.duration,routes.distanceMeters,routes.duration", forHTTPHeaderField: "X-Goog-FieldMask")

        let body: [String: Any] = [
            "origin": [
                "location": [
                    "latLng": ["latitude": origin.latitude, "longitude": origin.longitude]
                ]
            ],
            "destination": [
                "location": [
                    "latLng": ["latitude": destination.latitude, "longitude": destination.longitude]
                ]
            ],
            "travelMode": "WALK",
            "polylineEncoding": "GEO_JSON_LINESTRING",
            "routeModifiers": [
                "avoidIndoor": true   // Avoid indoor paths (stairs, elevators, escalators)
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let bodyStr = String(data: data, encoding: .utf8) ?? "no body"
            print("[RouteService] Routes API error \(statusCode): \(bodyStr)")
            throw RouteError.routeFetchFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let routes = json["routes"] as? [[String: Any]],
              let firstRoute = routes.first,
              let legs = firstRoute["legs"] as? [[String: Any]],
              let firstLeg = legs.first,
              let stepsJson = firstLeg["steps"] as? [[String: Any]] else {
            throw RouteError.routeParseFailed
        }

        let totalDistance = (firstRoute["distanceMeters"] as? Int) ?? 0
        let durationStr = (firstRoute["duration"] as? String) ?? "0s"
        let totalDuration = Self.parseDuration(durationStr)

        // Parse overview polyline
        var overviewPolyline: [CLLocationCoordinate2D] = []
        if let legPoly = firstLeg["polyline"] as? [String: Any] {
            overviewPolyline = Self.parseGeoJsonLineString(legPoly)
        }

        // Parse steps
        var steps: [RouteStep] = []
        for stepJson in stepsJson {
            let step = Self.parseStep(stepJson)
            steps.append(step)
        }

        print("[RouteService] Route fetched: \(steps.count) steps, \(totalDistance)m, \(Int(totalDuration))s")

        return PedestrianRoute(
            origin: origin,
            destination: destination,
            destinationName: destinationName,
            steps: steps,
            overviewPolyline: overviewPolyline,
            totalDistanceMeters: Double(totalDistance),
            totalDurationSeconds: totalDuration
        )
    }

    // MARK: - Infrastructure Enrichment (Overpass API)

    func augmentWithInfrastructure(_ route: inout PedestrianRoute) async throws {
        let bbox = Self.computeBoundingBox(route.overviewPolyline, bufferMeters: 50)

        let query = """
        [out:json][timeout:10];
        (
          node["highway"="crossing"](\(bbox));
          node["highway"="traffic_signals"](\(bbox));
          node["highway"="stop"](\(bbox));
        );
        out body;
        """

        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://overpass-api.de/api/interpreter?data=\(encoded)") else {
            print("[RouteService] Overpass query encoding failed")
            return
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("[RouteService] Overpass API error")
            return
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else {
            return
        }

        var features: [InfrastructureFeature] = []
        for element in elements {
            guard let lat = element["lat"] as? Double,
                  let lon = element["lon"] as? Double,
                  let tags = element["tags"] as? [String: String] else { continue }

            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let type: InfrastructureType?

            if tags["highway"] == "crossing" {
                type = .crosswalk
            } else if tags["highway"] == "traffic_signals" {
                type = .trafficSignal
            } else if tags["highway"] == "stop" {
                type = .stopSign
            } else {
                type = nil
            }

            guard let infraType = type else { continue }

            // Find nearest step and distance
            var minDist = Double.greatestFiniteMagnitude
            var nearestStepIndex = 0
            for (i, step) in route.steps.enumerated() {
                for point in step.polyline {
                    let d = coord.distance(to: point)
                    if d < minDist {
                        minDist = d
                        nearestStepIndex = i
                    }
                }
            }

            // Only include features within 50m of the route
            guard minDist <= 50 else { continue }

            let feature = InfrastructureFeature(
                type: infraType,
                coordinate: coord,
                distanceFromRoute: minDist
            )
            features.append(feature)

            // Assign to nearest step
            if nearestStepIndex < route.steps.count {
                route.steps[nearestStepIndex].infrastructure.append(feature)
            }
        }

        print("[RouteService] Infrastructure: \(features.count) features (crosswalks, signals, stops)")
    }

    // MARK: - Parsing Helpers

    private static func parseStep(_ json: [String: Any]) -> RouteStep {
        let navInstruction = json["navigationInstruction"] as? [String: Any]
        let instruction = navInstruction?["instructions"] as? String ?? ""
        let maneuverStr = navInstruction?["maneuver"] as? String ?? ""
        let maneuver = Maneuver(rawValue: maneuverStr) ?? .unknown

        let distanceMeters = json["distanceMeters"] as? Double
            ?? Double(json["distanceMeters"] as? Int ?? 0)

        let startLoc = parseLatLng(json["startLocation"] as? [String: Any])
        let endLoc = parseLatLng(json["endLocation"] as? [String: Any])

        var polyline: [CLLocationCoordinate2D] = []
        if let polyJson = json["polyline"] as? [String: Any] {
            polyline = parseGeoJsonLineString(polyJson)
        }

        return RouteStep(
            instruction: instruction,
            maneuver: maneuver,
            distanceMeters: distanceMeters,
            startLocation: startLoc,
            endLocation: endLoc,
            polyline: polyline,
            infrastructure: []
        )
    }

    private static func parseLatLng(_ json: [String: Any]?) -> CLLocationCoordinate2D {
        guard let json = json,
              let latLng = json["latLng"] as? [String: Any],
              let lat = latLng["latitude"] as? Double,
              let lng = latLng["longitude"] as? Double else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private static func parseGeoJsonLineString(_ json: [String: Any]) -> [CLLocationCoordinate2D] {
        guard let geoJson = json["geoJsonLinestring"] as? [String: Any],
              let coordinates = geoJson["coordinates"] as? [[Double]] else {
            return []
        }
        return coordinates.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
    }

    private static func parseDuration(_ str: String) -> Double {
        // Google returns duration as "123s"
        let cleaned = str.replacingOccurrences(of: "s", with: "")
        return Double(cleaned) ?? 0
    }

    private static func computeBoundingBox(_ coords: [CLLocationCoordinate2D], bufferMeters: Double) -> String {
        guard !coords.isEmpty else { return "0,0,0,0" }

        var minLat = coords[0].latitude
        var maxLat = coords[0].latitude
        var minLng = coords[0].longitude
        var maxLng = coords[0].longitude

        for c in coords {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude)
            maxLng = max(maxLng, c.longitude)
        }

        // ~50m buffer in degrees (rough approximation)
        let latBuffer = bufferMeters / 111_111.0
        let lngBuffer = bufferMeters / (111_111.0 * cos(minLat * .pi / 180))

        return String(format: "%.6f,%.6f,%.6f,%.6f",
                      minLat - latBuffer, minLng - lngBuffer,
                      maxLat + latBuffer, maxLng + lngBuffer)
    }
}

// MARK: - Errors

enum RouteError: LocalizedError {
    case invalidAddress
    case geocodingFailed
    case routeFetchFailed
    case routeParseFailed

    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Invalid address"
        case .geocodingFailed: return "Could not find that location"
        case .routeFetchFailed: return "Failed to fetch route"
        case .routeParseFailed: return "Failed to parse route data"
        }
    }
}
