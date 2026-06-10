//
//  SettingsView.swift
//  Catchlight (iOS app target) — Phase 6 UI, Task 6.14
//
//  The Settings sheet — four sections (Appearance, Security, Sync, System) and
//  eight rows. Most rows are placeholders for later phases; the Notifications row
//  is fully functional (status inline, deep-link to iOS Settings when denied,
//  inline permission prompt when not determined).
//
//  Stubbed rows reference work-plan items that are intentionally Blocked at the
//  moment (6.12 Second device, 6.13 Cloud Storage) — the rows are visible so the
//  sheet layout is complete; tapping them no-ops or shows a "Coming soon" badge.
//
//  Access: long-press on the Dailies dock button (BottomDockView). The orientation
//  Hint 3 short-circuits the gesture until orientation step >= 4; after that, the
//  long-press flips UIState.isSettingsPresented.
//

import SwiftUI
import UserNotifications

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var ui
    @AppStorage(SettingsViewModel.appearanceDefaultsKey) private var appearanceModeRaw: String = SettingsViewModel.AppearanceMode.system.rawValue

    @State private var vm = SettingsViewModel()

    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                securitySection
                syncSection
                subscriptionSection
                systemSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.ckBackground)
            .accessibilityIdentifier("settings-sheet")
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(CatchlightFont.ui(.light, size: 22, relativeTo: .title3))
                        .foregroundStyle(Color.ckTextPrimary)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .task {
            await vm.refreshNotificationStatus()
            vm.refreshPINState()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Returning from iOS Settings: re-poll in case the user toggled.
                Task { await vm.refreshNotificationStatus() }
                vm.refreshPINState()
            }
        }
        // Sub-screen sheets (Task 3.12). Each presents on its own bool so they
        // never compete with one another and each can be drag-dismissed.
        .sheet(isPresented: $vm.isPINSheetPresented) {
            PINSetupView(
                initialMode: vm.hasPIN ? .manage : .create,
                onDidChangePINState: { vm.refreshPINState() }
            )
        }
        .sheet(isPresented: $vm.isPhraseSheetPresented) {
            PrivacyPhraseView()
        }
        .sheet(isPresented: $vm.isCloudStorageSheetPresented) {
            CloudStorageView()
        }
        .sheet(isPresented: $vm.isAboutSheetPresented) {
            AboutView()
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            // Mode picker — segmented control inline, no navigation push.
            HStack(spacing: 14) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.ckAdd)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text("Mode")
                    .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                    .foregroundStyle(Color.ckTextPrimary)
                Spacer()
                Picker("Appearance mode", selection: appearanceBinding) {
                    ForEach(SettingsViewModel.AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .accessibilityLabel("Appearance mode")
            }
            .frame(height: 52)
            .listRowBackground(Color.ckSurface)

            SettingsRow(icon: "paintpalette",
                        label: "Themes",
                        disabled: true) {
                SettingsDetailLabel(text: "Coming soon")
            }
            .accessibilityHint("Coming soon.")
        } header: {
            sectionHeader("Appearance")
        }
    }

    private var appearanceBinding: Binding<SettingsViewModel.AppearanceMode> {
        Binding(
            get: { SettingsViewModel.AppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    // MARK: - Security

    private var securitySection: some View {
        Section {
            SettingsRow(icon: "lock",
                        label: "PIN / biometrics",
                        chevron: true,
                        action: { vm.isPINSheetPresented = true }) {
                SettingsDetailLabel(text: vm.hasPIN ? "On" : "Off")
            }
            .accessibilityHint(vm.hasPIN ? "Change or remove your PIN." : "Set a PIN to lock the app.")

            SettingsRow(icon: "key.horizontal",
                        label: "Privacy phrase",
                        chevron: true,
                        action: { vm.isPhraseSheetPresented = true })
                .accessibilityHint("Double-tap to view your phrase. PIN confirmation required.")

            // 6.12 — Blocked on Phase 2. Stub stays visible so the layout is complete.
            SettingsRow(icon: "iphone.and.arrow.forward",
                        label: "Second device",
                        chevron: true,
                        disabled: true) {
                SettingsDetailLabel(text: "Coming soon")
            }
            .accessibilityHint("Coming soon.")
        } header: {
            sectionHeader("Security")
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        Section {
            SettingsRow(icon: "icloud",
                        label: "Cloud Storage",
                        chevron: true,
                        action: { vm.isCloudStorageSheetPresented = true }) {
                SettingsDetailLabel(text: cloudStorageDetail)
            }
            .accessibilityIdentifier("settings-cloud-storage")
            .accessibilityHint("Choose where encrypted Takes are stored.")
            .accessibilityValue(cloudStorageDetail)
        } header: {
            sectionHeader("Sync")
        }
    }

    /// Task 6.13 — Detail label for the Cloud Storage row. Shows the picked
    /// folder's last path component when configured, or "Not configured" when
    /// running in local-only mode. Refreshed via `scenePhase` so a folder
    /// picked or removed in the sub-sheet reflects when the sheet dismisses.
    private var cloudStorageDetail: String {
        if let url = try? Wiring.resolveCloudFolderURL()?.url, !url.path.isEmpty {
            // Last path component reads better than a deep iCloud path; the
            // sub-sheet shows the full path for users who need to verify it.
            // (User-provided folder name — not localised by definition.)
            return url.lastPathComponent
        }
        return String(localized: "Not configured",
                      comment: "Cloud Storage row detail label when no folder is picked.")
    }

    // MARK: - Subscription (Task 6.20)

    private var subscriptionSection: some View {
        Section {
            SettingsRow(icon: "sparkle",
                        label: "Manage Subscription",
                        chevron: true,
                        action: {
                            dismiss()
                            // Defer so the Settings sheet finishes dismissing
                            // before the paywall sheet presents.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                ui.isPaywallPresented = true
                            }
                        }) {
                SettingsDetailLabel(text: subscriptionRowDetail)
            }
            .accessibilityHint("View your subscription or restore purchases.")
        } header: {
            sectionHeader("Subscription")
        }
    }

    private var subscriptionRowDetail: String {
        switch app.subscriptionStatus {
        case .subscribed:
            return String(localized: "Active",
                          comment: "Subscription status — currently subscribed.")
        case .trial:
            return String(localized: "Free trial",
                          comment: "Subscription status — currently in the intro trial.")
        case .lapsed:
            return String(localized: "Inactive",
                          comment: "Subscription status — lapsed, in read-only mode.")
        case .unknown:
            return ""
        }
    }

    // MARK: - System

    private var systemSection: some View {
        Section {
            notificationsRow
            // Task 6.22 — always available, regardless of subscription status.
            // Decisions doc §5: "your data is yours, always" must hold even in
            // lapsed read-only mode. Do NOT wrap this in `ensureEntitled`.
            SettingsRow(icon: "square.and.arrow.up",
                        label: "Export Takes",
                        chevron: false,
                        action: { exportTakes() }) {
                SettingsDetailLabel(text: "Markdown")
            }
            .accessibilityIdentifier("settings-export-takes")
            .accessibilityHint("Export all your Takes as a Markdown file.")
            SettingsRow(icon: "info.circle",
                        label: "About",
                        chevron: true,
                        action: { vm.isAboutSheetPresented = true }) {
                SettingsDetailLabel(text: aboutString)
            }
            .accessibilityLabel("About. \(aboutString)")
        } header: {
            sectionHeader("System")
        }
    }

    @MainActor
    private func exportTakes() {
        // Reads through the live DailiesViewModel's store so the export reflects
        // whatever the user can see in the timeline (one store, one source of
        // truth). `allTakes()` already returns `createdAt` ascending; the
        // exporter re-sorts defensively.
        let takes = (try? app.dailiesVM.store.allTakes()) ?? []
        ExportCoordinator.presentShareSheet(takes: takes)
    }

    private var aboutString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let suffix = build.isEmpty ? "" : " (\(build))"
        return "Catchlight \(version)\(suffix)"
    }

    // MARK: - Notifications row (fully functional)

    @ViewBuilder
    private var notificationsRow: some View {
        switch vm.notificationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationsRowAuthorised
        case .denied:
            notificationsRowDenied
        case .notDetermined:
            notificationsRowNotDetermined
        @unknown default:
            notificationsRowNotDetermined
        }
    }

    private var notificationsRowAuthorised: some View {
        SettingsRow(icon: "bell", label: "Notifications") {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text("Enabled")
                    .font(CatchlightFont.ui(.regular, size: 15, relativeTo: .subheadline))
                    .foregroundStyle(Color.ckTextSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Notifications enabled")
        }
    }

    private var notificationsRowDenied: some View {
        SettingsRow(icon: "bell.slash",
                    label: "Notifications",
                    chevron: true,
                    action: { openSystemSettings() }) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text("Disabled")
                    .font(CatchlightFont.ui(.regular, size: 15, relativeTo: .subheadline))
                    .foregroundStyle(Color.ckTextSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Notifications disabled. Opens iOS Settings.")
        }
    }

    private var notificationsRowNotDetermined: some View {
        SettingsRow(icon: "bell.badge",
                    label: "Notifications",
                    action: { Task { await vm.requestNotificationPermission() } }) {
            if vm.notificationStatusLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Requesting notification permission")
            } else {
                SettingsDetailLabel(text: "Enable")
            }
        }
    }

    @MainActor
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Section headers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(CatchlightFont.ui(.medium, size: 13, relativeTo: .caption))
            .foregroundStyle(Color.ckTextSecondary)
            .textCase(.uppercase)
            .padding(.leading, 4)
            .padding(.top, 6)
    }
}

#Preview("Settings — Night") {
    Color.ckBackground
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) { SettingsView() }
        .preferredColorScheme(.dark)
}

#Preview("Settings — Daylight") {
    Color.ckBackground
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) { SettingsView() }
        .preferredColorScheme(.light)
}
