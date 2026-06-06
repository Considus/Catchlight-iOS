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

    var notificationStatus: UNAuthorizationStatus = .notDetermined
    var notificationStatusLoading: Bool = false

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
