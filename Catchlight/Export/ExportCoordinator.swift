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
    static func presentShareSheet(takes: [Take], format: TakeExporter.Format = .markdown) {
        let payload = TakeExporter.export(takes, format: format)
        guard let fileURL = writeTempFile(text: payload, format: format) else { return }

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

        guard let presenter = topViewController() else { return }

        // iPad popover anchor — without this, UIActivityViewController crashes
        // on iPad. Pinned to the centre of the presenter's view as a safe
        // fallback when the call site isn't a button.
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.midY,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        presenter.present(activityVC, animated: true)
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
        guard let presenter = topViewController() else { return }
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(activityVC, animated: true)
    }

    // MARK: - File staging

    private static func writeTempFile(text: String, format: TakeExporter.Format) -> URL? {
        let filename = TakeExporter.suggestedFilename(format: format)
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
