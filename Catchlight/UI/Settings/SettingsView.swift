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
import CatchlightCore

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
    /// Drives the Markdown / Plain Text chooser for Export Takes (owner 2026-06-21).
    @State private var showExportFormatDialog = false
    /// The Import-result message; non-nil presents the confirmation alert (owner 2026-06-22).
    @State private var importResultMessage: String?

    #if DEBUG
    /// Gate for the destructive DEBUG reset's confirmation alert (section 2).
    @State private var showResetConfirm = false
    /// Settings-backed toggle for the section 2b on-device inset readout overlay.
    @AppStorage(DebugInsetReadoutSettings.defaultsKey) private var showInsetReadout = false
    #endif

    var body: some View {
        NavigationStack {
            List {
                titleRow
                appearanceSection
                remindersSection
                securitySection
                subscriptionSection
                systemSection
                supportSection
                #if DEBUG
                debugSection
                #endif
            }
            .listStyle(.insetGrouped)
            // Density pass (owner 2026-06-21): let rows sit below the system's
            // ~44pt floor so the 40pt rows aren't padded back up, and pull the
            // inter-section gaps in.
            .environment(\.defaultMinListRowHeight, 40)
            .listSectionSpacing(.compact)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(Color.ckBackground)
            .accessibilityIdentifier("settings-sheet")
            // The "Settings" title scrolls with the list now (owner 2026-06-21) —
            // it lives in `titleRow` instead of a pinned nav bar, so it gets out of
            // the way on scroll. Hide the nav bar entirely (no collapsed inline
            // title left behind).
            .toolbar(.hidden, for: .navigationBar)
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
        // Export format chooser (owner 2026-06-21) — tap Export Takes, pick a
        // format, then the share sheet presents. No persisted preference.
        .confirmationDialog("Export Takes",
                            isPresented: $showExportFormatDialog,
                            titleVisibility: .visible) {
            Button("Markdown") { exportTakes(format: .markdown) }
            Button("Plain Text") { exportTakes(format: .plainText) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a format. Both include every Take and stay readable forever.")
        }
        // Import result (owner 2026-06-22) — immediate feedback while Settings is open
        // (the summary Take lands behind the sheet), and stops an accidental re-tap.
        .alert("Import", isPresented: importAlertPresented) {
            Button("OK", role: .cancel) { importResultMessage = nil }
        } message: {
            Text(importResultMessage ?? "")
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
                .frame(minHeight: 40)
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

    // MARK: - Title (scrolls with the list)

    /// The "Settings" heading as a scrolling list row (owner 2026-06-21) — clear
    /// background, no section chrome, so it reads as a title and scrolls away.
    private var titleRow: some View {
        Text("Settings")
            .font(CatchlightFont.ui(.light, size: 28, relativeTo: .title))
            .foregroundStyle(Color.ckTextPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 4, trailing: 20))
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            // Mode picker — menu dropdown, matching Lock after / Snooze etc. so the
            // whole sheet is one consistent control language (owner 2026-06-21).
            menuPickerRow(icon: "circle.lefthalf.filled",
                          label: "Mode",
                          accessibilityLabel: "Appearance mode",
                          selectionLabel: appearanceBinding.wrappedValue.label) {
                Picker("Appearance mode", selection: appearanceBinding) {
                    ForEach(SettingsViewModel.AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }

            // Timeline density — the gap between Takes on Dailies (owner 2026-06-16).
            menuPickerRow(icon: "arrow.up.and.down.text.horizontal",
                          label: "View",
                          accessibilityLabel: "Take spacing",
                          selectionLabel: takeSpacingBinding.wrappedValue.label) {
                Picker("View", selection: takeSpacingBinding) {
                    ForEach(SettingsViewModel.TakeSpacing.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }

            // Take preview length — how much of a collapsed Take's body shows on the
            // timeline (owner 2026-06-16). Independent of "View" density; the reminder
            // time label always shows regardless. Ordered before Order (owner: Mode,
            // View, Preview, Order, Scenes).
            menuPickerRow(icon: "text.alignleft",
                          label: "Preview",
                          accessibilityLabel: "Take preview length",
                          selectionLabel: takePreviewBinding.wrappedValue.label) {
                Picker("Preview", selection: takePreviewBinding) {
                    ForEach(SettingsViewModel.TakePreview.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }

            // Timeline order — which end of time sits at the top (owner 2026-06-16).
            menuPickerRow(icon: "arrow.up.arrow.down",
                          label: "Order",
                          accessibilityLabel: "Timeline order",
                          selectionLabel: takeSortBinding.wrappedValue.label) {
                Picker("Order", selection: takeSortBinding) {
                    ForEach(SettingsViewModel.TakeSort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }

            SettingsRow(icon: "paintpalette",
                        label: "Scenes",
                        disabled: true) {
                SettingsDetailLabel(text: "Coming soon")
            }
            .accessibilityHint("Coming soon.")
        } header: {
            sectionHeader("Appearance")
        }
    }

    /// Shared row for an inline menu-style `Picker` — one consistent control
    /// language across the whole sheet (owner 2026-06-21: ditch the segmented
    /// controls in favour of the Snooze / Lock after dropdown). Leading icon +
    /// label, the picker's current value as a tappable trailing menu. Compact
    /// 40pt height (owner 2026-06-21 density pass); the picker keeps its own
    /// ≥44pt tap region via the menu chevron's hit area.
    private func menuPickerRow<P: View>(icon: String,
                                        label: String,
                                        accessibilityLabel: String,
                                        selectionLabel: String,
                                        @ViewBuilder picker: () -> P) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.ckAccent)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(label)
                .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                .foregroundStyle(Color.ckTextPrimary)
            Spacer()
            picker()
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Color.ckTextSecondary)
        }
        .frame(height: 40)
        .listRowBackground(Color.ckSurface)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(accessibilityLabel) \(selectionLabel)")
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
            // `PetalFanView.defaultReminderDate` reads the same key.
            menuPickerRow(icon: "clock",
                          label: "Default timing",
                          accessibilityLabel: "Default reminder timing",
                          selectionLabel: defaultReminderHoursBinding.wrappedValue.label) {
                Picker("Default timing", selection: defaultReminderHoursBinding) {
                    ForEach(SettingsViewModel.DefaultReminderHours.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }

            // Snooze duration — how long the reminder notification's "Snooze" pull-down
            // action defers by (owner 2026-06-20). Read by `NotificationPresenter` from
            // this preference (works while locked, when the encrypted store doesn't).
            menuPickerRow(icon: "zzz",
                          label: "Snooze Duration",
                          accessibilityLabel: "Snooze duration",
                          selectionLabel: snoozeDurationBinding.wrappedValue.label) {
                Picker("Snooze", selection: snoozeDurationBinding) {
                    ForEach(SettingsViewModel.SnoozeDuration.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }
        } header: {
            sectionHeader("Reminders")
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
            menuPickerRow(icon: "lock",
                          label: "Lock after",
                          accessibilityLabel: "Lock after",
                          selectionLabel: lockAfterBinding.wrappedValue.label) {
                Picker("Lock after", selection: lockAfterBinding) {
                    ForEach(SettingsViewModel.LockAfter.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }

            // Auto-delete — data minimisation (owner 2026-06-19: lives under Security,
            // since trimming finished data you no longer need limits your exposure).
            // The user decides the window ([[catchlight-user-decides-principle]]); only
            // done, note-free Takes are ever eligible (see Take.isAutoCleanupEligible).
            menuPickerRow(icon: "trash",
                          label: "Auto-Delete (exc. notes)",
                          accessibilityLabel: "Auto-delete completed Takes, excluding notes,",
                          selectionLabel: autoCleanupBinding.wrappedValue.label) {
                Picker("Auto-delete", selection: autoCleanupBinding) {
                    ForEach(SettingsViewModel.AutoCleanup.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }

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
        }
    }

    private var lockAfterBinding: Binding<SettingsViewModel.LockAfter> {
        Binding(
            get: { SettingsViewModel.LockAfter(rawValue: lockAfterRaw) ?? .default },
            set: { lockAfterRaw = $0.rawValue }
        )
    }

    // MARK: - Sync

    /// The Cloud Storage row — sync now lives under System (owner 2026-06-21),
    /// so this is composed into `systemSection` rather than owning a section.
    private var cloudStorageRow: some View {
        SettingsRow(icon: "icloud",
                    label: "Cloud Storage",
                    chevron: true,
                    action: { vm.isCloudStorageSheetPresented = true }) {
            SettingsDetailLabel(text: cloudStorageDetail)
        }
        .accessibilityIdentifier("settings-cloud-storage")
        .accessibilityHint("Choose where encrypted Takes are stored.")
        .accessibilityValue(cloudStorageDetail)
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
            // Sync lives under System now (owner 2026-06-21).
            cloudStorageRow
            // Task 6.22 — always available, regardless of subscription status.
            // Decisions doc §5: "your data is yours, always" must hold even in
            // lapsed read-only mode. Do NOT wrap this in `ensureEntitled`.
            SettingsRow(icon: "square.and.arrow.up",
                        label: "Export Takes",
                        chevron: false,
                        action: { showExportFormatDialog = true })
                .accessibilityIdentifier("settings-export-takes")
                .accessibilityHint("Export all your Takes as a Markdown or plain-text file.")
            // Import notes (owner 2026-06-22) — reads .md/.txt from the Import folder
            // inside the configured sync folder; one file = one Take.
            SettingsRow(icon: "square.and.arrow.down",
                        label: "Import notes",
                        chevron: false,
                        action: { importNotes() })
                .accessibilityIdentifier("settings-import-notes")
                .accessibilityHint("Import .md, .txt or .rtf files from the Import folder of your sync location as new Takes.")
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

    // MARK: - Support

    /// Its own section below System (owner 2026-06-21). With no analytics or crash
    /// reporting, a prefilled mail to support is our only inbound signal.
    private var supportSection: some View {
        Section {
            SettingsRow(icon: "ladybug",
                        label: "Report an issue",
                        chevron: false,
                        action: { reportAnIssue() })
                .accessibilityIdentifier("settings-report-issue")
                .accessibilityHint("Opens a prefilled email to Catchlight support.")
        } header: {
            sectionHeader("Support")
        }
    }

    /// Open a prefilled support email (owner 2026-06-21). We collect no analytics
    /// or crash reports, so a `mailto:` with the app/OS/device stamped into the
    /// body is the entire bug-report channel — the diagnostics line saves a
    /// round-trip asking the reporter what they're running. No Take content is
    /// ever included (it's encrypted and none of our business). If no mail
    /// account is configured iOS simply no-ops the open.
    @MainActor
    private func reportAnIssue() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let subject = "Catchlight issue — v\(version) (\(build))"
        let body = """
        Describe the issue or feedback here:


        ———
        The details below help us investigate (we collect no analytics):
        App: Catchlight \(version) (\(build))
        iOS: \(UIDevice.current.systemVersion)
        Device: \(deviceModelIdentifier())
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@catchlight.app"
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }

    /// Hardware identifier (e.g. `iPhone17,1`) for the support-mail diagnostics
    /// line — `UIDevice.model` only ever returns the generic "iPhone".
    private func deviceModelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        let identifier = mirror.children.reduce(into: "") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            partial.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    @MainActor
    private func exportTakes(format: TakeExporter.Format) {
        // Reads through the live DailiesViewModel's store so the export reflects
        // whatever the user can see in the timeline (one store, one source of
        // truth). `allTakes()` already returns `createdAt` ascending; the
        // exporter re-sorts defensively.
        let takes = (try? app.dailiesVM.store.allTakes()) ?? []
        ExportCoordinator.presentShareSheet(takes: takes, format: format)
    }

    private var importAlertPresented: Binding<Bool> {
        Binding(get: { importResultMessage != nil },
                set: { if !$0 { importResultMessage = nil } })
    }

    /// Import the Import folder's `.md`/`.txt` files as new Takes (owner 2026-06-22).
    /// One file = one Take; on success a summary Take is also created. Requires a
    /// configured sync folder (the Import folder lives inside it).
    @MainActor
    private func importNotes() {
        guard let folder = ImportCoordinator.syncImportFolder() else {
            importResultMessage = "Set up Cloud Storage first — the Import folder lives inside your sync folder."
            return
        }
        defer { folder.stopAccess() }

        let outcome = (try? ImportCoordinator.parseFolder(folder.url))
            ?? ImportCoordinator.Outcome(takes: [], filesScanned: 0, skipped: 0)
        let imported = app.dailiesVM.importTakes(outcome.takes)

        guard imported > 0 else {
            importResultMessage = "No recognised markdown or text files found in the Import folder."
            return
        }
        let noun = imported == 1 ? "Take" : "Takes"
        importResultMessage = "Import successful. \(imported) \(noun) added to your timeline."
        // The auto-created summary Take (owner 2026-06-22) — a persistent record in the
        // timeline, dated now so it lands at the recent end. Terser than the alert.
        let takeMessage = "Import successful. \(imported) \(noun) added."
        app.dailiesVM.importTakes([
            Take(createdAt: Date(), modifiedAt: Date(), blocks: [.textLine(takeMessage)], isNote: true)
        ])
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
