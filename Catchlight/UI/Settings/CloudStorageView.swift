//
//  CloudStorageView.swift
//  Catchlight (iOS app target) — Task 3.12
//
//  Settings → Sync → Cloud Storage.
//
//  Lets the user point Catchlight at a folder where encrypted Takes will sync.
//  Two paths, both always visible:
//    1. Pick a folder from Files (UIDocumentPickerViewController scoped to
//       UTType.folder). Persisted as a security-scoped bookmark under the
//       SAME UserDefaults key (`catchlight.cloudFolderBookmark`) that
//       `Wiring.makeSyncEngine` and `FileCloudFolder(bookmark:)` already
//       resolve at sync time.
//    2. Paste a URL — fallback for NAS / Proton Drive / any provider that
//       isn't surfaced through Files. Persisted under
//       `catchlight.cloudFolderURLString` so BackgroundSync can pick it up
//       once URL-mode sync lands (Task 6.13).
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
    @State private var folderURLString: String = Self.currentFolderURLString()
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
                header

                pickerSection

                divider

                urlSection

                syncModeSection

                if let errorText {
                    Text(errorText)
                        .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .footnote))
                        .foregroundStyle(Color.ckRuby)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.ckBackground)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose where your encrypted Takes are stored.")
                .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                .foregroundStyle(Color.ckTextPrimary)
            Text("Catchlight never sees your files — only you can read them.")
                .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .subheadline))
                .foregroundStyle(Color.ckTextSecondary)
        }
    }

    // Primary action moved up here, directly above the "or" divider (owner
    // 2026-06-21): the docked-pill position read as disconnected from the folder
    // status it controls. Label unchanged ("Choose folder from Files") so the UI
    // tests' button query still matches; it also serves as the "change" path when
    // a folder is already set, so the separate "Change folder" action is retired.
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
                .accessibilityLabel(String(localized: "Current folder: \(folderDisplayPath)"))

                // Remove clears the bookmark and returns the app to local-only mode.
                Button("Remove") { removeFolder() }
                    .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .body))
                    .foregroundStyle(Color.ckRuby)
                    .accessibilityIdentifier("cloud-remove-folder")
                    .accessibilityHint("Return to local-only mode.")
            }
        }
    }

    private func removeFolder() {
        Wiring.clearCloudFolderBookmark()
        folderDisplayPath = nil
        folderURLString = ""
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

    /// Whether anything is configured to sync to — a picked folder or a saved URL.
    private var hasFolderConfigured: Bool {
        folderDisplayPath != nil
            || !folderURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private var divider: some View {
        HStack {
            Rectangle().fill(Color.ckTextSecondary.opacity(0.3)).frame(height: 1)
            Text("or")
                .font(CatchlightFont.ui(.regular, size: 12, relativeTo: .caption))
                .foregroundStyle(Color.ckTextSecondary)
                .padding(.horizontal, 10)
            Rectangle().fill(Color.ckTextSecondary.opacity(0.3)).frame(height: 1)
        }
    }

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Paste a folder URL…", text: $folderURLString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.ckSurface)
                )
                .onSubmit { commitURLString() }

            Text("Use a URL for NAS, Proton Drive, or any provider not in your Files app.")
                .font(CatchlightFont.ui(.regular, size: 12, relativeTo: .caption))
                .foregroundStyle(Color.ckTextSecondary)

            HStack {
                Spacer()
                Button("Save URL") { commitURLString() }
                    .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .body))
                    .foregroundStyle(Color.ckTextObie)
                    .disabled(folderURLString.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
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

    private func commitURLString() {
        let trimmed = folderURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Validate before persisting (2026-06-10). Previously ANY string was
        // saved with implicit success while the sync engine never read this key
        // at all — the user believed sync was configured and the app silently
        // ran local-only. The engine now consumes this slot (see
        // Wiring.makeSyncEngine), so reject inputs that can't possibly work:
        // the URL must point at a folder this app can actually read.
        guard let url = Wiring.usableFolderURL(from: trimmed) else {
            errorText = "That location couldn't be opened. For iCloud Drive or other Files-app providers, use \u{201C}Choose Folder\u{201D} instead."
            return
        }
        appGroupDefaults?.set(url.absoluteString, forKey: Wiring.cloudFolderURLStringDefaultsKey)
        errorText = nil
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

    private static func currentFolderURLString() -> String {
        UserDefaults(suiteName: AppGroup.identifier)?
            .string(forKey: Wiring.cloudFolderURLStringDefaultsKey) ?? ""
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
