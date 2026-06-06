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
    @AppStorage(SettingsViewModel.appearanceDefaultsKey) private var appearanceModeRaw: String = SettingsViewModel.AppearanceMode.system.rawValue

    @State private var vm = SettingsViewModel()

    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                securitySection
                syncSection
                systemSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.ckBackground)
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
        .task { await vm.refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Returning from iOS Settings: re-poll in case the user toggled.
                Task { await vm.refreshNotificationStatus() }
            }
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
                        disabled: true)
                .accessibilityHint("Coming soon.")

            SettingsRow(icon: "key.horizontal",
                        label: "Privacy phrase",
                        chevron: true,
                        disabled: true)
                .accessibilityHint("Coming soon.")

            // 6.12 — Blocked. Surface as a stub so the sheet layout is complete.
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
            // 6.13 — Blocked on Phase 2 cloud-folder selection. Stub for now.
            SettingsRow(icon: "icloud",
                        label: "Cloud Storage",
                        chevron: true,
                        disabled: true) {
                SettingsDetailLabel(text: "Coming soon")
            }
            .accessibilityHint("Coming soon.")
        } header: {
            sectionHeader("Sync")
        }
    }

    // MARK: - System

    private var systemSection: some View {
        Section {
            notificationsRow
            SettingsRow(icon: "info.circle", label: "About") {
                SettingsDetailLabel(text: aboutString)
            }
            .accessibilityLabel("About. \(aboutString)")
        } header: {
            sectionHeader("System")
        }
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
