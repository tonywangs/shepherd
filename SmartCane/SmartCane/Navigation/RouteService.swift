//
//  RouteService.swift
//  SmartCane
//
//  OpenRouteService wheelchair routing + Google Geocoding + Overpass infrastructure
//

import Foundation
import CoreLocation

class RouteService {
    private let googleApiKey: String
    private let orsApiKey: String
    private let session = URLSession.shared

    init(googleApiKey: String, openRouteServiceApiKey: String) {
        self.googleApiKey = googleApiKey
        self.orsApiKey = openRouteServiceApiKey
    }

    // MARK: - Geocoding (Google)

    func geocode(_ address: String) async throws -> (CLLocationCoordinate2D, String) {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw RouteError.invalidAddress
        }

        let urlString = "https://maps.googleapis.com/maps/api/geocode/json?address=\(encoded)&key=\(googleApiKey)"
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

    // MARK: - Route Fetching (OpenRouteService wheelchair profile)

    func fetchRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, destinationName: String) async throws -> PedestrianRoute {
        let url = URL(string: "https://api.openrouteservice.org/v2/directions/wheelchair/geojson")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(orsApiKey, forHTTPHeaderField: "Authorization")

        // ORS uses [longitude, latitude] order
        let body: [String: Any] = [
            "coordinates": [
                [origin.longitude, origin.latitude],
                [destination.longitude, destination.latitude]
            ],
            "instructions": true,
            "preference": "recommended",
            "options": [
                "avoid_features": ["steps"]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let bodyStr = String(data: data, encoding: .utf8) ?? "no body"
            print("[RouteService] ORS API error \(statusCode): \(bodyStr)")
            throw RouteError.routeFetchFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]],
              let feature = features.first,
              let properties = feature["properties"] as? [String: Any],
              let summary = properties["summary"] as? [String: Any],
              let segments = properties["segments"] as? [[String: Any]],
              let geometry = feature["geometry"] as? [String: Any],
              let coordinates = geometry["coordinates"] as? [[Double]] else {
            throw RouteError.routeParseFailed
        }

        let totalDistance = summary["distance"] as? Double ?? 0
        let totalDuration = summary["duration"] as? Double ?? 0

        // Parse overview polyline from geometry coordinates [lon, lat]
        let overviewPolyline: [CLLocationCoordinate2D] = coordinates.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }

        // Parse steps from all segments
        var steps: [RouteStep] = []
        for segment in segments {
            guard let orsSteps = segment["steps"] as? [[String: Any]] else { continue }
            for orsStep in orsSteps {
                let step = parseORSStep(orsStep, allCoordinates: overviewPolyline)
                steps.append(step)
            }
        }

        print("[RouteService] Route fetched: \(steps.count) steps, \(Int(totalDistance))m, \(Int(totalDuration))s (wheelchair, stairs avoided)")

        return PedestrianRoute(
            origin: origin,
            destination: destination,
            destinationName: destinationName,
            steps: steps,
            overviewPolyline: overviewPolyline,
            totalDistanceMeters: totalDistance,
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

    // MARK: - ORS Parsing Helpers

    /// Extract a RouteStep from an ORS step object.
    /// ORS steps include `way_points` — an array of two indices [start, end] into the
    /// route geometry. We slice the full coordinate array to get the step polyline.
    private func parseORSStep(_ json: [String: Any], allCoordinates: [CLLocationCoordinate2D]) -> RouteStep {
        let instruction = json["instruction"] as? String ?? ""
        let distanceMeters = json["distance"] as? Double ?? 0
        let orsType = json["type"] as? Int ?? -1
        let maneuver = Self.orsTypeToManeuver(orsType)

        // way_points: [startIndex, endIndex] into the geometry array
        var stepPolyline: [CLLocationCoordinate2D] = []
        var startLocation = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        var endLocation = CLLocationCoordinate2D(latitude: 0, longitude: 0)

        if let wayPoints = json["way_points"] as? [Int], wayPoints.count >= 2 {
            let startIdx = max(0, wayPoints[0])
            let endIdx = min(allCoordinates.count - 1, wayPoints[1])
            if startIdx <= endIdx {
                stepPolyline = Array(allCoordinates[startIdx...endIdx])
                startLocation = allCoordinates[startIdx]
                endLocation = allCoordinates[endIdx]
            }
        }

        return RouteStep(
            instruction: instruction,
            maneuver: maneuver,
            distanceMeters: distanceMeters,
            startLocation: startLocation,
            endLocation: endLocation,
            polyline: stepPolyline,
            infrastructure: []
        )
    }

    /// Map ORS integer type codes to the existing Maneuver enum.
    /// Reference: https://giscience.github.io/openrouteservice/api-reference/endpoints/directions/routing-options
    private static func orsTypeToManeuver(_ type: Int) -> Maneuver {
        switch type {
        case 0:  return .turnLeft
        case 1:  return .turnRight
        case 2:  return .turnSharpLeft
        case 3:  return .turnSharpRight
        case 4:  return .turnSlightLeft
        case 5:  return .turnSlightRight
        case 6:  return .straight
        case 7:  return .roundaboutRight   // enter roundabout
        case 8:  return .roundaboutLeft    // exit roundabout
        case 9:  return .uturnRight        // U-turn
        case 10: return .arrive            // goal
        case 11: return .depart            // depart
        case 12: return .turnSlightLeft    // keep left
        case 13: return .turnSlightRight   // keep right
        default: return .unknown
        }
    }

    // MARK: - Shared Helpers

    static func parseGeoJsonLineString(_ json: [String: Any]) -> [CLLocationCoordinate2D] {
        guard let geoJson = json["geoJsonLinestring"] as? [String: Any],
              let coordinates = geoJson["coordinates"] as? [[Double]] else {
            return []
        }
        return coordinates.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
    }

    static func computeBoundingBox(_ coords: [CLLocationCoordinate2D], bufferMeters: Double) -> String {
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
