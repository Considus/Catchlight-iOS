//
//  SettingsViewModel.swift
//  Catchlight (iOS app target) — Phase 6 UI, Task 6.14
//
//  Backing state for the Settings sheet. Owns the appearance-mode preference
//  (persisted via UserDefaults under "appearanceMode") and the notification
//  authorization status displayed inline in the Notifications row. Pure SwiftUI
//  + UNUserNotificationCenter — no domain types touched.
//

import SwiftUI
import Observation
import UserNotifications
import Security

@Observable
@MainActor
final class SettingsViewModel {

    /// Persisted appearance preference. Mirrors `@AppStorage("appearanceMode")` in
    /// the View — we keep the source of truth on the view model so `RootView` /
    /// `CatchlightApp` can derive `preferredColorScheme` without re-reading the
    /// SwiftUI property wrapper from non-View code.
    static let appearanceDefaultsKey = "appearanceMode"

    enum AppearanceMode: String, CaseIterable, Identifiable {
        case system, night, daylight
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return "System"
            case .night: return "Night"
            case .daylight: return "Daylight"
            }
        }
        /// Translate to SwiftUI's preferredColorScheme. `nil` means "follow system".
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .night: return .dark
            case .daylight: return .light
            }
        }
    }

    /// "Lock after" grace — how long Catchlight may sit in the background before a
    /// return re-locks it (D-042). Read by `AppModel.relockIfAwayTooLong()`. The app
    /// ALWAYS re-locks on cold launch and when the phone locks while Catchlight is in
    /// the foreground — this only governs the background-grace window.
    enum LockAfter: String, CaseIterable, Identifiable {
        case thirtySeconds, oneMinute, fiveMinutes, thirtyMinutes, oneHour

        static let defaultsKey = "catchlight.lockAfter"
        static let `default`: LockAfter = .oneMinute

        var id: String { rawValue }

        var seconds: TimeInterval {
            switch self {
            case .thirtySeconds: return 30
            case .oneMinute:     return 60
            case .fiveMinutes:   return 300
            case .thirtyMinutes: return 1800
            case .oneHour:       return 3600
            }
        }

        var label: String {
            switch self {
            case .thirtySeconds: return "30 seconds"
            case .oneMinute:     return "1 minute"
            case .fiveMinutes:   return "5 minutes"
            case .thirtyMinutes: return "30 minutes"
            case .oneHour:       return "1 hour"
            }
        }

        /// The user's current choice (falls back to the default), read from the same
        /// UserDefaults key the Settings picker writes via `@AppStorage`.
        static var current: LockAfter {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let value = LockAfter(rawValue: raw) else { return .default }
            return value
        }
    }

    var notificationStatus: UNAuthorizationStatus = .notDetermined
    var notificationStatusLoading: Bool = false

    // MARK: - Sub-sheet presentation (Task 3.12)

    var isPhraseSheetPresented: Bool = false
    var isCloudStorageSheetPresented: Bool = false
    var isAboutSheetPresented: Bool = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Notifications

    /// Pull the current authorization status. Safe to call repeatedly; never prompts.
    func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }

    /// Explicitly request notification permission. Only meaningful in `.notDetermined`
    /// — after the system prompt resolves, refreshes the cached status.
    func requestNotificationPermission() async {
        guard notificationStatus == .notDetermined else { return }
        notificationStatusLoading = true
        _ = await ReminderScheduler().requestAuthorization()
        await refreshNotificationStatus()
        notificationStatusLoading = false
    }

    /// True if the system considers the app authorised to deliver any kind of
    /// reminder notification (authorised, provisional, or ephemeral).
    var notificationsEffectivelyEnabled: Bool {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }
}
