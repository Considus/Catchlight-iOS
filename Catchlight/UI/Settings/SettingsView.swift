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
//  Access: swipe UP on the dock (BottomDockView — owner redesign 2026-06-11;
//  replaces the long-press on Dailies). The orientation Hint 3 short-circuits the
//  gesture until orientation step >= 4; after that, the swipe flips UIState.isSettingsPresented.
//

import SwiftUI
import UserNotifications

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var ui
    @AppStorage(SettingsViewModel.appearanceDefaultsKey) private var appearanceModeRaw: String = SettingsViewModel.AppearanceMode.system.rawValue
    @AppStorage(SettingsViewModel.LockAfter.defaultsKey) private var lockAfterRaw: String = SettingsViewModel.LockAfter.default.rawValue
    @AppStorage(SettingsViewModel.TakeSpacing.defaultsKey) private var takeSpacingRaw: String = SettingsViewModel.TakeSpacing.default.rawValue
    @AppStorage(SettingsViewModel.TakeSort.defaultsKey) private var takeSortRaw: String = SettingsViewModel.TakeSort.default.rawValue
    @AppStorage(SettingsViewModel.TakePreview.defaultsKey) private var takePreviewRaw: String = SettingsViewModel.TakePreview.default.rawValue
    @AppStorage(SettingsViewModel.AutoCleanup.defaultsKey) private var autoCleanupRaw: String = SettingsViewModel.AutoCleanup.default.rawValue
    @AppStorage(SettingsViewModel.DefaultReminderHours.defaultsKey) private var defaultReminderHoursRaw: String = SettingsViewModel.DefaultReminderHours.default.rawValue
    @AppStorage(SettingsViewModel.SnoozeDuration.defaultsKey) private var snoozeDurationRaw: String = SettingsViewModel.SnoozeDuration.default.rawValue

    @State private var vm = SettingsViewModel()

    #if DEBUG
    /// Gate for the destructive DEBUG reset's confirmation alert (section 2).
    @State private var showResetConfirm = false
    /// Settings-backed toggle for the section 2b on-device inset readout overlay.
    @AppStorage(DebugInsetReadoutSettings.defaultsKey) private var showInsetReadout = false
    #endif

    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                remindersSection
                securitySection
                syncSection
                subscriptionSection
                systemSection
                #if DEBUG
                debugSection
                #endif
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
        // The sheet owns its colour scheme directly (owner 2026-06-19): an already-
        // presented sheet doesn't reliably re-follow the app-level preferredColorScheme,
        // and crucially won't RELEASE a forced scheme back to `nil` — so System (nil)
        // left the overlay stuck on the last forced scheme. `settingsScheme` resolves
        // System to an explicit value (read from the screen), so the sheet always gets
        // a concrete scheme and re-themes live in every direction.
        .preferredColorScheme(settingsScheme)
        .presentationDragIndicator(.visible)
        .task {
            await vm.refreshNotificationStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Returning from iOS Settings: re-poll in case the user toggled.
                Task { await vm.refreshNotificationStatus() }
            }
        }
        // Sub-screen sheets (Task 3.12). Each presents on its own bool so they
        // never compete with one another and each can be drag-dismissed.
        .sheet(isPresented: $vm.isPhraseSheetPresented) {
            PrivacyPhraseView()
        }
        .sheet(isPresented: $vm.isCloudStorageSheetPresented) {
            CloudStorageView()
        }
        .sheet(isPresented: $vm.isAboutSheetPresented) {
            AboutView()
        }
        #if DEBUG
        .alert("Reset Catchlight?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Wipe & re-onboard", role: .destructive) {
                DebugReset.wipeAndRelaunch()
            }
        } message: {
            Text("Deletes the master key, privacy phrase, all settings, and every Take, then quits the app so the next launch starts onboarding. DEBUG builds only.")
        }
        #endif
    }

    #if DEBUG
    // MARK: - DEBUG (never compiled into Release / TestFlight)

    /// Developer-only aids for on-device testing (fix pass 1, sections 2 / 2b).
    /// The whole section is `#if DEBUG`, so it cannot ship.
    private var debugSection: some View {
        Section {
            // Section 2 — one-tap re-onboarding on a real device. The Keychain
            // survives app deletion, so this is the only way to re-trigger
            // onboarding without a full device wipe.
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "trash")
                        .font(.system(size: 20, weight: .regular))
                        .frame(width: 26)
                        .accessibilityHidden(true)
                    Text("Reset Catchlight (wipe & re-onboard)")
                        .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ckRuby)
            .listRowBackground(Color.ckSurface)
            .accessibilityIdentifier("debug-reset")
            .accessibilityHint("Wipes everything and returns to onboarding. Debug builds only.")

            // Section 2b — toggle the on-device safe-area inset readout overlay.
            Toggle(isOn: $showInsetReadout) {
                HStack(spacing: 14) {
                    Image(systemName: "ruler")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Color.ckAccent)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                    Text("Inset readout")
                        .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                        .foregroundStyle(Color.ckTextPrimary)
                }
            }
            .tint(Color.ckEmber)
            .frame(minHeight: 52)
            .listRowBackground(Color.ckSurface)
            .accessibilityIdentifier("debug-inset-readout-toggle")
            .accessibilityHint("Shows live safe-area insets bottom-right, to verify the device-layout fix.")
        } header: {
            sectionHeader("Debug")
        }
    }
    #endif

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            // Mode picker — segmented control inline, no navigation push.
            HStack(spacing: 14) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.ckAccent)
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

            // Timeline density — the gap between Takes on Dailies (owner 2026-06-16).
            // Segmented control matching the Mode row; labelled "View" so the three
            // options fit the inline 220pt width.
            HStack(spacing: 14) {
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.ckAccent)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text("View")
                    .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                    .foregroundStyle(Color.ckTextPrimary)
                Spacer()
                Picker("View", selection: takeSpacingBinding) {
                    ForEach(SettingsViewModel.TakeSpacing.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .accessibilityLabel("Take spacing")
            }
            .frame(height: 52)
            .listRowBackground(Color.ckSurface)

            // Take preview length — how much of a collapsed Take's body shows on the
            // timeline (owner 2026-06-16). Independent of "View" density; the reminder
            // time label always shows regardless. Ordered before Order (owner: Mode,
            // View, Preview, Order, Scenes).
            HStack(spacing: 14) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.ckAccent)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text("Preview")
                    .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                    .foregroundStyle(Color.ckTextPrimary)
                Spacer()
                Picker("Preview", selection: takePreviewBinding) {
                    ForEach(SettingsViewModel.TakePreview.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .accessibilityLabel("Take preview length")
            }
            .frame(height: 52)
            .listRowBackground(Color.ckSurface)

            // Timeline order — which end of time sits at the top (owner 2026-06-16).
            HStack(spacing: 14) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.ckAccent)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text("Order")
                    .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                    .foregroundStyle(Color.ckTextPrimary)
                Spacer()
                Picker("Order", selection: takeSortBinding) {
                    ForEach(SettingsViewModel.TakeSort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .accessibilityLabel("Timeline order")
            }
            .frame(height: 52)
            .listRowBackground(Color.ckSurface)

            SettingsRow(icon: "paintpalette",
                        label: "Scenes",
                        disabled: true) {
                SettingsDetailLabel(text: "Coming soon")
            }
            .accessibilityHint("Coming soon.")
        } header: {
            sectionHeader("Appearance")
        } footer: {
            Text("How much of each Take previews, the spacing between Takes, and whether the oldest or newest sits at the top. The Obie always stays pinned at the top.")
                .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .footnote))
                .foregroundStyle(Color.ckTextSecondary)
        }
    }

    /// The scheme to FORCE on the Settings sheet. Night/Daylight map directly; System
    /// resolves to the DEVICE scheme read from the SCREEN — not
    /// `UITraitCollection.current`, which carries this view's own (stale) override and
    /// would keep System stuck on the previously-forced scheme (owner 2026-06-19).
    private var settingsScheme: ColorScheme? {
        switch SettingsViewModel.AppearanceMode(rawValue: appearanceModeRaw) ?? .system {
        case .night: return .dark
        case .daylight: return .light
        case .system:
            return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        }
    }

    private var appearanceBinding: Binding<SettingsViewModel.AppearanceMode> {
        Binding(
            get: { SettingsViewModel.AppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    private var takeSpacingBinding: Binding<SettingsViewModel.TakeSpacing> {
        Binding(
            get: { SettingsViewModel.TakeSpacing(rawValue: takeSpacingRaw) ?? .default },
            set: { takeSpacingRaw = $0.rawValue }
        )
    }

    private var takePreviewBinding: Binding<SettingsViewModel.TakePreview> {
        Binding(
            get: { SettingsViewModel.TakePreview(rawValue: takePreviewRaw) ?? .default },
            set: { takePreviewRaw = $0.rawValue }
        )
    }

    private var takeSortBinding: Binding<SettingsViewModel.TakeSort> {
        Binding(
            get: { SettingsViewModel.TakeSort(rawValue: takeSortRaw) ?? .default },
            set: { takeSortRaw = $0.rawValue }
        )
    }

    private var autoCleanupBinding: Binding<SettingsViewModel.AutoCleanup> {
        Binding(
            get: { SettingsViewModel.AutoCleanup(rawValue: autoCleanupRaw) ?? .default },
            set: { autoCleanupRaw = $0.rawValue }
        )
    }

    // MARK: - Security

    // MARK: - Reminders

    private var remindersSection: some View {
        Section {
            // How many hours ahead a freshly-added reminder opens to (owner 2026-06-18).
            // Segmented control like the View/Order rows — the labels are short numbers.
            // `PetalFanView.defaultReminderDate` reads the same key.
            HStack(spacing: 14) {
                Image(systemName: "clock")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.ckAccent)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text("Default timing (hrs)")
                    .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                    .foregroundStyle(Color.ckTextPrimary)
                Spacer()
                Picker("Default timing", selection: defaultReminderHoursBinding) {
                    ForEach(SettingsViewModel.DefaultReminderHours.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .accessibilityLabel("Default reminder timing in hours")
            }
            .frame(height: 52)
            .listRowBackground(Color.ckSurface)

            // Snooze duration — how long the reminder notification's "Snooze" pull-down
            // action defers by (owner 2026-06-20). Read by `NotificationPresenter` from
            // this preference (works while locked, when the encrypted store doesn't).
            // Menu picker like Lock after / Auto-delete (the labels are too long for a
            // segmented control).
            HStack(spacing: 14) {
                Image(systemName: "zzz")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.ckAccent)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text("Snooze")
                    .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                    .foregroundStyle(Color.ckTextPrimary)
                Spacer()
                Picker("Snooze", selection: snoozeDurationBinding) {
                    ForEach(SettingsViewModel.SnoozeDuration.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Color.ckTextSecondary)
            }
            .frame(height: 52)
            .listRowBackground(Color.ckSurface)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Snooze duration \(snoozeDurationBinding.wrappedValue.label)")
        } header: {
            sectionHeader("Reminders")
        } footer: {
            Text("How many hours ahead a new reminder starts (you can always adjust the exact time before saving), and how long the notification's Snooze button defers by.")
                .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .footnote))
                .foregroundStyle(Color.ckTextSecondary)
        }
    }

    private var defaultReminderHoursBinding: Binding<SettingsViewModel.DefaultReminderHours> {
        Binding(
            get: { SettingsViewModel.DefaultReminderHours(rawValue: defaultReminderHoursRaw) ?? .default },
            set: { defaultReminderHoursRaw = $0.rawValue }
        )
    }

    private var snoozeDurationBinding: Binding<SettingsViewModel.SnoozeDuration> {
        Binding(
            get: { SettingsViewModel.SnoozeDuration(rawValue: snoozeDurationRaw) ?? .default },
            set: {
                snoozeDurationRaw = $0.rawValue
                // Refresh the banner action's "Snooze for …" label to match the new default.
                NotificationPresenter.registerReminderCategory()
            }
        )
    }

    private var securitySection: some View {
        Section {
            // Lock after — the background grace window before a return re-locks
            // (D-042). The app ALWAYS locks on cold launch and when the phone locks
            // while Catchlight is in front; this only governs the in-background grace.
            HStack(spacing: 14) {
                Image(systemName: "lock")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.ckAccent)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text("Lock after")
                    .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                    .foregroundStyle(Color.ckTextPrimary)
                Spacer()
                Picker("Lock after", selection: lockAfterBinding) {
                    ForEach(SettingsViewModel.LockAfter.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Color.ckTextSecondary)
            }
            .frame(height: 52)
            .listRowBackground(Color.ckSurface)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Lock after \(lockAfterBinding.wrappedValue.label)")

            // Auto-delete — data minimisation (owner 2026-06-19: lives under Security,
            // since trimming finished data you no longer need limits your exposure).
            // The user decides the window ([[catchlight-user-decides-principle]]); only
            // done, note-free Takes are ever eligible (see the footer + Take.isAutoCleanupEligible).
            HStack(spacing: 14) {
                Image(systemName: "trash")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.ckAccent)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text("Auto-delete")
                    .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                    .foregroundStyle(Color.ckTextPrimary)
                Spacer()
                Picker("Auto-delete", selection: autoCleanupBinding) {
                    ForEach(SettingsViewModel.AutoCleanup.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Color.ckTextSecondary)
            }
            .frame(height: 52)
            .listRowBackground(Color.ckSurface)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Auto-delete completed Takes, \(autoCleanupBinding.wrappedValue.label)")

            SettingsRow(icon: "key.horizontal",
                        label: "Privacy phrase",
                        chevron: true,
                        action: { vm.isPhraseSheetPresented = true })
                .accessibilityHint("Double-tap to view your phrase. Face ID or passcode required.")

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
        } footer: {
            Text("Catchlight locks after this long in the background. It always locks when you quit the app or lock your phone while it's open.\n\nAuto-delete keeps your stored data lean: once all its tasks and reminders are done and it holds no note, a Take is removed after the time you choose. Notes — and anything still in progress — are never deleted. Off by default.")
                .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .footnote))
                .foregroundStyle(Color.ckTextSecondary)
        }
    }

    private var lockAfterBinding: Binding<SettingsViewModel.LockAfter> {
        Binding(
            get: { SettingsViewModel.LockAfter(rawValue: lockAfterRaw) ?? .default },
            set: { lockAfterRaw = $0.rawValue }
        )
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
