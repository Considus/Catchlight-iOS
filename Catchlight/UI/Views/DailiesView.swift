//
//  DailiesView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  The homepage timeline — the ONE surface (dock redesign 2026-06-10). A vertical
//  scroll of TakeRowViews threaded by a 2px spine aligned to each circle's centre.
//  The Obie (if any) is pinned at the top with a small gap before the regular
//  list — ALWAYS, even when it doesn't match the active filter. Month markers
//  ghost in only while scrolling (they are never static). First-launch empty
//  state is a single Fog line.
//
//  Live filtering (2026-06-10): the dock's FILTERING toggles and SEARCHING query
//  produce `ui.activeTimelineFilter`; the non-Obie rows are narrowed through
//  `SequenceFilter.matches` before month-grouping. When a filter is active but
//  nothing matches, a quiet "Nothing here yet." line replaces the grouped list.
//  In FILTERING, tapping empty timeline background (not rows/Irises) exits to
//  RESTING and clears all filters.
//
//  Petal fan and edit surfaces are presented by the parent RootView via the shared
//  UIState, so this view stays focused on layout + the spine geometry.
//
//  Task 3.9: Error and edge-case states — three quiet, non-blocking strips are
//  inserted above the timeline via `.safeAreaInset(edge: .top)`: storage error,
//  sync error, and quarantine notice. All share the conflict-banner geometry
//  (44pt, 16pt horizontal pad, same font) so the visual vocabulary stays consistent.
//

import SwiftUI
import CatchlightCore

struct DailiesView: View {
    @Environment(DailiesViewModel.self) private var vm
    @Environment(UIState.self) private var ui
    @Environment(AppModel.self) private var app
    @Environment(FirstRunOrientationState.self) private var orientation
    @Environment(ConflictQueue.self) private var conflicts
    @Environment(\.colorScheme) private var scheme

    /// Horizontal centre of the circles == x of the spine. Matches the dock's Add
    /// button so the spine terminates there (handled in RootView's layout).
    private let spineX = CatchlightLayout.spineLeading

    @State private var scrolling = false
    @State private var scrollHideWork: DispatchWorkItem?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.ckBackground.ignoresSafeArea()

            // The spine: a full-height hairline behind the rows, at the circle centre.
            Rectangle()
                .fill(Color.ckSpine)
                .frame(width: CatchlightLayout.spineWidth)
                .frame(maxHeight: .infinity)
                .offset(x: spineX - CatchlightLayout.spineWidth / 2)
                .accessibilityHidden(true)

