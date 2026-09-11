//
//  ExportCoordinator.swift
//  Catchlight (iOS app target) — Task 6.22
//
//  iOS glue between `CatchlightCore.TakeExporter` (pure, testable) and the
//  system share sheet. Pulls every Take through the live store, writes the
//  Markdown payload to a temporary file under the app sandbox, and presents
//  a `UIActivityViewController` so the user can route the file to Files /
//  AirDrop / Mail / Notes / whatever they have installed.
//
//  Export is subscription-INDEPENDENT — never gate it on `subscriptionStatus`.
//  Decisions doc §5 is explicit: "your data is yours, always" only holds if
//  export remains available in lapsed read-only mode, and the lapse banner
//  surfaces export prominently alongside the resubscribe prompt.
//

import Foundation
import UIKit
import SwiftUI
import CatchlightCore

@MainActor
enum ExportCoordinator {

    /// Build the `.md` payload from the supplied store, write it to a temp
    /// file, and present the share sheet bound to the active scene.
    ///
    /// Returns immediately; presentation is asynchronous. Logging is intentionally
    /// absent — Take content is sensitive and must never reach the system log.
    static func presentShareSheet(takes: [Take]) {
        let payload = TakeExporter.export(takes)
        guard let fileURL = writeTempFile(text: payload) else { return }

        let activityVC = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        // Empty array — let iOS decide. The decisions doc explicitly asks for
        // AirDrop, Files, Notes, Mail, etc. all to be available.
        activityVC.excludedActivityTypes = []

        // After the sheet completes (any branch), delete the temp file so the
        // exported plaintext doesn't linger in the sandbox.
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: fileURL)
        }

        present(activityVC)
    }

    /// Share the content-free diagnostics text (D-085) as a `.txt` via the system share sheet.
    /// A user-initiated export — the placeholder for the future web Report-an-issue form, which
    /// will reuse this producer. The log holds no Take content, so no special protection class.
    static func presentDiagnostics(_ text: String) {
        // Lowercase "catchlight-" prefix (2026-07-02) so `sweepStaleExports`
        // (which matches TakeExporter.isExportFilename) collects this file too
        // if a crash strands it — the previous capital-C name escaped the sweep
        // forever. Content-free log, so the exposure was cosmetic, but tmp
        // hygiene should not depend on luck.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("catchlight-diagnostics.txt")
        guard (try? Data(text.utf8).write(to: url, options: [.atomic])) != nil else { return }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
        }
        present(activityVC)
    }

    // MARK: - File staging

    private static func writeTempFile(text: String) -> URL? {
        let filename = TakeExporter.suggestedFilename()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            // `.completeFileProtectionUnlessOpen`: the file holds the user's
            // ENTIRE decrypted corpus, so it gets the strongest protection class
            // compatible with the share sheet reading it while the device is
            // unlocked. `Data(text.utf8)` cannot fail (the previous
            // `data(using:)?` optional chain could silently skip the write and
            // still return the URL).
            try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            return url
        } catch {
            return nil
        }
    }

    /// Delete any stale export files left in tmp by a crash or a share sheet
    /// whose completion handler never ran. Call once at app launch. Without
    /// this, the cleanup in `completionWithItemsHandler` was the ONLY thing
    /// standing between the full decrypted corpus and an indefinite lifetime in
    /// the sandbox tmp directory (iOS purges tmp only opportunistically).
    static func sweepStaleExports() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        guard let items = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return }
        for item in items where TakeExporter.isExportFilename(item.lastPathComponent) {
            try? fm.removeItem(at: item)
        }
    }

    // MARK: - Presenter lookup

    /// Walk the scene's view-controller stack down to the foremost presented
    /// controller; required because Settings / sheets / overlays can each be
    /// the current presenter depending on the entry point (Settings row vs.
    /// lapse banner).
    /// Present on the top-most controller, waiting if one is still going away.
    ///
    /// 🚨 A share sheet offered from INSIDE a `confirmationDialog` silently did
    /// nothing (owner 2026-09-11: Settings > Start over > "Export Takes"). The
    /// dialog is still dismissing when its own button action runs, so
    /// `topViewController()` returns the dismissing `UIAlertController`, and
    /// `present` on a controller that is being dismissed is a NO-OP — no sheet,
    /// no error, no log. Nothing to see, which is why it reads as a dead button.
    ///
    /// 🚨 It was on BOTH of the export off-ramps and neither of the ordinary
    /// ones: Start over's, and the missing-phrase banner's "Export anyway"
    /// (`DailiesView`). The five plain-button callers were fine, because no
    /// dialog was closing over them. **The fault sat on exactly the two paths
    /// whose whole job is to save the user's data before it becomes
    /// unreachable** — and on Start over, a user who reads "nothing happened"
    /// as "nothing to export" is one tap from an irreversible wipe.
    ///
    /// ⚠️ It is a RACE, not a hard failure, and the owner established that
    /// himself: after exporting once from the ordinary Settings row, Start over's
    /// export then worked. A first `UIActivityViewController` has to enumerate
    /// share extensions and is slow to appear; once that list is warm it presents
    /// quickly enough to win. So the outcome depends on timing, which is worse
    /// than a clean failure on this path — a user who taps Export, sees nothing,
    /// and concludes there is nothing to export is one tap from an irreversible
    /// wipe.
    ///
    /// Fixed HERE rather than at the two call sites, so a future dialog-invoked
    /// export cannot reintroduce it. Retries on the main queue while the top
    /// controller is mid-dismissal, then gives up quietly rather than spinning.
    /// That makes the outcome deterministic whichever way the race would have
    /// gone.
    private static func present(_ vc: UIViewController, attemptsLeft: Int = 8) {
        guard let presenter = topViewController(), !presenter.isBeingDismissed else {
            guard attemptsLeft > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                present(vc, attemptsLeft: attemptsLeft - 1)
            }
            return
        }

        // iPad popover anchor — without this, UIActivityViewController crashes
        // on iPad. Pinned to the centre of the presenter's view as a safe
        // fallback when the call site isn't a button.
        if let popover = vc.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.midY,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        presenter.present(vc, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
