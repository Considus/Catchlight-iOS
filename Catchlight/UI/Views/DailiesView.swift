//
//  DailiesView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  The homepage timeline. A vertical scroll of TakeRowViews threaded by a 2px spine
//  aligned to each circle's centre. The Obie (if any) is pinned at the top with a
//  small gap before the regular list. Month markers ghost in only while scrolling
//  (they are never static). First-launch empty state is a single Fog line.
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

            if vm.isEmpty {
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
            storageErrorStrip
            syncErrorStrip
            quarantineNoticeStrip
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
                .accessibilityLabel("Review sync conflicts")
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
        ScrollView {
            // Track scroll offset to ghost month markers in/out.
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ScrollOffsetKey.self,
                    value: proxy.frame(in: .named("dailies")).minY
                )
            }
            .frame(height: 0)

            LazyVStack(alignment: .leading, spacing: 0) {
                // Pinned Obie.
                if let obie = vm.obie {
                    row(for: obie, isFirst: true)
                    Color.clear.frame(height: 18)   // gap below the Obie
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
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 120)   // clearance for the dock
        }
        .coordinateSpace(name: "dailies")
        .onPreferenceChange(ScrollOffsetKey.self) { _ in markScrolling() }
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
                vm.designateObie(take, replaceExisting: false)
            },
            onTapText: { ui.openEditor(for: take) }
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

    // MARK: - Month grouping

    private struct MonthGroup { let month: String; let takes: [Take] }

    private var monthGroups: [MonthGroup] {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        var order: [String] = []
        var map: [String: [Take]] = [:]
        for take in vm.takes {
            let key = f.string(from: take.createdAt)
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
    static var defaultValue: CGFloat = 0
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
