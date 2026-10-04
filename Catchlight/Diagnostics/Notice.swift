//
//  Notice.swift
//  Catchlight (iOS app target)
//
//  Every line the app writes to the diagnostics log, as a closed set with a permanent
//  reference code. A line reads `[CCIOS-202] <message>`: the code says exactly which
//  notice it is, whatever language the message is in, so a support export can be read
//  without knowing the user's language. CC = Considus Catchlight, IOS = the platform
//  that wrote it (the Mac app uses CCMOS); the number means the same notice on every
//  platform.
//
//  Rules, because the codes outlive any one release:
//  - A number is never reused or renumbered, even when its notice is deleted.
//    `NoticeCodeTests.testCodesNeverChange` pins every code; a new one is added there.
//  - Two call sites with the same wording still get their own codes: the code says
//    where it happened, not only what was said.
//  - 1xx sync, 2xx storage, 3xx conflicts, 4xx verification, 9xx developer-only
//    breadcrumbs. 950–999 is reserved for lines Catchlight-Core writes itself.
//  - Each `NoticeCode` case carries its English summary as a trailing comment, on one
//    line; `scripts/diagnostics/notice_codes.py` builds the support table from them.
//  - Nothing else writes to the log: `NoticeCodeTests` fails on any call to the
//    category-and-text form, `record(.storage, "…")`, anywhere in the app.
//
//  Which group a notice belongs in (owner, 2026-10-04): a warning that can appear on the
//  main screen is user-facing (1xx–4xx, 2xx for lasting states too) and goes in Notice
//  History, in the device language. Anything that can never appear on the main screen is
//  9xx: export only, English.
//

import Foundation
import CatchlightCore

/// The permanent number of each notice. Raw values must be unique, which the compiler
/// enforces.
enum NoticeCode: Int, CaseIterable {
    // 1xx sync
    case syncPaused = 101                   // Sync paused: the cloud data's signature didn't verify.
    case syncProblem = 102                  // Sync failed and will retry.
    case syncLockHeld = 103                 // Another device holds the sync lock.
    case libraryNotSaving = 104             // Unlocked, but the encrypted library couldn't open; changes aren't saved.
    case cloudFolderStale = 105             // The cloud folder bookmark is stale; the user must re-pick it.
    case cloudFolderUnresolvable = 106      // The cloud folder bookmark can't be resolved; the user must choose a new one.

    // 2xx storage
    case loadFailed = 201                   // Couldn't load the Takes (reload).
    case saveFailed = 202                   // Couldn't save a Take (save).
    case saveInPlaceFailed = 203            // Couldn't save a Take (save in place, e.g. a tick or edit).
    case reorderFailed = 204                // Couldn't reorder the timeline.
    case importFailed = 205                 // Couldn't import one of the notes.
    case deleteFailed = 206                 // Couldn't delete a Take.
    case cleanupFailed = 207                // Auto-delete couldn't remove some finished Takes; will retry.
    case setObieFailed = 208                // Couldn't make a Take the Obie.
    case replaceObieFailed = 209            // Couldn't replace the existing Obie.
    case conflictChoiceFailed = 210         // Couldn't save a conflict choice.
    case conflictResolutionFailed = 211     // Couldn't save a conflict resolution.
    case privacyPhraseMissing = 212         // Banner: this device holds a key but no Privacy phrase; Takes can't be recovered elsewhere.
    case readOnlyLapsed = 213               // Banner: subscription lapsed, the app is read-only.

    // 3xx conflicts
    case conflictsChanged = 301             // N Takes changed on another device.
    case conflictsUnverified = 302          // N cloud copies failed verification and need a choice.

    // 4xx verification
    case takesQuarantined = 401             // N Takes failed verification during pull and were skipped.

