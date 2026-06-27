//
//  LocationEditor.swift
//  Catchlight (iOS app target)
//
//  The inline "Place" controls for a location reminder (owner 2026-06-23, Phase-1). Shown
//  under the reminder picker's Time/Place switch when Place is selected. Lets the user
//  choose a place — by search-as-you-type or one-tap current location — see the geofence on
//  a map, pick arrive vs leave, and name it. Writes the result to a bound `LocationTrigger?`
//  (radius fixed at ReminderScheduler.defaultGeofenceRadius). Owns its own `LocationService`
//  for the "While Using" prompt + a one-shot current location; the geofence itself is armed
//  by ReminderScheduler once the Take saves.
//
//  A reminder is EITHER time-based OR location-based (owner 2026-06-24) — never both — so
//  this editor stands alone in the Place tab; there is no time UI here.
//

import SwiftUI
import MapKit
import CoreLocation
import CatchlightCore

struct LocationEditor: View {
    /// The composed result, kept in sync with the controls. Nil until a place is chosen.
    @Binding var trigger: LocationTrigger?

    @StateObject private var location = LocationService()
    @StateObject private var search = PlaceSearchCompleter()

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var name: String
    @State private var arriveOnEntry: Bool
    @State private var alarmEnabled: Bool
    @State private var cameraPosition: MapCameraPosition
    @State private var query: String = ""

    private let radius = ReminderScheduler.defaultGeofenceRadius

    init(trigger: Binding<LocationTrigger?>) {
        _trigger = trigger
        let t = trigger.wrappedValue
        let coord = t.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        _coordinate = State(initialValue: coord)
        _name = State(initialValue: t?.locationName ?? "")
        _arriveOnEntry = State(initialValue: t?.triggerOnArrival ?? true)
        _alarmEnabled = State(initialValue: t?.alarmEnabled ?? true)
        _cameraPosition = State(initialValue: coord.map { .region(Self.region(for: $0)) } ?? .automatic)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            searchField
            if !search.results.isEmpty && !query.isEmpty {
                resultsList
            } else {
                currentLocationButton
                if let coordinate { mapPreview(coordinate) }
                if coordinate != nil { detailControls }
                if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
                    permissionHint
                }
            }
        }
        .onAppear { location.requestAuthorization() }
        // A fresh one-shot fix drops the pin on the user's spot + names it.
        .onChange(of: location.currentLocation) { _, loc in
            guard let loc else { return }
            apply(coordinate: loc.coordinate, name: name.isEmpty ? "Current location" : name)
            Task { if let resolved = await search.reverseGeocodedName(for: loc) { name = resolved; writeBack() } }
        }
        .onChange(of: name) { _, _ in writeBack() }
        .onChange(of: arriveOnEntry) { _, _ in writeBack() }
        .onChange(of: alarmEnabled) { _, _ in writeBack() }
    }

    // MARK: - Sections

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.ckTextSecondary)
            TextField("Search a place or address", text: $query)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("location-search-field")
            if !query.isEmpty {
                Button { query = ""; search.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.ckTextSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.ckSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onChange(of: query) { _, q in search.query = q }
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            ForEach(search.results, id: \.self) { result in
                Button { select(result) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title).foregroundStyle(Color.ckTextPrimary)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle).font(.caption).foregroundStyle(Color.ckTextSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .padding(.horizontal, 14)
        .background(Color.ckSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var currentLocationButton: some View {
        Button { location.requestCurrentLocation() } label: {
            Label("Use current location", systemImage: "location.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.ckSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.ckEmber.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.ckTextPrimary)
        .accessibilityIdentifier("location-use-current")
    }

    private func mapPreview(_ coordinate: CLLocationCoordinate2D) -> some View {
        Map(position: $cameraPosition) {
            MapCircle(center: coordinate, radius: radius)
                .foregroundStyle(Color.ckEmber.opacity(0.18))
                .stroke(Color.ckEmber, lineWidth: 2)
        }
        .mapStyle(.standard)
        // A fixed centre pin + "move the map under the pin" — drag to fine-tune the fence.
        .overlay { Image(systemName: "mappin").font(.title2).foregroundStyle(Color.ckEmber) }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onMapCameraChange(frequency: .onEnd) { context in
            self.coordinate = context.region.center
            writeBack()
        }
    }

    private var detailControls: some View {
        VStack(spacing: 0) {
            Picker("Trigger", selection: $arriveOnEntry) {
                Text("When I arrive").tag(true)
                Text("When I leave").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 8)
            .accessibilityIdentifier("location-arrive-leave")

            Divider()

            // Notify on/off (owner 2026-06-27) — model-C parity with time reminders. Off =
            // a silent place tag (no geofence registered); on = fire on arrive/leave.
            HStack {
                Label("Notify", systemImage: alarmEnabled ? "bell" : "bell.slash")
                Spacer()
                Toggle("", isOn: $alarmEnabled).labelsHidden().tint(Color.ckEmber)
            }
            .padding(.vertical, 8)
            .accessibilityIdentifier("location-notify-toggle")

            if !alarmEnabled {
                Text("Silent — keeps the place on the Take, with no alert when you arrive or leave.")
                    .font(.caption)
                    .foregroundStyle(Color.ckTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)
            }

            Divider()

            HStack {
                Label("Name", systemImage: "tag")
                TextField("e.g. Home", text: $name)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("location-name-field")
            }
            .padding(.vertical, 8)
        }
        .tint(Color.ckEmber)
        .padding(.horizontal, 14).padding(.vertical, 4)
        .background(Color.ckSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var permissionHint: some View {
        Text("Location access is off. Enable it in Settings to set a place reminder.")
            .font(.footnote)
            .foregroundStyle(Color.ckTextSecondary)
            .padding(.horizontal, 4)
    }

    // MARK: - Actions

    private func select(_ result: MKLocalSearchCompletion) {
        Task {
            guard let (coord, label) = await search.resolve(result) else { return }
            apply(coordinate: coord, name: label)
            query = ""
            search.query = ""
        }
    }

    private func apply(coordinate: CLLocationCoordinate2D, name: String) {
        self.coordinate = coordinate
        if self.name.isEmpty { self.name = name }
        cameraPosition = .region(Self.region(for: coordinate))
        writeBack()
    }

    /// Compose the current selection into the bound trigger (nil while no place is chosen).
    private func writeBack() {
        guard let coordinate else { trigger = nil; return }
        trigger = LocationTrigger(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusMetres: radius,
            triggerOnArrival: arriveOnEntry,
            locationName: name.isEmpty ? nil : name,
            alarmEnabled: alarmEnabled)
    }

    /// A region framing the geofence comfortably (~the circle plus margin).
    private static func region(for coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800)
    }
}

/// Search-as-you-type place suggestions via `MKLocalSearchCompleter`, plus resolving a
/// suggestion to a coordinate and reverse-geocoding a raw location to a name.
@MainActor
final class PlaceSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    /// Bound to the search field; feeds the completer.
    @Published var query: String = "" {
        didSet { completer.queryFragment = query }
    }

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let latest = completer.results
        Task { @MainActor in self.results = latest }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }

    /// Resolve a suggestion to a concrete coordinate + display title.
    func resolve(_ completion: MKLocalSearchCompletion) async -> (CLLocationCoordinate2D, String)? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first else { return nil }
        return (item.placemark.coordinate, completion.title)
    }

    /// A human name for a raw location (street / place / locality), for "current location".
    func reverseGeocodedName(for location: CLLocation) async -> String? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let p = placemarks?.first else { return nil }
        return p.name ?? p.thoroughfare ?? p.locality
    }
}
