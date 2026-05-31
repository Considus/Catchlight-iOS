//
//  LocationTrigger.swift
//  CatchlightCore
//
//  Location-based reminder (geofence) payload (Phase 5 brief §4.4).
//
//  v1.0 STATUS: this type MUST EXIST but is ALWAYS nil on every Take. No Core
//  Location permission is requested, no UNLocationNotificationTrigger is created,
//  and nothing wires this up. It is present only so that the v1.1 location-reminder
//  feature does not require a breaking data-model migration (Roadmap §4).
//

import Foundation

public struct LocationTrigger: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    /// Geofence radius in metres.
    public var radiusMetres: Double

    /// `true` = fire on arrival; `false` = fire on departure.
    public var triggerOnArrival: Bool

    /// User-provided label, e.g. "Home". Optional.
    public var locationName: String?

    public init(
        latitude: Double,
        longitude: Double,
        radiusMetres: Double,
        triggerOnArrival: Bool,
        locationName: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMetres = radiusMetres
        self.triggerOnArrival = triggerOnArrival
        self.locationName = locationName
    }
}
