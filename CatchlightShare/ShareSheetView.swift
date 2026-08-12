//
//  ShareSheetView.swift
//  CatchlightShare
//
//  The share sheet's UI, split out of `ShareViewController` when it grew past a thumbnail and
//  two buttons (owner 2026-08-11, device round 3).
//
//  WHAT THE OWNER ASKED FOR:
//    • TALLER — the first cut was a small card floating on dimmed host app, wasting most of the
//      screen. It now fills it.
//    • PAPER, NOT GREY — that grey was the host app showing through a dim layer. The sheet is now
//      opaque `ckBackground`, which is Paper in daylight and Ink at night: asking for "Paper"
//      means the brand background, and hardcoding the light value would break dark mode.
//    • A GENEROUS NOTE FIELD — the point of the screen is the thought you add, not the link.
//
//  TRIED AND REMOVED (device round 4) — recorded so neither gets re-proposed:
//    • SHAPING PILLS (Obie / Important / Task). Built as asked, then cut on sight: "too
//      off-brand". Shaping stays in the app, where the Focus ring does it properly.
//    • RICH LINK PREVIEWS (title + image via LinkPresentation). Also built as asked, also cut.
//      Worth knowing what that bought back: it was the ONLY network request Catchlight made, so
//      removing it returns the app to contacting nobody at all, and the privacy-policy line
//      added to disclose it was reverted with it. A privacy product that never phones out is
//      easier to explain than one that phones out once, for decoration.
//

import SwiftUI
import CatchlightCore

struct ShareSheetView: View {
    let load: () async -> [String]
    let onSave: (CaptureRouting.SharedItem) -> Void
    let onCancel: () -> Void

    private enum Phase: Equatable {
        case loading
        case ready([String])
        /// Nothing usable in the share. Said out loud rather than closing silently — the owner
        /// hit the silent version as "opened the editor and closed again".
        case nothingToSave
        case saved
    }

    @State private var phase: Phase = .loading
    @State private var note: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            content
            Spacer(minLength: 0)
            if case .ready(let items) = phase { actions(items) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Opaque brand background, edge to edge — no dimmed host app behind it.
        .background(Color.ckBackground.ignoresSafeArea())
        .task {
            let items = await load()
            phase = items.isEmpty ? .nothingToSave : .ready(items)
        }
    }

    private var header: some View {
        Text(phase == .saved ? "Saved to Catchlight" : "Save to Catchlight")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Color.ckTextPrimary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)

        case .nothingToSave:
            VStack(alignment: .leading, spacing: 16) {
                Text("There's nothing here Catchlight can keep.")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.ckTextPrimary)
                Text("It takes text, links and web pages, not images or files.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ckTextSecondary)
                Button("Close", action: onCancel)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.ckAccent)
            }

        case .saved:
            Text("It'll be waiting on your timeline next time you open the app.")
                .font(.system(size: 16))
                .foregroundStyle(Color.ckTextSecondary)

        case .ready(let items):
            preview(items)
            noteField
        }
    }

    /// The real content — the text or link being shared. No page title, no thumbnail: see the
    /// removal note in the header.
    private func preview(_ items: [String]) -> some View {
        Text(items.joined(separator: "\n"))
            .font(.system(size: 15))
            .foregroundStyle(Color.ckTextPrimary)
            .lineLimit(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.ckSurface)
            )
    }

    private var noteField: some View {
        TextField("Add a note (optional)", text: $note, axis: .vertical)
            .font(.system(size: 16))
            // ~25% taller than the first cut (owner device round 4). This is where the value of
            // the screen is: the thought you add, not the link you already have.
            .lineLimit(5...10)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.ckTextSecondary.opacity(0.28), lineWidth: 1)
            )
    }

    private func actions(_ items: [String]) -> some View {
        HStack {
            Button("Cancel", action: onCancel)
                .font(.system(size: 17))
                .foregroundStyle(Color.ckTextSecondary)
            Spacer()
            // "Save", not "Post" — nothing is being published.
            Button("Save") { save(items) }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ckAccent)
        }
    }

    /// Note first, shared content below — a reason for keeping it, then the thing itself.
    private func save(_ items: [String]) {
        let body = ([note.trimmingCharacters(in: .whitespacesAndNewlines)] + items)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        phase = .saved
        onSave(CaptureRouting.SharedItem(text: body))
    }
}
