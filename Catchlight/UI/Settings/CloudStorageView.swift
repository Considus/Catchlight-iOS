//
//  CloudStorageView.swift
//  Catchlight (iOS app target) — Task 3.12
//
//  Settings → Sync → Cloud Storage.
//
//  Lets the user point Catchlight at a folder where encrypted Takes will sync.
//  ONE path: pick a folder from Files (UIDocumentPickerViewController scoped to
//  UTType.folder). Persisted as a security-scoped bookmark under the
//  `catchlight.cloudFolderBookmark` UserDefaults key that `Wiring.makeSyncEngine`
//  and `FileCloudFolder(bookmark:)` resolve at sync time.
//
//  Supported providers = iCloud Drive + Dropbox only (device-verified
//  2026-06-22): folder-in-place selection requires NSFileProviderReplicatedExtension,
//  which only those two implement — every other cloud greys out in the picker.
//  The paste-a-URL fallback was removed 2026-06-22; a typed path can never gain
//  iOS write access (the grant must come through the picker), so it only ever
//  failed. See 03_Engineering/Cloud_Provider_Sync_Compatibility.md.
//
//  This view does NOT perform iCloud sync — it only configures the destination.
//

import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct CloudStorageView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app

    @State private var pickerPresented = false
    @State private var folderDisplayPath: String? = Self.currentFolderDisplayPath()
    @State private var errorText: String?
    /// Transient "Syncing…" feedback after a manual Sync Now (owner 2026-06-21).
    @State private var syncFeedback: String?

    @AppStorage(SettingsViewModel.SyncMode.defaultsKey)
    private var syncModeRaw: String = SettingsViewModel.SyncMode.default.rawValue

    private let appGroupDefaults = UserDefaults(suiteName: AppGroup.identifier)

    // Audit 2026-08, DT13: above the default sizes the static content OVERFLOWS —
    // the body ran over the nav title, the primary button truncated, and the only
    // vertical gesture DISMISSED the sheet, so cloud setup could not be completed
    // at accessibility sizes at all (owner device report, bench-reproduced). Gate
    // matches DockPillRow's D-030 threshold (> .large), like the onboarding
    // scaffold (DT6): at default sizes the layout is byte-identical to before.
    @Environment(\.dynamicTypeSize) private var dynamicSize

    var body: some View {
        NavigationStack {
            Group {
                if dynamicSize > .large {
                    // A ScrollView also absorbs the vertical drag, so scrolling
                    // reaches the content instead of dismissing the sheet.
                    ScrollView {
                        sheetContent
                    }
                    .scrollIndicators(.hidden)
                } else {
                    sheetContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.ckBackground)
            // System inline nav title, matching the other Settings sub-pages
            // (About / Notice History / Privacy Phrase) — owner 2026-06-29; the
            // bespoke cloud-glyph hero was the only sub-page that differed.
            .navigationTitle("Cloud Storage")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $pickerPresented) {
            FolderPicker { url in
                handlePickedFolder(url)
            }
            .ignoresSafeArea()
        }
        // Announce the async state changes (audit 2026-08, V14): the transient
        // "Syncing…" line and the connect error both appear silently. The error
        // is the same class, enumerated with the row's named site.
        //
        // DT13 placement (2026-09-02): these stay on the NAVIGATION STACK, OUTSIDE
        // the `dynamicSize` branch above. Attached inside that branch — on the
        // ScrollView, or within `sheetContent` — a change of text size swaps which
        // arm renders, and SwiftUI tears down the old subtree and builds the new
        // one, so a `syncFeedback` or `errorText` change landing across that swap
        // could go unannounced. Out here the observer's lifetime is the sheet's,
        // which is what V14 assumed when it was written against the flat layout.
        .onChange(of: syncFeedback) { _, feedback in
            if let feedback {
                UIAccessibility.post(notification: .announcement, argument: feedback)
            }
        }
        .onChange(of: errorText) { _, error in
            if let error {
                UIAccessibility.post(notification: .announcement, argument: error)
            }
        }
    }

    /// The sheet's content column — static at default sizes (owner 2026-06-21:
    /// the content fits, so it sits still like About), scrolled above `.large`
    /// (DT13).
    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            intro

            pickerSection

            finePrint

            divider

            syncModeSection

            if let errorText {
                Text(errorText)
                    .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.ckRuby)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Sections

    /// Two-line instruction with deliberate breathing room between each line
    /// (owner 2026-06-22), plus the privacy reassurance underneath.
    private var intro: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose from iCloud Drive or Dropbox")
                .font(CatchlightFont.display(size: 28, relativeTo: .title2))
                .foregroundStyle(Color.ckTextPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 18)   // 1 line break after "Choose from…"

            Text("Select an empty folder, or create a new one, and we'll take care of the rest.")
                .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                .foregroundStyle(Color.ckTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)   // 1 line break after "Select an empty…"

            Text("Catchlight never sees your files — only you can read them.")
                .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .subheadline))
                .foregroundStyle(Color.ckTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Primary action. Label is "Choose folder from Files" (unchanged — the UI
    // tests' button query matches it); it also serves as the "change" path when a
    // folder is already set, so a separate "Change folder" action is unnecessary.
    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { pickerPresented = true } label: {
                Text("Choose folder from Files")
                    .font(CatchlightFont.ui(.medium, size: 15, relativeTo: .body))
                    .foregroundStyle(Color.ckOnAccent)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(Color.ckEmber))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the Files picker to choose a folder for sync.")

            if let folderDisplayPath {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.ckAccent)
                    Text(folderDisplayPath)
                        .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .footnote))
                        .foregroundStyle(Color.ckTextSecondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .padding(.top, 2)
                // Audit 2026-08, V17: a label on a non-combined container is a
                // no-op — combine first so the label lands on a real element.
                // The checkmark glyph folds in with it (V21's inconsistency).
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "Current folder: \(folderDisplayPath)"))

                // Remove clears the bookmark and returns the app to local-only mode.
                // Centred under the folder path (owner 2026-06-22).
                HStack {
                    Spacer()
                    Button("Remove") { removeFolder() }
                        .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .body))
                        .foregroundStyle(Color.ckRuby)
                        // T4 (audit 2026-08): a destructive control tapped at its
                        // ~19pt line. Inset −13 reaches the 44pt hit floor; the
                        // Spacers either side make the overspill safe.
                        .contentShape(Rectangle().inset(by: -13))
                        .accessibilityIdentifier("cloud-remove-folder")
                        .accessibilityHint("Return to local-only mode.")
                    Spacer()
                }
            }
        }
    }

    /// Dropbox needs its app present to expose the folder through Files; iCloud is
    /// always there, so this only matters for the Dropbox path.
    private var finePrint: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Color.ckTextSecondary)
                .accessibilityHidden(true)
            Text("You'll need to have the Dropbox app installed, and signed-in, on your device to access via Catchlight.")
                .font(CatchlightFont.ui(.regular, size: 12, relativeTo: .caption))
                .foregroundStyle(Color.ckTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func removeFolder() {
        Wiring.clearCloudFolderBookmark()
        folderDisplayPath = nil
        errorText = nil
    }

    // MARK: - Sync mode (owner 2026-06-21)

    /// Disabled / Manual / Automatic, plus a Sync Now button in Manual mode. Same
    /// `.menu` dropdown language as the main Settings sheet. The one-line
    /// clarifier stays — Manual vs Automatic semantics aren't self-evident and the
    /// choice governs whether edits leave the device.
    private var syncModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Shared selector look (grey value + up/down chevron, 44pt) via MenuFieldRow
            // — no leading icon here, matching this borderless section (owner 2026-06-29).
            Menu {
                Picker("Sync", selection: syncModeBinding) {
                    ForEach(SettingsViewModel.SyncMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            } label: {
                MenuFieldRow(title: "Sync", value: syncMode.label)
            }
            .tint(Color.ckTextSecondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Sync \(syncMode.label)")

            Text(syncModeDescription)
                .font(CatchlightFont.ui(.regular, size: 12, relativeTo: .caption))
                .foregroundStyle(Color.ckTextSecondary)

            if syncMode == .manual {
                Button { fireManualSync() } label: {
                    Text(syncFeedback ?? "Sync Now")
                        .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .body))
                        .foregroundStyle(hasFolderConfigured ? Color.ckTextObie : Color.ckTextSecondary)
                }
                // T4: same 44pt hit floor as Remove above.
                .contentShape(Rectangle().inset(by: -13))
                .disabled(!hasFolderConfigured || syncFeedback != nil)
                // Audit 2026-08, C8: the no-folder disabled state was hue-swap
                // only — invisible to a sighted user who can't distinguish the
                // hues. The house disabled-dim carries it; the transient
                // "Syncing…" state keeps full strength (its text IS the signal).
                .opacity(hasFolderConfigured ? 1 : 0.38)
                .accessibilityIdentifier("cloud-sync-now")
                .accessibilityHint("Run a sync pass now.")
            }
        }
    }

    private var syncMode: SettingsViewModel.SyncMode {
        SettingsViewModel.SyncMode(rawValue: syncModeRaw) ?? .default
    }

    private var syncModeBinding: Binding<SettingsViewModel.SyncMode> {
        Binding(get: { syncMode }, set: { syncModeRaw = $0.rawValue })
    }

    private var syncModeDescription: String {
        switch syncMode {
        case .auto:     return "Syncs automatically in the background and when you open the app."
        case .manual:   return "Only syncs when you tap Sync Now."
        case .disabled: return "Never syncs. Your Takes stay on this device."
        }
    }

    /// Whether a sync destination is configured — i.e. a folder has been picked.
    private var hasFolderConfigured: Bool {
        folderDisplayPath != nil
    }

    /// Fire a one-shot manual sync through the shared coordinator. We know it
    /// *starts* (so show "Syncing…"), but the coordinator exposes no completion
    /// callback here — the clear is time-boxed, and the timeline/error strips
    /// surface the actual result. Honest, not a false "Done".
    private func fireManualSync() {
        app.performManualSync?()
        syncFeedback = "Syncing…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            syncFeedback = nil
        }
    }

    /// Hairline separator between the destination block and the Sync controls.
    private var divider: some View {
        Rectangle()
            .fill(Color.ckTextSecondary.opacity(0.18))
            .frame(height: 1)
    }

    // MARK: - Handlers

    private func handlePickedFolder(_ url: URL) {
        // Save the bookmark AND fire the first sync via the shared AppModel path
        // (also used by the post-restore guidance card) so connect-then-sync behaves
        // identically from both entry points. D-103.
        if let error = app.connectCloudFolder(url) {
            errorText = error
        } else {
            folderDisplayPath = url.path
            errorText = nil
            syncFeedback = "Syncing…"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { syncFeedback = nil }
        }
    }

    // MARK: - Display helpers

    private static func currentFolderDisplayPath() -> String? {
        guard let data = UserDefaults(suiteName: AppGroup.identifier)?
                .data(forKey: Wiring.bookmarkDefaultsKey) else {
            return nil
        }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [.withoutUI],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else {
            return nil
        }
        return url.path
    }
}

// MARK: - UIDocumentPickerViewController bridge

/// Thin `UIViewControllerRepresentable` over `UIDocumentPickerViewController`
/// scoped to folder selection. Calls `onPicked` exactly once with the chosen
/// URL; the caller is responsible for converting that URL to a
/// security-scoped bookmark (see `FileCloudFolder.makeBookmark`).
struct FolderPicker: UIViewControllerRepresentable {

    let onPicked: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (URL) -> Void
        init(onPicked: @escaping (URL) -> Void) { self.onPicked = onPicked }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPicked(url)
        }
    }
}
