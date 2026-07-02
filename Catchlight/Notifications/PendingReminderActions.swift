//
//  PendingReminderActions.swift
//  Catchlight (iOS app target)
//
//  A tiny app-group-defaults queue for reminder notification actions whose EFFECT
//  needs the encrypted store, but which fire while the phone may be LOCKED (owner
//  2026-06-22).
//
//  The "Dismiss" notification action stops the CURRENT instance nagging. For a
//  ONE-SHOT reminder that means turning its alarm off; for a RECURRING reminder it
//  means only clearing this occurrence — future occurrences must keep firing
//  untouched (owner 2026-06-22). Cancelling the fired instance's OS alarm happens
//  immediately while locked (it's the notification queue, not the store). The
//  one-shot's `alarmEnabled = false`, though, is a store write, and the key is
//  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — unavailable in the background.
//  Snooze sidesteps this by never touching the store; "Dismiss" can't for one-shots.
//
//  So the action records the Take's id here (a plain UUID string — no Take content
//  — written to the app-group defaults, which ARE writable while locked, exactly as
//  the snooze handler already reads a preference while locked). On next unlock,
//  `DailiesViewModel.applyPendingReminderActions()` drains this queue and — for the
//  reminders that turn out to be one-shots — turns the alarm off with the key
//  available, BEFORE the recurring-alarm rebuild runs. Recurring reminders are left
//  entirely alone, so the queue is just "Dismiss was tapped"; the drain decides what
//  (if anything) to persist once it can read each reminder's recurrence.
//

import Foundation
import CatchlightCore

enum PendingReminderActions {

    /// App-group defaults key holding the set of Take ids a background "Dismiss" tap
    /// touched. A SET (deduped) — repeated taps on the same reminder collapse to one.
    private static let dismissedKey = "ckPendingDismissedIDs"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroup.identifier)
    }

    /// A drained dismissal: which Take, and whether it was the Take's LOCATION
    /// notification (`<uuid>#loc`) rather than its time reminder (2026-07-01).
    /// The distinction matters because a Take can carry BOTH a "when" and a
    /// "where" — dismissing one must not silence the other.
    struct DismissedAction: Equatable {
        let id: UUID
        let isLocation: Bool
    }

    /// The marker a location dismissal is stored under: `<uuid>#loc` — the same
    /// suffix as the geofence notification identifier, so entries stay
    /// human-legible in the defaults. Bare UUID strings are time dismissals
    /// (also the pre-2026-07 wire format, so already-queued entries still drain).
    private static let locationSuffix = "#loc"

    /// Record that the reminder identified by `takeID` (its UUID string) was dismissed,
    /// for the drain to resolve on next unlock. Pass `isLocation: true` when the
    /// dismissed notification was the Take's geofence. Safe to call from a background
    /// notification action while the device is locked.
    static func enqueueDismiss(takeID: String, isLocation: Bool = false) {
        guard let defaults else { return }
        var ids = Set(defaults.stringArray(forKey: dismissedKey) ?? [])
        ids.insert(isLocation ? takeID + locationSuffix : takeID)
        defaults.set(Array(ids), forKey: dismissedKey)
    }

    /// Return every queued dismissal and CLEAR the queue, so each pending action
    /// resolves exactly once. Non-UUID junk is dropped.
    static func drainDismissed() -> [DismissedAction] {
        guard let defaults else { return [] }
        let raw = defaults.stringArray(forKey: dismissedKey) ?? []
        guard !raw.isEmpty else { return [] }
        defaults.removeObject(forKey: dismissedKey)
        return raw.compactMap { entry in
            let isLocation = entry.hasSuffix(locationSuffix)
            let base = isLocation ? String(entry.dropLast(locationSuffix.count)) : entry
            guard let id = UUID(uuidString: base) else { return nil }
            return DismissedAction(id: id, isLocation: isLocation)
        }
    }
}
