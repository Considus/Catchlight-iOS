//
//  ShareViewController.swift
//  CatchlightShare — the Share Extension (owner 2026-08-11)
//
//  "Share to Catchlight" from any app. Deferred to v1.1 when the widgets landed; brought into
//  v1.0 on owner testing feedback, because Catchlight simply never appeared in the share sheet —
//  no such target existed.
//
//  CUSTOM UI, replacing `SLComposeServiceViewController` (owner, device round 2). Apple's compose
//  sheet owns three things it does not let you change, and the owner hit all three within a minute
//  of testing: the action button says "Post" (wrong verb — nothing is being published), it draws a
//  grey placeholder square for an attachment it cannot preview, and it dismisses with no
//  confirmation, so a shared link looked like it had gone nowhere. This screen fixes all three,
//  and it is the same surface we would extend if the extension ever writes the store directly.
//
//  IT QUEUES, IT DOES NOT SAVE. The encrypted store needs the master key, which is Face-ID-gated
//  and only exists inside the foreground, unlocked app — the same wall that stops the widgets
//  writing Takes. So this appends to `CaptureRouting`'s shared queue and the app commits on next
//  open. A QUEUE rather than the widgets' single pending slot: sharing three things before opening
//  the app is ordinary, and last-wins would silently eat the first two.
//
//  NOTHING IS EVER SILENTLY DROPPED. If no text or URL can be extracted, the screen SAYS SO rather
//  than closing as if it had worked — the owner hit that too (a share that "opened the editor and
//  closed again", which was this path, not the site misbehaving).
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers
import CatchlightCore

final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let root = ShareSheetView(
            load: { [weak self] in await self?.extractSharedText() ?? [] },
            onSave: { [weak self] body in
                CaptureRouting.enqueueShared(body)
                self?.finish()
            },
            onCancel: { [weak self] in self?.finish() }
        )
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    // MARK: - Extraction

    /// Pull plain text and URLs out of every attachment on every input item.
    ///
    /// TEXT is preferred over URL on the same attachment: a share from a browser usually carries
    /// both, and the text is the selection the user actually highlighted. A URL-only share (the
    /// Share button rather than a text selection) falls through to the link.
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

// MARK: - The sheet

private struct ShareSheetView: View {
    let load: () async -> [String]
    let onSave: (String) -> Void
    let onCancel: () -> Void

    private enum Phase: Equatable {
        case loading
        case ready([String])
        /// Nothing usable in the share. Said out loud rather than closing silently.
        case nothingToSave
        case saved
    }

    @State private var phase: Phase = .loading
    @State private var note: String = ""
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            card
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.28).ignoresSafeArea())
        .task {
            let items = await load()
            phase = items.isEmpty ? .nothingToSave : .ready(items)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(phase == .saved ? "Saved to Catchlight" : "Save to Catchlight")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.ckTextPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            switch phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)

            case .nothingToSave:
                Text("There's nothing here Catchlight can keep. It takes text, links and web pages, not images or files.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ckTextSecondary)
                Button("Close", action: onCancel)
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)

            case .saved:
                Text("It'll be waiting on your timeline next time you open the app.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ckTextSecondary)

            case .ready(let items):
                // The REAL content, not a placeholder thumbnail. This is what the grey square
                // should always have been.
                Text(items.joined(separator: "\n"))
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ckTextPrimary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.ckSurface)
                    )

                TextField("Add a note (optional)", text: $note, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...3)
                    .focused($noteFocused)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.ckTextSecondary.opacity(0.3), lineWidth: 1)
                    )

                HStack {
                    Button("Cancel", action: onCancel)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.ckTextSecondary)
                    Spacer()
                    // "Save", not "Post". Nothing is being published.
                    Button("Save") { save(items) }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.ckAccent)
                }
                .padding(.top, 2)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.ckBackground)
        )
    }

    /// Note first, shared content below — a reason for keeping it, then the thing itself.
    private func save(_ items: [String]) {
        let body = ([note.trimmingCharacters(in: .whitespacesAndNewlines)] + items)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        phase = .saved
        onSave(body)
    }
}