    // 9xx developer-only breadcrumbs (export only, English)
    case spotlightReindexSkipped = 901      // Spotlight reindex skipped: locked or store unavailable.
    case spotlightReindexed = 902           // Spotlight reindex: count, exposure level, subscription status.
    case cloudFolderConnected = 903         // Cloud folder connected.
    case cloudFolderDisconnected = 904      // Cloud folder disconnected (local-only).
    case cloudBookmarkReminted = 905        // Cloud folder bookmark re-minted (was stale).
    case lockedCaptureCommitRequested = 906 // Locked capture: commit requested.
    case lockedCaptureBlankDiscarded = 907  // Locked capture: blank, discarded.
    case lockedCaptureDiscarded = 908       // Locked capture discarded.
    case paywallDraftHeld = 909             // Draft held for the paywall (entitlement check failed).
    case paywallDraftDropped = 910          // Paywall draft dropped (not entitled); typed text discarded.
    case paywallDraftSaved = 911            // Paywall draft saved (now entitled).
    case takeSaved = 912                    // Take saved.
    case timelineReordered = 913            // Timeline reordered.
    case takeDeleted = 914                  // Take deleted.
    case backgroundSyncNotScheduled = 915   // Background sync scheduling failed, with the system error.
    case reminderNotScheduled = 916         // Reminder scheduling failed; the OS will not deliver it.
    case notificationPermission = 917       // Notification permission changed, with the new state.
    case reminderPastDated = 918            // Reminder refused: past-dated, would never fire.
    case takesHeldBack = 919                // N Takes not re-uploaded: device away too long to rule out deletion elsewhere.
    case watermarkPrepareFailed = 920       // Sync watermark write failed (prepare).
    case watermarkStepFailed = 921          // Sync watermark write failed (step).
    case libraryOpenFailed = 922            // Encrypted library failed to open, with the error (the user sees 104).
}

/// One line for the diagnostics log. Build it, then `DiagnosticsLog.shared.record(_:)`.
enum Notice: Equatable {
    case syncPaused, syncProblem, syncLockHeld, libraryNotSaving
    case cloudFolderStale, cloudFolderUnresolvable
    case takesHeldBack(Int)

    case loadFailed, saveFailed, saveInPlaceFailed, reorderFailed, importFailed, deleteFailed
    case cleanupFailed, setObieFailed, replaceObieFailed
    case conflictChoiceFailed, conflictResolutionFailed
    case privacyPhraseMissing, readOnlyLapsed

    case conflictsChanged(Int), conflictsUnverified(Int)
    case takesQuarantined(Int)

    case spotlightReindexSkipped
    case spotlightReindexed(count: Int, exposure: String, status: String)
    case cloudFolderConnected, cloudFolderDisconnected, cloudBookmarkReminted
    case lockedCaptureCommitRequested, lockedCaptureBlankDiscarded, lockedCaptureDiscarded
    case paywallDraftHeld, paywallDraftDropped, paywallDraftSaved
    case takeSaved, timelineReordered, takeDeleted
    case backgroundSyncNotScheduled(domain: String, code: Int)
    case reminderNotScheduled(domain: String, code: Int)
    case notificationPermission(state: String, remindersWillFire: Bool)
    case reminderPastDated
    case watermarkPrepareFailed, watermarkStepFailed
    case libraryOpenFailed(String)

    /// The platform part of the reference. The Mac app uses "CCMOS".
    static let platform = "CCIOS"

