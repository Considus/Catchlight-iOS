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

    @State private var pickerPresented = false
    @State private var folderDisplayPath: String? = Self.currentFolderDisplayPath()
    @State private var folderURLString: String = Self.currentFolderURLString()
    @State private var errorText: String?

    private let appGroupDefaults = UserDefaults(suiteName: AppGroup.identifier)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    pickerSection

                    divider

                    urlSection

                    if let errorText {
                        Text(errorText)
                            .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .footnote))
                            .foregroundStyle(Color.ckRuby)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Color.ckBackground)
            .navigationTitle("Cloud Storage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.ckTextObie)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .safeAreaInset(edge: .bottom) {
            // Primary action at the dock position (D-022 pill system). The
            // label is unchanged so the UI tests' button query still matches.
            DockPillRow {
                DockPill(title: "Choose folder from Files") { pickerPresented = true }
                    .accessibilityHint("Opens the Files picker to choose a folder for sync.")
            }
            .dockFadeBackground()
        }
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

    // The primary action lives in the bottom dock-pill row (D-022 button
    // system, applied 2026-06-12) — this section now carries only the
    // current-folder status and its secondary actions.
    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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

                // Task 6.13 — Change / Remove secondary actions. "Change" is
                // the same flow as the primary button; "Remove" clears the
                // bookmark and returns the app to local-only mode.
                HStack(spacing: 16) {
                    // L10N: candidate for icon-only — "Change folder" sits in
                    // the same row as Remove; an icon-first treatment (folder.badge)
                    // would carry intent without occupying line-width across locales.
                    Button("Change folder") { pickerPresented = true }
                        .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .body))
                        .foregroundStyle(Color.ckTextObie)
                        .accessibilityIdentifier("cloud-change-folder")
                    // L10N: candidate for icon-only — destructive intent reads
                    // well as a trash glyph; the accessibilityLabel below would
                    // still surface "Remove" copy to VoiceOver.
                    Button("Remove") { removeFolder() }
                        .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .body))
                        .foregroundStyle(Color.ckRuby)
                        .accessibilityIdentifier("cloud-remove-folder")
                        .accessibilityHint("Return to local-only mode.")
                }
            }
        }
    }

    private func removeFolder() {
        Wiring.clearCloudFolderBookmark()
        folderDisplayPath = nil
        folderURLString = ""
        errorText = nil
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
