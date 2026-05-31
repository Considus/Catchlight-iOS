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

import SwiftUI
import CatchlightCore

struct DailiesView: View {
    @Environment(DailiesViewModel.self) private var vm
    @Environment(UIState.self) private var ui
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
        .onAppear { vm.reload() }
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
                    row(for: obie)
                    Color.clear.frame(height: 18)   // gap below the Obie
                }

                ForEach(monthGroups, id: \.month) { group in
                    // Ghosted month marker — appears only while scrolling.
                    Text(group.month)
                        .font(CatchlightFont.ui(.medium, size: 12, relativeTo: .caption))
                        .foregroundStyle(Color.ckTextSecondary)
                        .padding(.leading, spineX + 22)
                        .padding(.vertical, 6)
                        .opacity(scrolling ? 0.8 : 0)
                        .animation(.easeInOut(duration: 0.25), value: scrolling)
                        .accessibilityHidden(!scrolling)

                    ForEach(group.takes) { take in
                        row(for: take)
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 120)   // clearance for the dock
        }
        .coordinateSpace(name: "dailies")
        .onPreferenceChange(ScrollOffsetKey.self) { _ in markScrolling() }
    }

    private func row(for take: Take) -> some View {
        TakeRowView(
            take: take,
            onTapCircle: { ui.openPetalFan(for: take) },
            onLongPressCircle: { vm.designateObie(take, replaceExisting: false) },
            onTapText: { ui.openEditor(for: take) }
        )
        .padding(.leading, spineX - CatchlightLayout.circleDiameter / 2
                 - (CatchlightLayout.minTouchTarget - CatchlightLayout.circleDiameter) / 2)
        .padding(.trailing, 20)
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
    let vm = DailiesViewModel(store: store)
    let ui = UIState()
    return DailiesView()
        .environment(vm)
        .environment(ui)
        .preferredColorScheme(.dark)
}

#Preview("Dailies — Daylight (populated)") {
    let store = InMemoryTakeStore()
    for t in SeedTakes.make() { try? store.upsert(t) }
    let vm = DailiesViewModel(store: store)
    return DailiesView()
        .environment(vm)
        .environment(UIState())
        .preferredColorScheme(.light)
}

#Preview("Dailies — empty") {
    let vm = DailiesViewModel(store: InMemoryTakeStore())
    return DailiesView()
        .environment(vm)
        .environment(UIState())
        .preferredColorScheme(.dark)
}