            // A first-launch-empty store shows the Fog line; but when a dock
            // filter is active the timeline (with its own filter-empty line)
            // always wins, so the background-tap exit remains available.
            if vm.isEmpty && activeFilter.isEmpty {
                emptyState
            } else {
                timeline
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { topStrips }
        .animation(.easeInOut(duration: 0.2), value: conflicts.pending.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: vm.lastError)
        .animation(.easeInOut(duration: 0.2), value: app.lastSyncError)
        .animation(.easeInOut(duration: 0.2), value: app.quarantinedCount)
        .onAppear {
            vm.reload()
            // Kick off the first-run orientation tour the first time the main app
            // is visible. No-op once the tour has started or completed.
            orientation.beginIfNeeded()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Text("Your first take is waiting.")
            .font(CatchlightFont.ui(.light, size: 17, relativeTo: .body))
            .foregroundStyle(Color.ckTextSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Your first take is waiting.")
    }

    // MARK: - Timeline

    /// Stack of quiet, non-blocking notice strips inserted above the timeline.
    /// Order (top → bottom): conflicts (Task 6.15), storage error, sync error,
    /// quarantine notice (Task 3.9). All share the conflict banner's geometry.
    private var topStrips: some View {
        VStack(spacing: 0) {
            conflictBanner
            lapseBanner
            storageErrorStrip
            syncErrorStrip
            quarantineNoticeStrip
        }
    }

    /// Read-only banner shown while the user is `.lapsed` (Tasks 6.20 / 6.22).
    /// Offers two parallel actions: resubscribe (opens the paywall) and export
    /// (subscription-independent — never gated). This is the lapse-mode entry
    /// point the decisions doc §5 specifically calls out.
    @ViewBuilder
    private var lapseBanner: some View {
        if app.subscriptionStatus == .lapsed {
            HStack(spacing: 10) {
                Image(systemName: "lock")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.ckEmber)
                    .accessibilityHidden(true)
                Text("Read-only — your data is still yours.")
                    .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Color.ckTextPrimary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button {
                    let takes = (try? vm.store.allTakes()) ?? []
                    ExportCoordinator.presentShareSheet(takes: takes)
                } label: {
                    Text("Export")
                        .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .body))
                        .foregroundStyle(Color.ckEmber)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lapse-banner-export")
                .accessibilityLabel("Export your Takes")
                Button {
                    ui.isPaywallPresented = true
                } label: {
                    Text("Subscribe")
                        .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .body))
                        .foregroundStyle(Color.ckEmber)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lapse-banner-subscribe")
                .accessibilityLabel("Resubscribe to Catchlight")
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(scheme == .dark
                        ? Color.ckGlow.opacity(0.12)
                        : Color.ckEmber.opacity(0.15))
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }

    /// Quiet amber banner at the top of the timeline shown while conflicts await
    /// resolution. Inserted via `.safeAreaInset(edge: .top)` so the timeline rows
    /// shift down cleanly rather than overlapping. (Task 6.15)
    @ViewBuilder
    private var conflictBanner: some View {
        let count = conflicts.pending.count
        if count > 0 {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.ckEmber)
                    .accessibilityHidden(true)
                // L10N: pluralisation done inline via `count == 1`. Future
                // pass should move to a Stringsdict / .xcstrings plural rule
                // — many locales don't pluralise on the singular/plural axis
                // alone (e.g. Polish, Arabic). Tracked but not blocking.
                Text("\(count) take\(count == 1 ? "" : "s") changed on another device.")
                    .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Color.ckTextPrimary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button {
                    ui.isConflictSheetPresented = true
                } label: {
                    Text("Review")
                        .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .body))
                        .foregroundStyle(Color.ckEmber)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(count) Take\(count == 1 ? "" : "s") changed on another device. Double-tap to review.")
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(scheme == .dark
                        ? Color.ckGlow.opacity(0.12)
                        : Color.ckEmber.opacity(0.15))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Task 3.9 error strips

    /// Shared chrome for every non-blocking strip on the timeline. Identical
    /// geometry to the conflict banner; only colour, icon and copy differ.
    private func noticeStrip(icon: String,
                             text: String,
                             tint: Color,
                             background: Color,
                             accessibilityLabel: String,
                             onDismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .subheadline))
                .foregroundStyle(Color.ckTextPrimary)
                .lineLimit(2)
                // Compose the message + Dismiss button into one VO element so the
                // user hears the full notice and then lands on the action, instead
                // of stepping through "exclamationmark, body text, Dismiss" hops.
                .accessibilityLabel("\(accessibilityLabel). \(text)")
                .accessibilityAddTraits(.isStaticText)
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Text("Dismiss")
                    .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .body))
                    .foregroundStyle(tint)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss \(accessibilityLabel)")
            .accessibilityHint("Double-tap to dismiss this notice.")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity)
        .background(background)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Storage-failure strip — fired by failures bubbled through `DailiesViewModel.lastError`.
    /// Auto-dismisses after 5 seconds.
    @ViewBuilder
    private var storageErrorStrip: some View {
        if let message = vm.lastError {
            noticeStrip(
                icon: "exclamationmark.circle",
                text: message,
                tint: Color.ckRuby,
                background: Color.ckRuby.opacity(0.12),
                accessibilityLabel: "storage error",
                onDismiss: { vm.clearError() }
            )
            .task(id: message) {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if vm.lastError == message { vm.clearError() }
            }
        }
    }

    /// Sync-failure strip — friendly summary set by `AppModel.reportSyncError`.
    /// Auto-dismisses after 8 seconds (longer than storage because the user has
    /// less context for what's happening in the background).
    @ViewBuilder
    private var syncErrorStrip: some View {
        if let message = app.lastSyncError {
            noticeStrip(
                icon: "exclamationmark.circle",
                text: message,
                tint: Color.ckRuby,
                background: Color.ckRuby.opacity(0.12),
                accessibilityLabel: "sync error",
                onDismiss: { app.clearSyncError() }
            )
            .task(id: message) {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if app.lastSyncError == message { app.clearSyncError() }
            }
        }
    }

    /// Quarantine notice — surfaces when `pullInbound()` skipped one or more
    /// Takes due to HMAC failure. UUIDs are NOT exposed; only a count.
    @ViewBuilder
    private var quarantineNoticeStrip: some View {
        let count = app.quarantinedCount
        if count > 0 {
            let copy = "\(count) Take\(count == 1 ? "" : "s") couldn't be verified and \(count == 1 ? "was" : "were") skipped."
            noticeStrip(
                icon: "lock.slash",
                text: copy,
                tint: Color.ckRuby,
                background: Color.ckRuby.opacity(0.12),
                accessibilityLabel: "quarantine notice",
                onDismiss: { app.clearQuarantineNotice() }
            )
        }
    }

    private var timeline: some View {
        // ScrollViewReader wraps the timeline so the Spotlight deep-link handler
        // (Task 6.19) can scroll programmatically to a target Take id.
        ScrollViewReader { proxy in
            ScrollView {
                // Track scroll offset to ghost month markers in/out.
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: geo.frame(in: .named("dailies")).minY
                    )
                }
                .frame(height: 0)

                LazyVStack(alignment: .leading, spacing: 0) {
                    // Pinned Obie — ALWAYS shown, even when it doesn't match
                    // the active filter (dock redesign 2026-06-10).
                    if let obie = vm.obie {
                        row(for: obie, isFirst: true)
                            .id(obie.id)
                        Color.clear.frame(height: 18)   // gap below the Obie
                    }

                    // Filter active but no non-Obie Take matches: quiet line in
                    // place of the grouped list (NOT the first-run empty state).
                    if !activeFilter.isEmpty && filteredTakes.isEmpty {
                        Text("Nothing here yet.")
                            .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                            .foregroundStyle(Color.ckTextSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                            .accessibilityIdentifier("timeline-filter-empty")
                            .accessibilityLabel("Nothing here yet.")
                    }

                    ForEach(Array(monthGroups.enumerated()), id: \.element.month) { groupIndex, group in
                        // Ghosted month marker — appears only while scrolling.
                        Text(group.month)
                            .font(CatchlightFont.ui(.medium, size: 12, relativeTo: .caption))
                            .foregroundStyle(Color.ckTextSecondary)
                            .padding(.leading, spineX + 22)
                            .padding(.vertical, 6)
                            .opacity(scrolling ? 0.8 : 0)
                            .animation(.easeInOut(duration: 0.25), value: scrolling)
                            .accessibilityHidden(!scrolling)

                        ForEach(Array(group.takes.enumerated()), id: \.element.id) { takeIndex, take in
                            // The very first row across all months (when there's no Obie)
                            // anchors the Iris hint tooltip in Hint 2.
                            let isFirstOverall = (vm.obie == nil) && groupIndex == 0 && takeIndex == 0
                            row(for: take, isFirst: isFirstOverall)
                                .id(take.id)
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 120)   // clearance for the dock
                .frame(maxWidth: .infinity, alignment: .leading)
                // FILTERING exit: tapping empty timeline background (not rows /
                // Irises — they stay fully interactive and win hit-testing)
                // returns the dock to RESTING and clears all filters. A
                // .background tap catcher (not an overlay) so row gestures and
                // scrolling are unaffected; attached only in FILTERING.
                .background {
                    if ui.dockMode == .filtering {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { ui.exitToResting() }
                            .accessibilityLabel("Clear filters")
                            .accessibilityHint("Double-tap the timeline background to clear all filters.")
                    }
                }
            }
            .coordinateSpace(name: "dailies")
            .onPreferenceChange(ScrollOffsetKey.self) { _ in markScrolling() }
            // `initial: true` (2026-06-10): when the Spotlight tap arrives from
            // another tab, this view is created with the target ALREADY set, so
            // a change-only observer never fired — no scroll, and the highlight
            // never cleared (blocking re-taps of the same result).
            .onChange(of: ui.spotlightTargetTakeID, initial: true) { _, newTarget in
                // Task 6.19 — Spotlight tap deep-link. Scroll the matching row
                // into view and let the row's own opacity flash do the rest.
                guard let id = newTarget else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(id, anchor: .center)
                }
                // Clear the target after the flash has time to start so a
                // subsequent tap on the same item re-triggers the highlight.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    if ui.spotlightTargetTakeID == id { ui.spotlightTargetTakeID = nil }
                }
            }
        }
    }

    private func row(for take: Take, isFirst: Bool = false) -> some View {
        TakeRowView(
            take: take,
            onTapCircle: {
                // Hint 2 is dismissed by tapping any Iris.
                orientation.didTapIris()
                ui.openPetalFan(for: take)
            },
            onLongPressCircle: {
                // Hint 4: arm the Obie introduction tooltip on the first long-press.
                // The actual designation still proceeds — the tooltip provides
                // context "before the action takes effect" (and persists over the
                // confirmation alert when one Obie already exists).
                orientation.triggerObieIntro()
                // Task 6.20: Obie designation is a mutation — gate it.
                guard app.ensureEntitled() else { return }
                vm.designateObie(take, replaceExisting: false)
            },
            onTapText: {
                // Task 6.20: editing is gated for lapsed users — paywall opens instead.
                guard app.ensureEntitled() else { return }
                ui.openEditor(for: take)
            },
            // Delete / complete paths (2026-06-10). Previously `vm.delete` had
            // no UI caller at all and nothing ever set `isComplete` — rows could
            // only accumulate, and the strikethrough/"complete" rendering was
            // unreachable. The row exposes both via a context menu on its text
            // column (kept off the circle so the Obie long-press still wins).
            onToggleComplete: {
                guard app.ensureEntitled() else { return }
                vm.toggleComplete(take)
            },
            onDelete: {
                guard app.ensureEntitled() else { return }
                vm.delete(take)
            }
        )
        .background(
            // Task 6.19 — brief flash when this row is the Spotlight deep-link
            // target. Uses the ember accent at low opacity so it reads as a
            // gentle pulse, not a notification.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.ckEmber.opacity(ui.spotlightTargetTakeID == take.id ? 0.18 : 0))
                .animation(.easeInOut(duration: 0.4), value: ui.spotlightTargetTakeID)
        )
        .padding(.leading, spineX - CatchlightLayout.circleDiameter / 2
                 - (CatchlightLayout.minTouchTarget - CatchlightLayout.circleDiameter) / 2)
        .padding(.trailing, 20)
        .overlay(alignment: .topLeading) {
            if isFirst && orientation.showIrisHint {
                OrientationTooltip(text: "Tap the Iris to shape this Take.", arrowEdge: .leading)
                    .fixedSize()
                    .offset(x: spineX + CatchlightLayout.circleDiameter, y: -4)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Live filter (dock redesign 2026-06-10)

    /// The filter the dock's current state describes (empty in RESTING).
    private var activeFilter: SequenceFilter { ui.activeTimelineFilter }

    /// Non-Obie Takes narrowed through the live filter, newest-first order
    /// preserved from the VM. The Obie is pinned separately and never filtered.
    private var filteredTakes: [Take] {
        let filter = activeFilter
        guard !filter.isEmpty else { return vm.takes }
        return vm.takes.filter { filter.matches($0) }
    }

    // MARK: - Month grouping

    private struct MonthGroup { let month: String; let takes: [Take] }

    /// Cached formatter — `DateFormatter` construction is expensive and this
    /// property is evaluated on every body pass (including the scroll-driven
    /// `scrolling` state toggles).
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    private var monthGroups: [MonthGroup] {
        var order: [String] = []
        var map: [String: [Take]] = [:]
        for take in filteredTakes {
            let key = Self.monthFormatter.string(from: take.createdAt)
            if map[key] == nil { order.append(key); map[key] = [] }
            map[key]?.append(take)
        }
        return order.map { MonthGroup(month: $0, takes: map[$0] ?? []) }
    }

    // MARK: - Scroll ghosting

    private func markScrolling() {
        if !scrolling { scrolling = true }
        scrollHideWork?.cancel()
        let work = DispatchWorkItem { scrolling = false }
        scrollHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

#Preview("Dailies — Night (populated)") {
    let store = InMemoryTakeStore()
    for t in SeedTakes.make() { try? store.upsert(t) }
    let app = AppModel.preview(store: store, onboarded: true)
    return DailiesView()
        .environment(app)
        .environment(app.dailiesVM)
        .environment(app.ui)
        .environment(app.orientation)
        .environment(app.conflictQueue)
        .preferredColorScheme(.dark)
}

#Preview("Dailies — Daylight (populated)") {
    let store = InMemoryTakeStore()
    for t in SeedTakes.make() { try? store.upsert(t) }
    let app = AppModel.preview(store: store, onboarded: true)
    return DailiesView()
        .environment(app)
        .environment(app.dailiesVM)
        .environment(app.ui)
        .environment(app.orientation)
        .environment(app.conflictQueue)
        .preferredColorScheme(.light)
}

#Preview("Dailies — empty") {
    let app = AppModel.preview(store: InMemoryTakeStore(), onboarded: true)
    return DailiesView()
        .environment(app)
        .environment(app.dailiesVM)
        .environment(app.ui)
        .environment(app.orientation)
        .environment(app.conflictQueue)
        .preferredColorScheme(.dark)
}
