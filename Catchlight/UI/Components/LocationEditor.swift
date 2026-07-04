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
    @State private var radiusMetres: Double

    /// Selectable geofence radii (owner 2026-06-27). 100 m is iOS's reliability floor
    /// (`ReminderScheduler.minGeofenceRadius`) — below it the fence is missed or fires late;
    /// 150 m is the reliable default; 250 / 500 m give an earlier, wider heads-up.
    static let radiusOptions: [Double] = [100, 150, 250, 500]

    /// Snap an arbitrary stored radius to the nearest option (older Takes stored a fixed 150).
    private static func nearestOption(to value: Double) -> Double {
        radiusOptions.min(by: { abs($0 - value) < abs($1 - value) }) ?? ReminderScheduler.defaultGeofenceRadius
    }

    /// The name this editor writes when a fresh fix drops a pin and the user
    /// hasn't named the place. Distinguishing it from a real user name is what
    /// stops the async reverse geocode clobbering e.g. "Home".
    static let currentLocationPlaceholder = "Current location"

    /// Whether the reverse-geocoded name may replace the current one: only when
    /// the field is empty or still the auto placeholder. Pure so the clobber
    /// guard is unit-testable without the view (2026-07-04).
    static func shouldAdoptGeocodedName(currentName: String) -> Bool {
        currentName.isEmpty || currentName == currentLocationPlaceholder
    }

    init(trigger: Binding<LocationTrigger?>) {
        _trigger = trigger
        let t = trigger.wrappedValue
        let coord = t.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let r = Self.nearestOption(to: t?.radiusMetres ?? ReminderScheduler.defaultGeofenceRadius)
        _coordinate = State(initialValue: coord)
        _name = State(initialValue: t?.locationName ?? "")
        _arriveOnEntry = State(initialValue: t?.triggerOnArrival ?? true)
        _alarmEnabled = State(initialValue: t?.alarmEnabled ?? true)
        _radiusMetres = State(initialValue: r)
        _cameraPosition = State(initialValue: coord.map { .region(Self.region(for: $0, radius: r)) } ?? .automatic)
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
            // Only auto-name when the user hasn't named the place (2026-07-01):
            // the slow reverse geocode previously overwrote a chosen name — e.g.
            // re-pinning "Home" renamed it to the street address — and writeBack
            // persisted the clobber. The decision is factored into the pure,
            // testable `shouldAdoptGeocodedName` (2026-07-04).
            let currentName = name
            apply(coordinate: loc.coordinate,
                  name: currentName.isEmpty ? Self.currentLocationPlaceholder : currentName)
            guard Self.shouldAdoptGeocodedName(currentName: currentName) else { return }
            Task { if let resolved = await search.reverseGeocodedName(for: loc) { name = resolved; writeBack() } }
        }
        .onChange(of: name) { _, _ in writeBack() }
        .onChange(of: arriveOnEntry) { _, _ in writeBack() }
        .onChange(of: alarmEnabled) { _, _ in writeBack() }
        .onChange(of: radiusMetres) { _, r in
            // Refit the map so the resized fence stays comfortably framed.
            if let coordinate { cameraPosition = .region(Self.region(for: coordinate, radius: r)) }
            writeBack()
        }
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
            MapCircle(center: coordinate, radius: radiusMetres)
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

            // Geofence radius (owner 2026-06-27). 100 m is the reliable floor; a tighter
            // fence is more precise but iOS may trigger it late or miss it.
            // Nested menu selector — matches the reminder Interval/Days rows (grey
            // value + up/down chevron) rather than a tinted inline Picker (owner 2026-06-29).
            Menu {
                Picker("Radius", selection: $radiusMetres) {
                    ForEach(Self.radiusOptions, id: \.self) { m in
                        Text("\(Int(m)) m").tag(m)
                    }
                }
            } label: {
                MenuFieldRow(title: "Radius", icon: "circle.dashed", value: "\(Int(radiusMetres)) m")
            }
            .accessibilityIdentifier("location-radius-picker")

            if radiusMetres <= ReminderScheduler.minGeofenceRadius {
                Text("A tighter radius is more precise, but iOS may trigger it late or miss it — 100 m is the reliable minimum.")
                    .font(.caption)
                    .foregroundStyle(Color.ckTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)
            }

            Divider()

            // Notify on/off (owner 2026-06-27) — model-C parity with time reminders. Off =
            // a silent place tag (no geofence registered); on = fire on arrive/leave.
            HStack {
                // Filled bell when on, matching the time-reminder Notify toggle
                // (owner 2026-06-29); slash stays for the silent/off place tag.
                Label("Notify", systemImage: alarmEnabled ? "bell.fill" : "bell.slash")
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
                // The same teardrop marker that identifies a location reminder on the
                // Dailies card (owner 2026-06-29), instead of the generic tag.
                Label {
                    Text("Place")
                } icon: {
                    // Size the pin's icon column to a standard SF-symbol box (a hidden
                    // reference symbol) so "Place" left-aligns with the Radius/Notify
                    // rows above — the narrow teardrop alone sat a char-space left
                    // (owner 2026-06-29). The marker is drawn centred over it.
                    Image(systemName: "circle.dashed")
                        .opacity(0)
                        .overlay {
                            LocationPinGlyph(color: Color.ckTextPrimary, size: 18, lineWidth: 1.2)
                        }
                }
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
        cameraPosition = .region(Self.region(for: coordinate, radius: radiusMetres))
        writeBack()
    }

    /// Compose the current selection into the bound trigger (nil while no place is chosen).
    private func writeBack() {
        guard let coordinate else { trigger = nil; return }
        trigger = LocationTrigger(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusMetres: radiusMetres,
            triggerOnArrival: arriveOnEntry,
            locationName: name.isEmpty ? nil : name,
            alarmEnabled: alarmEnabled)
    }

    /// A region framing the geofence comfortably — scales with the radius so the circle
    /// stays well inside the frame at every option (≈3× the radius, with a sensible floor).
    private static func region(for coordinate: CLLocationCoordinate2D, radius: Double) -> MKCoordinateRegion {
        let span = max(600, radius * 3)
        return MKCoordinateRegion(center: coordinate, latitudinalMeters: span, longitudinalMeters: span)
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