    var code: NoticeCode {
        switch self {
        case .syncPaused: return .syncPaused
        case .syncProblem: return .syncProblem
        case .syncLockHeld: return .syncLockHeld
        case .libraryNotSaving: return .libraryNotSaving
        case .cloudFolderStale: return .cloudFolderStale
        case .cloudFolderUnresolvable: return .cloudFolderUnresolvable
        case .takesHeldBack: return .takesHeldBack
        case .loadFailed: return .loadFailed
        case .saveFailed: return .saveFailed
        case .saveInPlaceFailed: return .saveInPlaceFailed
        case .reorderFailed: return .reorderFailed
        case .importFailed: return .importFailed
        case .deleteFailed: return .deleteFailed
        case .cleanupFailed: return .cleanupFailed
        case .setObieFailed: return .setObieFailed
        case .replaceObieFailed: return .replaceObieFailed
        case .conflictChoiceFailed: return .conflictChoiceFailed
        case .conflictResolutionFailed: return .conflictResolutionFailed
        case .privacyPhraseMissing: return .privacyPhraseMissing
        case .readOnlyLapsed: return .readOnlyLapsed
        case .watermarkPrepareFailed: return .watermarkPrepareFailed
        case .watermarkStepFailed: return .watermarkStepFailed
        case .libraryOpenFailed: return .libraryOpenFailed
        case .conflictsChanged: return .conflictsChanged
        case .conflictsUnverified: return .conflictsUnverified
        case .takesQuarantined: return .takesQuarantined
        case .spotlightReindexSkipped: return .spotlightReindexSkipped
        case .spotlightReindexed: return .spotlightReindexed
        case .cloudFolderConnected: return .cloudFolderConnected
        case .cloudFolderDisconnected: return .cloudFolderDisconnected
        case .cloudBookmarkReminted: return .cloudBookmarkReminted
        case .lockedCaptureCommitRequested: return .lockedCaptureCommitRequested
        case .lockedCaptureBlankDiscarded: return .lockedCaptureBlankDiscarded
        case .lockedCaptureDiscarded: return .lockedCaptureDiscarded
        case .paywallDraftHeld: return .paywallDraftHeld
        case .paywallDraftDropped: return .paywallDraftDropped
        case .paywallDraftSaved: return .paywallDraftSaved
        case .takeSaved: return .takeSaved
        case .timelineReordered: return .timelineReordered
        case .takeDeleted: return .takeDeleted
        case .backgroundSyncNotScheduled: return .backgroundSyncNotScheduled
        case .reminderNotScheduled: return .reminderNotScheduled
        case .notificationPermission: return .notificationPermission
        case .reminderPastDated: return .reminderPastDated
        }
    }

    var category: DiagnosticCategory {
        switch code.rawValue {
        case 100..<200: return .sync
        case 200..<300: return .storage
        case 300..<400: return .conflict
        case 400..<500: return .quarantine
        default: return .lifecycle
        }
    }

    /// `CCIOS-202`.
    var reference: String { "\(Self.platform)-\(code.rawValue)" }

    /// What the log stores: the reference, then the message.
    var logLine: String { "[\(reference)] \(message)" }

