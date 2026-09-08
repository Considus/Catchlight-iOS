//
//  WritingToolsBehaviour.swift
//  CatchlightCore
//
//  The user's choice of how much of Apple's Writing Tools the Take editor offers
//  (D-246). Pure model: no UIKit here, so Core stays testable and the mapping to
//  `UIWritingToolsBehavior` lives in the app target beside the text views it
//  configures.
//
//  🚨 WHY THIS EXISTS AT ALL. Writing Tools was NOT a feature anyone added — it
//  arrived by inheritance. The editor is a plain `UITextView` with
//  `writingToolsBehavior` unset, so iOS applies `.complete`, and a Take can be sent
//  to Private Cloud Compute. It was found because a published white paper said three
//  things cross the encryption boundary and "nothing else does": the re-enumeration
//  that produced that sentence counted only the paths the APP opens, and missed the
//  one the OS opens on its behalf.
//
//  The app's promise is why people chose it, so the default is `.off` — but the
//  choice belongs to the user, so this is a lever rather than a prohibition (the
//  direct sibling of `SpotlightExposure`, same section of Settings, same shape,
//  private option as the default).
//

import Foundation

/// How much of Apple's Writing Tools the Take editor offers. Maps to
/// `UIWritingToolsBehavior` at the point of use: `.off` → `.none`,
/// `.panel` → `.limited`, `.inline` → `.complete`.
public enum WritingToolsBehaviour: String, CaseIterable, Identifiable, Sendable {
    /// No Writing Tools anywhere in the editor. Nothing a Take contains can be
    /// handed to the system's writing services. The default.
    case off
    /// The overlay panel only — the user must invoke it deliberately, and the
    /// text goes nowhere until they do.
    case panel
    /// The full inline experience, including proofreading suggestions offered
    /// without being asked for.
    case inline

    public var id: String { rawValue }

    /// The Settings row's value text.
    public var label: String {
        switch self {
        case .off:    return "Off"
        case .panel:  return "Panel"
        case .inline: return "Inline"
        }
    }

    /// 🚨 The default is OFF and must stay OFF. Catchlight's proposition is that
    /// nobody else can read your notes; a default that quietly forwards them to a
    /// remote model would contradict the reason people installed it. A user who
    /// wants the feature can turn it on in two taps.
    public static let `default`: WritingToolsBehaviour = .off

    /// `UserDefaults` key. Namespaced like the other Settings keys so a stray
    /// read cannot collide with an unrelated flag.
    public static let defaultsKey = "settings.writingToolsBehaviour"

    /// The stored choice, clamped to `.default` when absent or unrecognised —
    /// so a corrupted or downgraded value fails CLOSED, to Off, never open.
    public static func current(_ defaults: UserDefaults = .standard) -> WritingToolsBehaviour {
        guard let raw = defaults.string(forKey: defaultsKey),
              let value = WritingToolsBehaviour(rawValue: raw) else { return .default }
        return value
    }
}
