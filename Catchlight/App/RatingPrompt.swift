//
//  RatingPrompt.swift
//  Catchlight (iOS app target)
//
//  When Catchlight asks for an App Store rating (owner 2026-10-06). Apple shows the
//  system prompt at most three times a year and says to ask after the person has
//  finished something, never as an interruption. So the app asks only straight after
//  one of two success moments, and only once the person has had the app for a few
//  days, is not in the read-only lapse, and has not been asked in this version or in
//  the last 120 days.
//
//  The prompt runs entirely through StoreKit. Nothing here leaves the device: the
//  ledger is three values in this device's UserDefaults.
//

import Foundation
import CatchlightCore

/// A moment worth asking after.
enum RatingMoment: Equatable {
    /// Every item on a checklist of at least `RatingPrompt.minimumChecklistItems` was
    /// just ticked off.
    case checklistFinished
    /// A new Take was written, and Takes have now been written on
    /// `RatingPrompt.writingDaysForHabit` different days since the first launch.
    case writingHabit
}

enum RatingPrompt {
    static let minimumDaysSinceFirstLaunch = 3
    static let writingDaysForHabit = 7
    static let minimumChecklistItems = 3
    static let daysBetweenAsks = 120

    /// The moment a save makes, if any. `previous` is the stored Take before the save
    /// (nil for a new Take); `allCreatedAt` is every Take's creation date after it.
    static func moment(previous: Take?, updated: Take, allCreatedAt: [Date],
                       firstLaunch: Date, calendar: Calendar = .current) -> RatingMoment? {
        if updated.isComplete, updated.checkItems.count >= minimumChecklistItems,
           previous.map({ !$0.isComplete }) ?? false {
            return .checklistFinished
        }
        if previous == nil,
           writingDays(allCreatedAt, since: firstLaunch, calendar: calendar) >= writingDaysForHabit {
            return .writingHabit
        }
        return nil
    }

    /// How many different calendar days have a Take created on or after `since`. Takes
    /// from before the first launch (imported, restored or synced in) do not count.
    static func writingDays(_ dates: [Date], since: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: since)
        return Set(dates.filter { $0 >= start }.map { calendar.startOfDay(for: $0) }).count
    }

    /// Whether to ask now, given the ledger and the app's state.
    static func shouldAsk(now: Date, firstLaunch: Date, lastAsked: Date?,
                          lastAskedVersion: String?, currentVersion: String,
                          isEntitled: Bool, calendar: Calendar = .current) -> Bool {
        guard isEntitled, lastAskedVersion != currentVersion else { return false }
        guard days(from: firstLaunch, to: now, calendar) >= minimumDaysSinceFirstLaunch else { return false }
        if let lastAsked, days(from: lastAsked, to: now, calendar) < daysBetweenAsks { return false }
        return true
    }

    private static func days(from: Date, to: Date, _ calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from),
                                to: calendar.startOfDay(for: to)).day ?? 0
    }
}

/// The three values the policy needs, kept in this device's UserDefaults.
struct RatingPromptLedger {
    private let defaults: UserDefaults
    private static let firstLaunchKey = "catchlight.rating.firstLaunch"
    private static let lastAskedKey = "catchlight.rating.lastAsked"
    private static let lastAskedVersionKey = "catchlight.rating.lastAskedVersion"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// The first launch this ledger saw, recorded on first read.
    var firstLaunch: Date {
        if let date = defaults.object(forKey: Self.firstLaunchKey) as? Date { return date }
        let now = Date()
        defaults.set(now, forKey: Self.firstLaunchKey)
        return now
    }

    var lastAsked: Date? { defaults.object(forKey: Self.lastAskedKey) as? Date }
    var lastAskedVersion: String? { defaults.string(forKey: Self.lastAskedVersionKey) }

    func recordAsked(at date: Date, version: String) {
        defaults.set(date, forKey: Self.lastAskedKey)
        defaults.set(version, forKey: Self.lastAskedVersionKey)
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
