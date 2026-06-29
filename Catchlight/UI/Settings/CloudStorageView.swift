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

    var body: some View {
        NavigationStack {
            // Static, non-scrolling layout (owner 2026-06-21) — the content fits the
            // sheet, so it sits still like the About sheet rather than bouncing in a
            // ScrollView. No Done button either; dismiss by swiping down (the drag
            // indicator shows the affordance), matching About.
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
    }

    // MARK: - Sections

    /// Two-line instruction with deliberate breathing room between each line
    /// (owner 2026-06-22), plus the privacy reassurance underneath.
    private var intro: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose from iCloud Drive or Dropbox")
                .font(CatchlightFont.displayFixed(size: 28))
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
                .accessibilityLabel(String(localized: "Current folder: \(folderDisplayPath)"))

                // Remove clears the bookmark and returns the app to local-only mode.
                // Centred under the folder path (owner 2026-06-22).
                HStack {
                    Spacer()
                    Button("Remove") { removeFolder() }
                        .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .body))
                        .foregroundStyle(Color.ckRuby)
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
            HStack(spacing: 14) {
                Text("Sync")
                    .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                    .foregroundStyle(Color.ckTextPrimary)
                Spacer()
                Picker("Sync", selection: syncModeBinding) {
                    ForEach(SettingsViewModel.SyncMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Color.ckTextSecondary)
            }
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
                .disabled(!hasFolderConfigured || syncFeedback != nil)
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
        do {
            let bookmark = try FileCloudFolder.makeBookmark(for: url)
            appGroupDefaults?.set(bookmark, forKey: Wiring.bookmarkDefaultsKey)
            folderDisplayPath = url.path
            errorText = nil
        } catch {
            errorText = "Couldn't save that folder: \(error.localizedDescription)"
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
