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

    /// Container width, captured by the background GeometryReader on the body
    /// ZStack; drives `spineX`.
    @State private var containerWidth: CGFloat = 0


    /// Horizontal centre of the circles == x of the spine == the dock's Add
    /// button centre. Both derive from `CatchlightLayout.spineX(containerWidth:)`
    /// — the same four-equal-columns formula BottomDockView lays out with — so
    /// the spine sits exactly on the + vertical at every device width
    /// (2026-06-10 fix: the previous fixed 32pt constant never matched the
    /// dock). The screen width stands in before the first layout pass so the
    /// spine doesn't flash at a wrong x.
    private var spineX: CGFloat {
        CatchlightLayout.spineX(
            containerWidth: containerWidth > 0 ? containerWidth : UIScreen.main.bounds.width
        )
    }

    @State private var scrolling = false
    @State private var scrollHideWork: DispatchWorkItem?
    /// The first row's top Y in the "dailies" space, published by the first row so
    /// the spine starts exactly at the first Iris (handles the pinned-Obie vs
    /// invisible-month-marker offset). `nil` until the first layout pass.
    @State private var firstRowTop: CGFloat?

    /// Where the spine's top edge sits: the first Iris's top edge. Prefer the
    /// MEASURED first-row top; before the first layout, fall back to the constant
    /// estimate (no month marker). Row top → card top (+6, the Iris straddles the
    /// top edge so its centre is there) → Iris top (−radius).
    private var spineTopInset: CGFloat {
        let radius = CatchlightLayout.circleDiameter / 2
        if let t = firstRowTop, t.isFinite {
            return max(0, t + 6 - radius)
        }
        return deviceTopInset + CatchlightLayout.headingClearance + 6 - radius
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.ckBackground.ignoresSafeArea()

            // The spine: a hairline behind the rows, at the circle centre. It
            // STARTS at the first Iris's top edge (HiFi §1 "the spine terminates at
            // the first Take") rather than the screen top — a full-height line poked
            // up into the gap below the DAILIES heading. First Iris centre = the
            // timeline's top content pad (deviceTopInset + headingClearance) + the
            // row's 6pt vertical pad; the top edge is one Iris radius higher. The
            // bottom runs on toward the Add button, covered by the dock fade (HiFi).
            Rectangle()
                .fill(Color.ckSpine)
                .frame(width: CatchlightLayout.spineWidth)
                .frame(maxHeight: .infinity)
                .padding(.top, spineTopInset)
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

            // Pinned page heading + top fade (cosmetic baseline 2026-06-11):
            // a plain overlay child, NOT .safeAreaInset — in this full-bleed
            // hierarchy (.ignoresSafeArea(.container) at the app root) a top
            // safeAreaInset here desynced hit-testing and killed the dock's
            // keyboard avoidance (Flow 5 regression, 2026-06-11). The heading
            // dodges the status bar itself via deviceTopInset. Takes scroll
            // under the solid block and dissolve beneath the 12pt fade.
            heading
        }
        .background {
            // Capture the layout width (NOT UIScreen) so spineX matches the
            // dock, which is laid out in the same safe-area coordinate space —
            // and the remaining top safe-area inset for the pinned heading.
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in containerWidth = width }
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

    // MARK: - Heading

    /// The device's top safe-area inset, captured at the WINDOW ROOT in
    /// CatchlightApp and delivered via the environment. The app root runs
    /// full-bleed (`.ignoresSafeArea(.container)` — the dock design), so the
    /// local safe-area plumbing reports zero here and the heading must dodge
    /// the status bar / Dynamic Island itself.
    ///
    /// History (2026-06-11): do NOT read UIKit window state for this —
    /// `keyWindow` per-body flapped when the keyboard window became key
    /// (killed dock hit-testing + keyboard avoidance); a `static let`
    /// UIApplication read trapped in dispatch_once recursion (launch SIGILL).
    /// The root-GeometryReader environment value is the safe source.
    @Environment(\.deviceTopInset) private var deviceTopInset

    /// The device's BOTTOM safe-area inset (home-indicator zone), captured at the
    /// window root (section 4 / D-041). Used to lift the timeline's last-row
    /// dock clearance so the final Take still clears the now-raised dock.
    @Environment(\.deviceBottomInset) private var deviceBottomInset

    /// The page title follows the activity: DAILIES · SEQUENCE · SEARCH.
    private var headingTitle: String {
        switch ui.dockMode {
        case .resting:   return "DAILIES"
        case .filtering: return "SEQUENCE"
        case .searching: return "SEARCH"
        }
    }

    /// Solid background behind the title, then a 12pt fade hugging it (kept
    /// tight so the pinned Obie's circle is clear of it at rest).
    private var heading: some View {
        VStack(spacing: 0) {
            HStack {
                Text(headingTitle)
                    // ROMAN (upright) display face — section 3. The page heading
                    // is Cormorant Garamond Light ROMAN, not the italic display
                    // cut. Take body text stays italic via `display(size:)`.
                    .font(CatchlightFont.displayRoman(size: 20, relativeTo: .title3))
                    .kerning(1.6)
                    .foregroundStyle(Color.ckTextPrimary)
                    .id(headingTitle)
                    .transition(.opacity)
                Spacer()
            }
            .padding(.leading, spineX + 22)
            .padding(.top, deviceTopInset + 14)
            .padding(.bottom, 2)
            .background(Color.ckBackground)
            LinearGradient(
                colors: [Color.ckBackground, Color.ckBackground.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 12)
        }
        .animation(.easeInOut(duration: 0.18), value: headingTitle)
        .allowsHitTesting(false)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(headingTitle.capitalized)
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
                    .foregroundStyle(Color.ckAccent)
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
                        .foregroundStyle(Color.ckAccent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lapse-banner-export")
                .accessibilityLabel("Export your Takes")
                Button {
                    ui.isPaywallPresented = true
                } label: {
                    Text("Subscribe")
                        .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .body))
                        .foregroundStyle(Color.ckAccent)
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
                    .foregroundStyle(Color.ckAccent)
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
                        .foregroundStyle(Color.ckAccent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(count) Take\(count == 1 ? "" : "s") changed on another device. Double-tap to review.")
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
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
                            // .month — 11pt medium, 0.08em tracking (matches the
                            // DAILIES heading kerning; D-042, was 12pt untracked).
                            .font(CatchlightFont.ui(.medium, size: 11, relativeTo: .caption))
                            .kerning(0.88)
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
                // Section 4 / D-041 — inset-aware on BOTH edges (the app runs
                // full-bleed, so these manual paddings are the only safe-area
                // correction). Top: clear the pinned heading + its 12pt fade on
                // large-inset devices (was a fixed 52 that ignored the inset, so
                // the first Take tucked under the fade on iPhone 17 / iOS 26.5.1).
                // Bottom: lift the last-row clearance by the home-indicator inset
                // so it still clears the now-raised dock.
                .padding(.top, deviceTopInset + CatchlightLayout.headingClearance)
                .padding(.bottom, CatchlightLayout.dockClearance + deviceBottomInset)
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
            .onPreferenceChange(FirstRowTopKey.self) { firstRowTop = $0.isFinite ? $0 : nil }
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
            onTapCircle: { irisCentre in
                // Hint 2 is dismissed by tapping any Iris.
                orientation.didTapIris()
                // Section 8 — bloom the fan in place at the tapped Iris (window
                // coords match the full-screen overlay space). The .zero fallback
                // (screen centre) only survives as a last resort.
                ui.openPetalFan(for: take, origin: irisCentre)
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
        // The row's leading edge IS the card's leading edge — `cardSpineInset`
        // left of the spine, so the card covers the spine and the Iris nests in its
        // corner (TakeRowView offsets the Iris back onto the spine). Independent of
        // the Iris diameter (was derived from circleDiameter, which moved the card
        // when the Iris grew).
        .padding(.leading, spineX - CatchlightLayout.cardSpineInset)
        .padding(.trailing, 20)
        .background(alignment: .top) {
            // The first row publishes its top Y (shared "dailies" space) so the
            // spine starts exactly at the first Iris — whether that's the pinned
            // Obie or a row sitting under an invisible month marker.
            if isFirst {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: FirstRowTopKey.self,
                        value: geo.frame(in: .named("dailies")).minY
                    )
                }
            }
        }
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

/// The first timeline row's top Y (in the "dailies" space) — drives where the spine
/// begins. Only the `isFirst` row publishes; `min` keeps the topmost if more than
/// one ever reports during a transition. `.infinity` default ⇒ "not measured yet".
private struct FirstRowTopKey: PreferenceKey {
    static let defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
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
