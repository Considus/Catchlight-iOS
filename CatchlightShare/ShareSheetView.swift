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
//  TRIED AND REMOVED (device round 4):
//    • SHAPING PILLS (Obie / Important / Task). Built as asked, then cut on sight: "too
//      off-brand". Shaping stays in the app, where the Focus ring does it properly.
//
//  RICH LINK PREVIEWS are IN, and were briefly removed by mistake — "no rich text/image on URLs"
//  was a bug report, read as a removal request. Restored with the actual fault fixed; see
//  `loadPreview`.
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
    /// Page title + image for a shared link, once fetched. nil while loading, or when the page
    /// publishes none — which is common and must look normal, not broken.
    @State private var linkTitle: String?
    @State private var linkImage: UIImage?
    /// STRONG reference to the in-flight provider. See `loadPreview`.
    @State private var metadataProvider: LPMetadataProvider?

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
        }
    }

    /// The shared content, with the page's title and picture when it publishes them.
    private func preview(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let linkImage {
                Image(uiImage: linkImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 150)
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
                // The link recedes once there is a title — the title is the useful part.
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

    // MARK: - Rich preview

    /// Fetch the shared link's title and image.
    ///
    /// ⚠️ THE ONLY NETWORK REQUEST CATCHLIGHT MAKES. `LPMetadataProvider` contacts the shared URL
    /// directly, so that site sees a request from this device. Owner-authorised 2026-08-11 on the
    /// reasoning that the user is sharing content they are already looking at — true for the
    /// common case, but NOT for forwarding a link you never opened, which is why the privacy
    /// policy states it outright. Metadata only, nothing about the user is sent, and none of it
    /// is persisted: only the text is queued.
    ///
    /// THE BUG THAT MADE THIS LOOK DEAD: the provider was created as a throwaway temporary
    /// (`LPMetadataProvider().startFetchingMetadata(...)`), so nothing owned it for the life of
    /// the request and the fetch could be cancelled before returning — silently, since a failure
    /// here is indistinguishable from a page with no metadata. It is now held in @State for the
    /// duration. Measured against the real API first: a YouTube VIDEO returns a title and image,
    /// while the logged-in subscriptions FEED the owner tested with returns "- YouTube" and no
    /// image at all, so part of the original report was the page, not the code.
    ///
    /// Timeout cut to 10s from the 30s default: this sits in front of someone mid-share, and a
    /// preview that arrives after they have tapped Save helps nobody.
    private func loadPreview(for items: [String]) async {
        guard let url = items.compactMap(Self.firstURL(in:)).first else { return }
        let provider = LPMetadataProvider()
        provider.timeout = 10
        metadataProvider = provider
        defer { metadataProvider = nil }

        guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return }
        // A blank or whitespace-only title is worse than none — it just shifts the layout.
        if let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            linkTitle = title
        }
        guard let imageProvider = metadata.imageProvider,
              let image = try? await imageProvider.loadUIImage() else { return }
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
