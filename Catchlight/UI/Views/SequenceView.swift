//
//  SequenceView.swift
//  Catchlight (iOS app target) — filter-based Sequences (2026-06-10)
//
//  The user's saved searches. Pills at the top are the user's OWN kept filters
//  (created from Search via "Keep as Sequence") — the previous three
//  hard-coded modes are gone. Selecting a pill shows the LIVE results of that
//  filter; the Obie (if any) stays pinned at the top. Rows reuse TakeRowView.
//  Long-press a pill to remove the Sequence (the filter only — never Takes).
//

import SwiftUI
import CatchlightCore

struct SequenceView: View {
    @Environment(SequenceViewModel.self) private var vm
    @Environment(UIState.self) private var ui

    var body: some View {
        ZStack {
            Color.ckBackground.ignoresSafeArea()

            if vm.hasNoSequences {
                createHint
            } else {
                VStack(spacing: 0) {
                    sequencePills
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    if vm.isEmpty {
                        Text("Nothing here yet.")
                            .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                            .foregroundStyle(Color.ckTextSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityIdentifier("sequence-empty")
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
        }
        .onAppear { vm.recompute() }
    }

    /// First-run state: no saved Sequences. Creation lives on the Search
    /// surface, in the user's own words — point there.
    private var createHint: some View {
        VStack(spacing: 10) {
            Text("A Sequence is a search you keep.")
                .font(CatchlightFont.ui(.light, size: 17, relativeTo: .body))
                .foregroundStyle(Color.ckTextSecondary)
            Button {
                ui.tab = .search
            } label: {
                Text("Search, then tap Keep")
                    .font(CatchlightFont.ui(.medium, size: 15, relativeTo: .subheadline))
                    .foregroundStyle(Color.ckTextObie)
                    .frame(minHeight: CatchlightLayout.minTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Double-tap to open Search and build your first Sequence.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("sequence-create-hint")
    }

    private var sequencePills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.sequences) { sequence in
                    let selected = vm.selectedId == sequence.id
                    Button {
                        vm.selectedId = sequence.id
                    } label: {
                        Text(sequence.name)
                            .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .subheadline))
                            .foregroundStyle(selected ? Color.ckBackground : Color.ckTextPrimary)
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(minHeight: CatchlightLayout.minTouchTarget)
                            .background(
                                Capsule().fill(selected ? Color.ckAdd : Color.ckSurface)
                            )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            vm.deleteSequence(sequence)
                        } label: {
                            Label("Remove Sequence", systemImage: "trash")
                        }
                    }
                    .accessibilityLabel("Sequence: \(sequence.name)")
                    .accessibilityValue(selected ? "selected" : "")
                    .accessibilityHint("Double-tap to show this Sequence.")
                    .accessibilityAction(named: "Remove Sequence") { vm.deleteSequence(sequence) }
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
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

#Preview("Sequence — saved filters (Night)") {
    let store = InMemoryTakeStore()
    for t in SeedTakes.make() { try? store.upsert(t) }
    try? store.upsert(CatchlightSequence(name: "Tasks", filter: SequenceFilter(requireTask: true)))
    try? store.upsert(CatchlightSequence(name: "first", filter: SequenceFilter(text: "first")))
    let vm = SequenceViewModel(store: store)
    return SequenceView()
        .environment(vm)
        .environment(UIState())
        .preferredColorScheme(.dark)
}

#Preview("Sequence — no sequences yet") {
    let vm = SequenceViewModel(store: InMemoryTakeStore())
    return SequenceView()
        .environment(vm)
        .environment(UIState())
        .preferredColorScheme(.dark)
}
