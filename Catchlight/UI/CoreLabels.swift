//
//  CoreLabels.swift
//  Catchlight (iOS app target)
//
//  The translated words for CatchlightCore values the app shows. Core's own `label` /
//  `displayName` stay English and identifier-like: Core carries no translations, so the
//  app that shows a value supplies its wording (the `SpotlightExposure.label` precedent
//  in SettingsViewModel). If a second app needs the same words, that is the point to
//  move them into Core with a catalog of their own.
//

import CatchlightCore

extension TimeReminder.Recurrence {
    /// The cadence word on the card ("Tomorrow at 9:00 · Daily").
    var localizedLabel: String {
        switch self {
        case .none:     return String(localized: "Never")
        case .hourly:   return String(localized: "Hourly")
        case .daily:    return String(localized: "Daily")
        case .weekly:   return String(localized: "Weekly")
        case .monthly:  return String(localized: "Monthly")
        case .annually: return String(localized: "Annually")
        }
    }
}

extension WritingToolsBehaviour {
    /// The Settings picker's option name.
    var localizedLabel: String {
        switch self {
        case .off:    return String(localized: "Off")
        case .panel:  return String(localized: "Panel")
        case .inline: return String(localized: "Inline")
        }
    }
}

extension DiagnosticCategory {
    /// The category VoiceOver reads before a Notice History entry.
    var localizedName: String {
        switch self {
        case .sync:       return String(localized: "Sync")
        case .storage:    return String(localized: "Storage")
        case .conflict:   return String(localized: "Conflict")
        case .quarantine: return String(localized: "Quarantine")
        case .lifecycle:  return String(localized: "App")
        }
    }
}