    /// The message itself, without the reference: what a strip or Notice History shows.
    var message: String {
        switch self {
        case .syncPaused:
            return String(localized: "Sync paused. Your cloud data looks unexpected. No changes were made locally.")
        case .syncProblem:
            return String(localized: "Sync encountered a problem and will retry.")
        case .syncLockHeld:
            return String(localized: "Another device is syncing. Catchlight will retry automatically.")
        case .libraryNotSaving:
            return String(localized: "Your encrypted library couldn't be opened, so changes aren't being saved to this device yet. Please restart Catchlight.")
        case .cloudFolderStale:
            return String(localized: "Your cloud folder is no longer available. Open Settings → Cloud Storage to re-pick it.")
        case .cloudFolderUnresolvable:
            return String(localized: "Your cloud folder couldn't be opened. Open Settings → Cloud Storage to choose a new one.")
        case .loadFailed:
            return String(localized: "Couldn't load your Takes.")
        case .saveFailed, .saveInPlaceFailed:
            return String(localized: "Couldn't save that Take.")
        case .reorderFailed:
            return String(localized: "Couldn't reorder your Takes.")
        case .importFailed:
            return String(localized: "Couldn't import one of the notes.")
        case .deleteFailed:
            return String(localized: "Couldn't delete that Take.")
        case .cleanupFailed:
            return String(localized: "Some finished Takes couldn't be cleaned up. They'll be retried.")
        case .setObieFailed, .replaceObieFailed:
            return String(localized: "Couldn't set Obie.")
        case .conflictChoiceFailed:
            return String(localized: "Couldn't save that choice. Please try again.")
        case .conflictResolutionFailed:
            return String(localized: "Couldn't save that resolution. Please try again.")
        case .privacyPhraseMissing:
            return String(localized: "No privacy phrase on this device. Export now, then Settings > Start over.")
        case .readOnlyLapsed:
            return String(localized: "Read-only. Your data is still yours.")
        case .conflictsChanged(let n):
            return String(localized: "\(n) Takes changed on another device.")
        case .conflictsUnverified(let n):
            return String(localized: "\(n) Takes couldn't be verified and need a choice.")
        case .takesQuarantined(let n):
            return String(localized: "\(n) Takes couldn't be verified and were skipped.")

        // Developer-only, English by design: export only, never shown in Notice History.
        case .spotlightReindexSkipped:
            return "Spotlight reindex skipped (locked or store unavailable)"
        case let .spotlightReindexed(count, exposure, status):
            return "Spotlight reindex: \(count) takes at exposure=\(exposure), status=\(status)"
        case .cloudFolderConnected:
            return "Cloud folder connected"
        case .cloudFolderDisconnected:
            return "Cloud folder disconnected (local-only)"
        case .cloudBookmarkReminted:
            return "Cloud folder bookmark re-minted (was stale)"
        case .lockedCaptureCommitRequested:
            return "Locked capture: commit requested"
        case .lockedCaptureBlankDiscarded:
            return "Locked capture: blank, discarded"
        case .lockedCaptureDiscarded:
            return "Locked capture discarded"
        case .paywallDraftHeld:
            return "Draft held for paywall (entitlement check failed)"
        case .paywallDraftDropped:
            return "Paywall draft DROPPED (not entitled) — typed text discarded"
        case .paywallDraftSaved:
            return "Paywall draft saved (now entitled)"
        case .takeSaved:
            return "Take saved"
        case .timelineReordered:
            return "Timeline reordered"
        case .takeDeleted:
            return "Take deleted"
        case let .backgroundSyncNotScheduled(domain, code):
            return "Background sync scheduling FAILED — BG refresh will not run (\(domain) \(code))"
        case let .reminderNotScheduled(domain, code):
            return "Reminder scheduling FAILED — the OS will not deliver it (\(domain) \(code))"
        case let .notificationPermission(state, remindersWillFire):
            return "Notification permission: \(state)\(remindersWillFire ? "" : " — reminders will NOT fire")"
        case .reminderPastDated:
            return "Reminder refused — past-dated, will never fire"
        case .takesHeldBack(let n):
            return "Takes not re-uploaded: \(n). This device was away too long to rule out deletion elsewhere; editing a Take syncs it again."
        case .watermarkPrepareFailed:
            return "Sync watermark write failed (prepare)."
        case .watermarkStepFailed:
            return "Sync watermark write failed (step)."
        case .libraryOpenFailed(let detail):
            return "Encrypted library failed to open: \(detail)"
        }
    }

    /// The message with any leading `[CC…-NNN] ` reference removed, for showing a stored
    /// log line to the user. Lines recorded before codes existed pass through unchanged.
    static func displayText(of logLine: String) -> String {
        guard logLine.hasPrefix("[CC"), let close = logLine.firstIndex(of: "]") else { return logLine }
        let rest = logLine[logLine.index(after: close)...]
        return rest.hasPrefix(" ") ? String(rest.dropFirst()) : String(rest)
    }
}

/// A lasting condition shown as a main-screen banner is recorded once when it begins, not
/// on every launch or redraw. The state is remembered across launches; when the condition
/// ends the memory clears, so a later recurrence is recorded again.
enum NoticeOnset {
    static func update(_ notice: Notice, active: Bool,
                       defaults: UserDefaults = .standard, log: DiagnosticsLog = .shared) {
        let key = "catchlight.diagnostics.onset.\(notice.code.rawValue)"
        guard active else { defaults.removeObject(forKey: key); return }
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        log.record(notice)
    }
}

extension DiagnosticsLog {
    /// The only way the app writes to the log.
    func record(_ notice: Notice) {
        record(notice.category, notice.logLine)
    }
}
