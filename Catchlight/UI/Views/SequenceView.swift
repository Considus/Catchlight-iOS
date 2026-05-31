//
//  SequenceView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  The filtered view. Pill tabs at the top select one of three modes — Reminders,
//  Tasks, Notes — each with its own ordering (see SequenceViewModel). The Obie (if
//  any) is pinned at the top of every mode. Rows reuse TakeRowView. Empty state for
//  a filter with no results: "Nothing here yet." in Fog, centred.
//

import SwiftUI
import CatchlightCore

struct SequenceView: View {
    @Environment(SequenceViewModel.self) private var vm
    @Environment(UIState.self) private var ui

    var body: some View {
        ZStack {
            Color.ckBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                filterPills
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                if vm.isEmpty {
                    Text("Nothing here yet.")
                        .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                        .foregroundStyle(Color.ckTextSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Nothing here yet.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if let obie = vm.obie {
                                row(for: obie)
                                Color.clear.frame(height: 14)
                            }
                            ForEach(vm.results) { take in
                                row(for: take)
                            }
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 120)
                    }
                }
            }
        }
        .onAppear { vm.recompute() }
    }

    private var filterPills: some View {
        HStack(spacing: 8) {
            ForEach(SequenceViewModel.Filter.allCases) { filter in
                let selected = vm.filter == filter
                Button {
                    vm.filter = filter
                } label: {
                    Text(filter.rawValue)
                        .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .subheadline))
                        .foregroundStyle(selected ? Color.ckBackground : Color.ckTextPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(minHeight: CatchlightLayout.minTouchTarget)
                        .background(
                            Capsule().fill(selected ? Color.ckAdd : Color.ckSurface)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(filter.rawValue)
                .accessibilityValue(selected ? "selected" : "")
                .accessibilityHint("Double-tap to show \(filter.rawValue.lowercased()).")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
            Spacer()
        }
    }

    private func row(for take: Take) -> some View {
        TakeRowView(
            take: take,
            onTapCircle: { ui.openPetalFan(for: take) },
            onTapText: { ui.openEditor(for: take) }
        )
        .padding(.horizontal, 20)
    }
}

#Preview("Sequence — Reminders (Night)") {
    let store = InMemoryTakeStore()
    for t in SeedTakes.make() { try? store.upsert(t) }
    let vm = SequenceViewModel(store: store)
    vm.filter = .reminders
    return SequenceView()
        .environment(vm)
        .environment(UIState())
        .preferredColorScheme(.dark)
}

#Preview("Sequence — Tasks (Daylight)") {
    let store = InMemoryTakeStore()
    for t in SeedTakes.make() { try? store.upsert(t) }
    let vm = SequenceViewModel(store: store)
    vm.filter = .tasks
    return SequenceView()
        .environment(vm)
        .environment(UIState())
        .preferredColorScheme(.light)
}

#Preview("Sequence — empty filter") {
    let vm = SequenceViewModel(store: InMemoryTakeStore())
    vm.filter = .notes
    return SequenceView()
        .environment(vm)
        .environment(UIState())
        .preferredColorScheme(.dark)
}
