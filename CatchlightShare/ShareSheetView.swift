//
//  ShareSheetView.swift
//  CatchlightShare
//
//  The share sheet's UI, split out of `ShareViewController` when it grew past a thumbnail and
//  two buttons (owner 2026-08-11, device round 3).
//
//  WHAT THE OWNER ASKED FOR, AND WHY EACH BIT IS HERE:
//    • TALLER — the first cut was a small card floating on dimmed host app, wasting most of the
//      screen. It now fills it.
//    • PAPER, NOT GREY — that grey was the host app showing through a dim layer. The sheet is now
//      opaque `ckBackground`, which is Paper in daylight and Ink at night: asking for "Paper"
//      means the brand background, and hardcoding the light value would break dark mode.
//    • SHAPING — Obie / Important / Task, the same three the Focus ring offers, so a share is a
//      real capture rather than a dump. They ride the queued payload, so nothing new is needed
//      downstream beyond honouring them.
//    • RICH PREVIEW — owner-authorised, see the note on `loadPreview` below. It is the only part
//      of this screen that touches the network, and that is a privacy decision, not a detail.
//

import SwiftUI
import LinkPresentation
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
    @State private var isObie = false
    @State private var isImportant = false
    @State private var isTask = false
    /// Rich link metadata, once fetched. nil while loading or when there is no link.
    @State private var linkTitle: String?
    @State private var linkImage: UIImage?

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
            if case .ready(let items) = phase { await loadPreview(for: items) }
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
            shapingRow
        }
    }

    /// The real content, and a page title + image when we have one.
    private func preview(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let linkImage {
                Image(uiImage: linkImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if let linkTitle {
                Text(linkTitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.ckTextPrimary)
                    .lineLimit(3)
            }
            Text(items.joined(separator: "\n"))
                .font(.system(size: 14))
                .foregroundStyle(linkTitle == nil ? Color.ckTextPrimary : Color.ckTextSecondary)
                .lineLimit(linkTitle == nil ? 8 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.ckSurface)
        )
    }

    private var noteField: some View {
        TextField("Add a note (optional)", text: $note, axis: .vertical)
            .font(.system(size: 16))
            .lineLimit(4...8)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.ckTextSecondary.opacity(0.28), lineWidth: 1)
            )
    }

    /// The same three shapes the Focus ring offers in the app.
    private var shapingRow: some View {
        HStack(spacing: 10) {
            shapeChip("Obie", isOn: $isObie)
            shapeChip("Important", isOn: $isImportant)
            shapeChip("Task", isOn: $isTask)
        }
    }

    private func shapeChip(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(label)
                .font(.system(size: 14, weight: isOn.wrappedValue ? .semibold : .regular))
                .foregroundStyle(isOn.wrappedValue ? Color.ckOnAccent : Color.ckTextSecondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(
                    Capsule().fill(isOn.wrappedValue ? Color.ckAccent : Color.clear)
                )
                .overlay(
                    Capsule().stroke(isOn.wrappedValue ? Color.clear
                                                       : Color.ckTextSecondary.opacity(0.28),
                                     lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn.wrappedValue ? [.isButton, .isSelected] : .isButton)
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

    // MARK: - Rich preview

    /// Fetch the shared link's title and image.
    ///
    /// ⚠️ THE ONLY NETWORK REQUEST CATCHLIGHT MAKES. `LPMetadataProvider` contacts the shared URL
    /// directly, so the site sees a request (and therefore an IP) from this device.
    ///
    /// Owner-authorised 2026-08-11, on the reasoning that the user is sharing content they are
    /// already looking at. Worth keeping in view: that holds for the common case, but NOT for
    /// forwarding a link someone sent you and never opened — there, this contacts a site you
    /// hadn't. It fetches metadata only, sends nothing about the user, and the result is not
    /// persisted; only the text is queued. The privacy policy says so explicitly rather than
    /// leaving it to be discovered.
    ///
    /// Fails silently and often — many sites block scrapers — so the sheet must look right with
    /// no title and no image. It always does: the plain text preview is the base state and this
    /// only ever adds to it.
    private func loadPreview(for items: [String]) async {
        guard let url = items.compactMap(Self.firstURL(in:)).first else { return }
        guard let metadata = try? await LPMetadataProvider().startFetchingMetadata(for: url) else { return }
        linkTitle = metadata.title
        guard let provider = metadata.imageProvider,
              let image = try? await provider.loadUIImage() else { return }
        linkImage = image
    }

    /// First http(s) URL in a string, or nil.
    static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range)
            .compactMap(\.url)
            .first { $0.scheme == "http" || $0.scheme == "https" }
    }

    /// Note first, shared content below — a reason for keeping it, then the thing itself.
    private func save(_ items: [String]) {
        let body = ([note.trimmingCharacters(in: .whitespacesAndNewlines)] + items)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        phase = .saved
        onSave(CaptureRouting.SharedItem(text: body,
                                         isObie: isObie,
                                         isImportant: isImportant,
                                         isTask: isTask))
    }
}

private extension NSItemProvider {
    /// `loadObject` as async, returning nil rather than throwing on the many ways a remote image
    /// can fail to arrive.
    func loadUIImage() async throws -> UIImage? {
        guard canLoadObject(ofClass: UIImage.self) else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            loadObject(ofClass: UIImage.self) { object, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: object as? UIImage) }
            }
        }
    }
}
