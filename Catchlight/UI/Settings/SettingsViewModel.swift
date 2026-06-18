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

    /// What a freshly-added reminder's "when" defaults to (owner 2026-06-18 — a user
    /// preference, not a baked-in +24h). `PetalFanView.defaultReminderDate` reads
    /// `current` when seeding the picker; the user always refines from there.
    enum DefaultReminderWhen: String, CaseIterable, Identifiable {
        case inOneHour, thisEvening, tomorrowMorning, tomorrowSameTime

        static let defaultsKey = "catchlight.defaultReminderWhen"
        static let `default`: DefaultReminderWhen = .tomorrowMorning

        private static let eveningHour = 18
        private static let morningHour = 9   // matches ReminderScheduler.allDayFireHour

        var id: String { rawValue }

        var label: String {
            switch self {
            case .inOneHour:        return "In 1 hour"
            case .thisEvening:      return "This evening"
            case .tomorrowMorning:  return "Tomorrow morning"
            case .tomorrowSameTime: return "Tomorrow, same time"
            }
        }

        /// Resolve to a concrete FUTURE date from `now` — all Calendar math, no
        /// hardcoded formats (the picker then shows it in the user's Region/12-24h style).
        func date(from now: Date = Date(), calendar: Calendar = .current) -> Date {
            switch self {
            case .inOneHour:
                return now.addingTimeInterval(3600)
            case .thisEvening:
                let today = calendar.date(bySettingHour: Self.eveningHour, minute: 0, second: 0, of: now) ?? now
                return today > now ? today : (calendar.date(byAdding: .day, value: 1, to: today) ?? today)
            case .tomorrowMorning:
                let next = calendar.date(byAdding: .day, value: 1, to: now) ?? now
                return calendar.date(bySettingHour: Self.morningHour, minute: 0, second: 0, of: next) ?? next
            case .tomorrowSameTime:
                return calendar.date(byAdding: .day, value: 1, to: now) ?? now
            }
        }

        /// The user's current choice (falls back to the default), from the same
        /// UserDefaults key the Settings picker writes via `@AppStorage`.
        static var current: DefaultReminderWhen {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let value = DefaultReminderWhen(rawValue: raw) else { return .default }
            return value
        }
    }

    /// Timeline density — how much clear space sits between consecutive Takes on
    /// Dailies (owner 2026-06-16). Changes ONLY the inter-card gap; the cards, Iris,
    /// and spine are untouched. `gap` is the clear distance from one card's bottom to
    /// the next card's top, sized so the lower card's Iris (which straddles its top
    /// edge, poking up one radius ≈ 22pt) never overlaps the card above. Read by
    /// `DailiesView` via `@AppStorage`.
    enum TakeSpacing: String, CaseIterable, Identifiable {
        case compact, standard, comfort

        static let defaultsKey = "catchlight.takeSpacing"
        static let `default`: TakeSpacing = .standard

        var id: String { rawValue }

        /// Clear gap between consecutive cards. Floor is the Iris's upper half
        /// (≈22pt) plus breathing room so Compact reads "close but not touching."
        var gap: CGFloat {
            switch self {
            case .compact:  return 26
            case .standard: return 44
            case .comfort:  return 56
            }
        }

        var label: String {
            switch self {
            case .compact:  return "Compact"
            case .standard: return "Standard"
            case .comfort:  return "Comfort"
            }
        }

        static var current: TakeSpacing {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let value = TakeSpacing(rawValue: raw) else { return .default }
            return value
        }
    }

    /// Timeline sort direction — which end of time sits at the TOP (owner 2026-06-16).
    /// The Obie is pinned above the list regardless. Default `.oldestFirst`: the
    /// oldest Take is on top and newer ones accrue below, so scrolling down moves
    /// toward "now" and older Takes fall off the top. This is also the order under
    /// which the chronologically-timed seed Takes read Note·Task·Reminder·Delete.
    /// `.newestFirst` inverts it. Read by `DailiesView`.
    enum TakeSort: String, CaseIterable, Identifiable {
        case oldestFirst, newestFirst

        static let defaultsKey = "catchlight.takeSort"
        static let `default`: TakeSort = .oldestFirst

        var id: String { rawValue }

        /// Short label for the segmented control.
        var label: String {
            switch self {
            case .oldestFirst: return "Oldest"
            case .newestFirst: return "Newest"
            }
        }

        static var current: TakeSort {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let value = TakeSort(rawValue: raw) else { return .default }
            return value
        }
    }

    /// How much of a collapsed Take's body shows on the timeline (owner 2026-06-16:
    /// "Preview" — deliberately INDEPENDENT of `TakeSpacing`/"View" density). The
    /// reminder date/time label is unaffected (it's a separate line below the body).
    enum TakePreview: String, CaseIterable, Identifiable {
        case single, some, all

        static let defaultsKey = "catchlight.takePreview"
        static let `default`: TakePreview = .some

        var id: String { rawValue }

        /// Body line cap; `nil` = unlimited (show the whole Take).
        var lineLimit: Int? {
            switch self {
            case .single: return 1
            case .some:   return 3
            case .all:    return nil
            }
        }

        /// Short label for the segmented control.
        var label: String {
            switch self {
            case .single: return "Single"
            case .some:   return "Some"
            case .all:    return "All"
            }
        }

        static var current: TakePreview {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let value = TakePreview(rawValue: raw) else { return .default }
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
