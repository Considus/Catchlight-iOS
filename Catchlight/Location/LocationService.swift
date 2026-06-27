//
//  LocationService.swift
//  Catchlight (iOS app target)
//
//  Core Location seam for LOCATION reminders (owner 2026-06-23). Catchlight uses
//  `UNLocationNotificationTrigger`, where iOS's own notification daemon monitors the
//  geofence — so the app needs only "When In Use" authorisation and never runs location
//  in the background (the same posture as Apple Reminders, and why the permission prompt
//  is the lighter "While Using" one). This wrapper owns the single `CLLocationManager`:
//  it requests that authorisation and provides a one-shot current location for the place
//  picker's "Use current location". It deliberately does NOT start continuous updates.
//

import CoreLocation
import Combine

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {

    /// Current authorisation — drives whether the picker shows a "grant access" hint and
    /// whether "Use current location" is offered.
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// The most recent one-shot fix, if any (nil until `requestCurrentLocation` resolves).
    @Published private(set) var currentLocation: CLLocation?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
    }

    /// Prompt for "When In Use" — sufficient for `UNLocationNotificationTrigger` (the system
    /// does the monitoring). No-op once a decision exists; the result arrives via the delegate.
    func requestAuthorization() {
        guard authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// One-shot location for the place picker. Requires at least "When In Use"; the delegate
    /// publishes the fix (or an error we swallow — the picker falls back to a default region).
    func requestCurrentLocation() {
        manager.requestLocation()
    }

    /// Whether a geofence reminder can actually be armed right now (authorised either tier).
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    // MARK: - CLLocationManagerDelegate
    // Callbacks may arrive off the main actor; hop back before touching @Published state.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorizationStatus = status }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.currentLocation = last }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Best-effort: a failed one-shot just leaves `currentLocation` nil; the picker copes.
    }
}
