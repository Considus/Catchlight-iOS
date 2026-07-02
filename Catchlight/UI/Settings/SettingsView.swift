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
import UniformTypeIdentifiers
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
    @AppStorage(SettingsViewModel.CreationStamp.defaultsKey) private var creationStampRaw: String = SettingsViewModel.CreationStamp.default.rawValue
    @AppStorage(SettingsViewModel.AutoCleanup.defaultsKey) private var autoCleanupRaw: String = SettingsViewModel.AutoCleanup.default.rawValue
    @AppStorage(SettingsViewModel.DefaultReminderHours.defaultsKey) private var defaultReminderHoursRaw: String = SettingsViewModel.DefaultReminderHours.default.rawValue
    @AppStorage(SettingsViewModel.SnoozeDuration.defaultsKey) private var snoozeDurationRaw: String = SettingsViewModel.SnoozeDuration.default.rawValue
    @AppStorage(SettingsViewModel.FollowUpReminders.defaultsKey) private var followUpRemindersOn: Bool = SettingsViewModel.FollowUpReminders.default

    @State private var vm = SettingsViewModel()
    /// The Import-result message; non-nil presents the confirmation alert (owner 2026-06-22).
    @State private var importResultMessage: String?
    /// Presents the Notice History sheet (D-085) — a SHIPPING feature, so this
    /// must live outside the `#if DEBUG` block (it was declared inside it, which
    /// compiled in Debug but broke every Release/Archive build — 2026-07-01).
    @State private var showNoticeHistory = false
    /// Second-device restore (D-087): the destructive warning gate, then the phrase-
    /// entry sheet. Two bools so the warning always precedes entry and each dismisses
    /// independently.
    @State private var showSecondDeviceWarning = false
    @State private var showSecondDeviceEntry = false
    /// Presents the Files document picker for the offline "Import from a file" path (D-088).
    @State private var showFileImporter = false

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
        .sheet(isPresented: $showNoticeHistory) {
            NoticeHistoryView()
        }
        .sheet(isPresented: $vm.isCloudStorageSheetPresented) {
            CloudStorageView()
        }
        .sheet(isPresented: $vm.isAboutSheetPresented) {
            AboutView()
        }
        .sheet(isPresented: $showSecondDeviceEntry) {
            SecondDeviceRestoreView()
        }
        // Second-device warning (D-087): the re-key is destructive because an onboarded
        // device already holds Takes under its current key — a new phrase can't decrypt
        // them, so they're removed. Continue only leads to phrase entry; the wipe/re-key
        // happens on Restore there (a bad phrase destroys nothing).
        .alert("Add this device to your account?", isPresented: $showSecondDeviceWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Continue", role: .destructive) { showSecondDeviceEntry = true }
        } message: {
            Text("Enter your privacy phrase to bring your Takes onto this device. Any Takes stored only on this device will be removed. To keep a copy first, cancel and use Export Takes (Markdown), or make sure they're already in your cloud folder.")
        }
        // Offline "Import from a file" (D-088): pick any exported file from Files.
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: Self.importableFileTypes,
                      allowsMultipleSelection: true) { result in
            importFromFile(result)
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
    /// Styled as the Dailies page heading (owner 2026-06-29): Cormorant Garamond
    /// ROMAN 24pt, kerned, CENTRED and upper-cased to match DAILIES/SEQUENCE/etc.
    private var titleRow: some View {
        Text("SETTINGS")
            .pageHeadingStyle()
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 4, trailing: 20))
            .listRowSeparator(.hidden)
            .accessibilityLabel("Settings")
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

            // Created-at stamp — Off / In the editor / Always (owner 2026-07-01).
            menuPickerRow(icon: "calendar",
                          label: "Creation date",
                          accessibilityLabel: "Show creation date",
                          selectionLabel: creationStampBinding.wrappedValue.label) {
                Picker("Creation date", selection: creationStampBinding) {
                    ForEach(SettingsViewModel.CreationStamp.allCases) { option in
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

    /// Shared row for a menu-style `Picker`. Uses the app-wide `SelectorRow` as the
    /// menu's label (owner 2026-06-29 standardisation) so the Settings pickers and the
    /// reminder Quick Set share ONE selector look + 44pt height. The chooser is the
    /// passed `picker()`, presented inside a `Menu`; the value shows in the row.
    private func menuPickerRow<P: View>(icon: String,
                                        label: String,
                                        accessibilityLabel: String,
                                        selectionLabel: String,
                                        @ViewBuilder picker: () -> P) -> some View {
        Menu {
            picker().labelsHidden()
        } label: {
            SelectorRow(icon: icon, label: label, value: selectionLabel)
        }
        .tint(Color.ckTextSecondary)
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

    private var creationStampBinding: Binding<SettingsViewModel.CreationStamp> {
        Binding(
            get: { SettingsViewModel.CreationStamp(rawValue: creationStampRaw) ?? .default },
            set: { creationStampRaw = $0.rawValue }
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

            // Follow-up reminders (owner 2026-06-28): when on, a fired reminder you don't
            // act on re-nudges at the Snooze interval until you mark it done. Default on.
            Toggle(isOn: $followUpRemindersOn) {
                HStack(spacing: 14) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Color.ckAccent)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Follow-up reminders")
                            .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                            .foregroundStyle(Color.ckTextPrimary)
                        Text("Re-nudge until you mark it done")
                            .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .caption))
                            .foregroundStyle(Color.ckTextSecondary)
                    }
                }
            }
            .tint(Color.ckEmber)
            .frame(minHeight: 52)
            .listRowBackground(Color.ckSurface)
            .accessibilityIdentifier("follow-up-reminders-toggle")
            .accessibilityHint("When on, a reminder you don't act on nudges again until you mark it done.")
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

            // Second device (D-087) — re-key this device to another account's phrase
            // to pull its Takes from the shared cloud folder. Destructive (it replaces
            // this device's account), so a warning gates entry.
            SettingsRow(icon: "iphone.and.arrow.forward",
                        label: "Second device",
                        chevron: true,
                        action: { showSecondDeviceWarning = true })
                .accessibilityIdentifier("settings-second-device")
                .accessibilityHint("Restore your Takes onto this device from your privacy phrase.")
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
    /// running in local-only mode. Re-reads on re-render — the sub-sheet's
    /// dismissal re-renders this row, which is what picks up a folder change
    /// (the `scenePhase` handler only refreshes notification status; comment
    /// corrected 2026-07-01).
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
            SettingsRow(icon: "calendar",
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
                        action: { exportTakes() })
                .accessibilityIdentifier("settings-export-takes")
                .accessibilityHint("Export all your Takes as a Markdown file.")
            // Import notes (owner 2026-06-22) — reads .md/.txt from the Import folder
            // inside the configured sync folder; one file = one Take.
            SettingsRow(icon: "square.and.arrow.down",
                        label: "Import notes",
                        chevron: false,
                        action: { importNotes() })
                .accessibilityIdentifier("settings-import-notes")
                .accessibilityHint("Import .md, .txt or .rtf files from the Import folder of your sync location as new Takes.")
            // Import from a file (D-088) — the offline route: pick an exported file from
            // anywhere in Files (On My iPhone, AirDrop, etc.), no cloud folder needed. A
            // Catchlight export splits back into its Takes; a foreign note imports as one.
            SettingsRow(icon: "doc.badge.plus",
                        label: "Import from a file",
                        chevron: false,
                        action: { showFileImporter = true })
                .accessibilityIdentifier("settings-import-file")
                .accessibilityHint("Pick a .md, .txt or .rtf file from Files to import as Takes — no cloud folder needed.")
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
    /// reporting, the prefilled web report form + the diagnostics export are our
    /// only inbound signal (D-091).
    private var supportSection: some View {
        Section {
            SettingsRow(icon: "ladybug",
                        label: "Report an issue",
                        chevron: false,
                        action: { reportAnIssue() })
                .accessibilityIdentifier("settings-report-issue")
                .accessibilityHint("Opens the Catchlight report form, prefilled with your app and iOS version.")

            // Notice History (D-085): the recent sync / storage / conflict / quarantine
            // notices, so an auto-dismissed banner isn't lost.
            SettingsRow(icon: "list.bullet.rectangle",
                        label: "Notice History",
                        chevron: true,
                        action: { showNoticeHistory = true })
                .accessibilityIdentifier("settings-notice-history")
                .accessibilityHint("Recent sync, storage and conflict notices.")

            // Export diagnostics (D-085): a content-free plain-text log to attach to a report.
            SettingsRow(icon: "square.and.arrow.up",
                        label: "Export diagnostics",
                        chevron: false,
                        action: { ExportCoordinator.presentDiagnostics(DiagnosticsLog.shared.exportText()) })
                .accessibilityIdentifier("settings-export-diagnostics")
                .accessibilityHint("Shares a plain-text diagnostics log to attach to a report.")
        } header: {
            sectionHeader("Support")
        }
    }

    /// Open the web Report-an-issue form (`catchlight.app/support`), pre-filled
    /// with the platform, app version (+build) and iOS version via query params
    /// so the report carries the basics without the user retyping them (D-091).
    /// Replaces the old `mailto:` — one web form is the single cross-platform
    /// intake. The form lets the user optionally attach the content-free
    /// diagnostics export (the "Export diagnostics" row below, which the form
    /// also points to). No Take content is ever sent. If the URL can't be built
    /// (it always can) we simply no-op.
    @MainActor
    private func reportAnIssue() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let appValue = build.isEmpty ? version : "\(version) (\(build))"
        var components = URLComponents(string: "https://catchlight.app/support/")
        components?.queryItems = [
            URLQueryItem(name: "platform", value: "iOS"),
            URLQueryItem(name: "app", value: appValue),
            URLQueryItem(name: "os", value: UIDevice.current.systemVersion),
        ]
        guard let url = components?.url else { return }
        UIApplication.shared.open(url)
    }

    @MainActor
    private func exportTakes() {
        // Reads through the live DailiesViewModel's store so the export reflects
        // whatever the user can see in the timeline (one store, one source of
        // truth). `allTakes()` already returns `createdAt` ascending; the
        // exporter re-sorts defensively. Markdown only (owner 2026-07-02).
        let takes = (try? app.dailiesVM.store.allTakes()) ?? []
        ExportCoordinator.presentShareSheet(takes: takes)
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
        // Import CREATES Takes, so it sits behind the subscription like every
        // other create/edit surface (owner decision 2026-07-01 — Export stays
        // free by design: users can always get their data OUT, but a lapsed
        // read-only user must not mint unlimited new Takes via the Import folder).
        guard app.ensureEntitled() else { return }
        guard let folder = ImportCoordinator.syncImportFolder() else {
            importResultMessage = "Set up Cloud Storage first — the Import folder lives inside your sync folder."
            return
        }
        defer { folder.stopAccess() }

        // Distinguish "couldn't read the folder" from "read it, found nothing"
        // (2026-07-01) — the old `try?` flattened an unreadable folder into the
        // misleading "no files found" message.
        let outcome: ImportCoordinator.Outcome
        do {
            outcome = try ImportCoordinator.parseFolder(folder.url)
        } catch {
            importResultMessage = "The Import folder couldn't be read. Check your cloud folder in Settings → Cloud Storage and try again."
            return
        }
        let imported = app.dailiesVM.importTakes(outcome.takes)

        guard imported > 0 else {
            importResultMessage = "No recognised markdown or text files found in the Import folder."
            return
        }
        announceImport(imported)
    }

    /// File types the offline picker accepts — Markdown, plain text, and RTF.
    private static let importableFileTypes: [UTType] = {
        var types: [UTType] = [.plainText, .text, .rtf]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let markdown = UTType(filenameExtension: "markdown") { types.append(markdown) }
        return types
    }()

    /// Import one or more files picked from Files (offline path, D-088). No cloud folder
    /// needed — a Catchlight export splits into its Takes; each foreign note imports as
    /// one, so picking several separate note files yields one Take per file.
    @MainActor
    private func importFromFile(_ result: Result<[URL], Error>) {
        guard app.ensureEntitled() else { return }
        guard case .success(let urls) = result, !urls.isEmpty else {
            if case .failure = result {
                importResultMessage = "Couldn't open those files. Please try again."
            }
            return
        }
        let takes = urls.flatMap { ImportCoordinator.parseSingleFile($0) }
        let imported = app.dailiesVM.importTakes(takes)
        guard imported > 0 else {
            importResultMessage = "No notes to import from your selection."
            return
        }
        announceImport(imported)
    }

    /// Success feedback shared by both import paths: the alert while Settings is open,
    /// plus a terse summary Take dated now so a record lands at the recent end of the
    /// timeline (owner 2026-06-22).
    @MainActor
    private func announceImport(_ imported: Int) {
        let noun = imported == 1 ? "Take" : "Takes"
        importResultMessage = "Import successful. \(imported) \(noun) added to your timeline."
        app.dailiesVM.importTakes([
            Take(createdAt: Date(), modifiedAt: Date(),
                 blocks: [.textLine("Import successful. \(imported) \(noun) added.")], isNote: true)
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
        // `bell.badge` (not plain `bell`) so this matches the Follow-up reminders row's
        // dotted bell — one bell language across the two reminder rows (owner 2026-06-29).
        SettingsRow(icon: "bell.badge", label: "Notifications") {
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
