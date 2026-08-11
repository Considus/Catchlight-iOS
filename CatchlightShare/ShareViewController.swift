//
//  ShareViewController.swift
//  CatchlightShare — the Share Extension (owner 2026-08-11)
//
//  "Share to Catchlight" from any app. Deferred to v1.1 when the widgets landed (project.yml's
//  closing note); brought into v1.0 on owner testing feedback — Catchlight simply never appeared
//  in the share sheet, because no extension target existed at all.
//
//  IT QUEUES, IT DOES NOT SAVE. The encrypted store needs the master key, which is
//  `.userPresence`-gated and only materialises in the foreground, unlocked app — the same
//  zero-knowledge wall that stops the widgets writing. So the extension appends to
//  `CaptureRouting`'s shared queue in the App Group and the app commits on next open. That is
//  also why it never reads existing Takes: it has no key, and no business holding one.
//
//  A QUEUE rather than the widgets' single pending slot: sharing three articles before opening
//  the app is ordinary behaviour, and last-wins would have silently eaten the first two.
//
//  The system compose sheet (`SLComposeServiceViewController`) carries the UI. Anything the user
//  types there becomes the FIRST LINE of the Take — a note about why they kept it — with the
//  shared text or link below. That's the whole editing surface offered here on purpose: a richer
//  one would be a second editor that cannot see the store it's writing to.
//

import UIKit
import UniformTypeIdentifiers
import Social
import CatchlightCore

final class ShareViewController: SLComposeServiceViewController {

    /// Post is always available: a share with no typed note is the common case, and the
    /// attachment alone is worth keeping.
    override func isContentValid() -> Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Catchlight"
        placeholder = "Add a note (optional)"
    }

    override func didSelectPost() {
        // Read the typed note on the main actor BEFORE hopping off it — `contentText` is UI state.
        let note = (contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let context = extensionContext

        Task {
            let shared = await extractSharedText()
            let body = ([note] + shared)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            CaptureRouting.enqueueShared(body)
            // Always complete, even when nothing could be extracted: leaving the sheet open on an
            // unsupported attachment strands the user inside another app's UI.
            context?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    // MARK: - Extraction

    /// Pull plain text and URLs out of every attachment on every input item.
    ///
    /// Order matters: TEXT is preferred over URL on the same attachment, because a share from a
    /// browser usually carries both and the text is the selection the user actually highlighted.
    /// A URL-only share (the Share button rather than a text selection) falls through to the link.
    private func extractSharedText() async -> [String] {
        guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem] else { return [] }
        var out: [String] = []

        for item in inputItems {
            for provider in item.attachments ?? [] {
                if let text = await load(provider, as: .plainText) {
                    out.append(text)
                } else if let url = await load(provider, as: .url) {
                    out.append(url)
                }
            }
            // Some apps carry the user-visible title only on the item itself (a URL attachment
            // with the page title alongside). Keep it when it adds something the attachments
            // didn't already say, so a shared link lands with its title rather than bare.
            if let title = item.attributedContentText?.string
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty,
               !out.contains(where: { $0.contains(title) }) {
                out.append(title)
            }
        }
        return out
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Load one attachment as `type`, or nil if it doesn't carry that representation.
    /// `loadItem` hands back a String, a URL or Data depending on the provider, so all three are
    /// accepted rather than assuming one.
    private func load(_ provider: NSItemProvider, as type: UTType) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier) { value, _ in
                switch value {
                case let string as String:  continuation.resume(returning: string)
                case let url as URL:        continuation.resume(returning: url.absoluteString)
                case let data as Data:      continuation.resume(returning: String(data: data, encoding: .utf8))
                default:                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
