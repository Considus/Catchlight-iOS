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

    /// Record that the reminder identified by `takeID` (its UUID string) was dismissed,
    /// for the drain to resolve on next unlock. Safe to call from a background
    /// notification action while the device is locked.
    static func enqueueDismiss(takeID: String) {
        guard let defaults else { return }
        var ids = Set(defaults.stringArray(forKey: dismissedKey) ?? [])
        ids.insert(takeID)
        defaults.set(Array(ids), forKey: dismissedKey)
    }

    /// Return every queued dismissed Take id and CLEAR the queue, so each pending action
    /// resolves exactly once. Returns parsed UUIDs (non-UUID junk is dropped).
    static func drainDismissedIDs() -> [UUID] {
        guard let defaults else { return [] }
        let raw = defaults.stringArray(forKey: dismissedKey) ?? []
        guard !raw.isEmpty else { return [] }
        defaults.removeObject(forKey: dismissedKey)
        return raw.compactMap(UUID.init(uuidString:))
    }
}
