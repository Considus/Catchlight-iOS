//
//  SearchView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  Full-text search over Takes. A single autofocused field at the top; matching
//  Takes appear below as a LazyVStack of TakeRowViews (the same component used on
//  the timeline). Matching is delegated to TakeStore.search (decrypt-side substring matching; the plaintext FTS index was removed 2026-06-10).
//  Empty/no-match state: "No takes match." in Fog, centred.
//

import SwiftUI
import CatchlightCore

struct SearchView: View {
    @Environment(SearchViewModel.self) private var vm
    @Environment(UIState.self) private var ui
    @Environment(AppModel.self) private var app

    @FocusState private var focused: Bool
    /// Brief "Kept ✓" confirmation after saving the filter as a Sequence.
    @State private var justKept = false

    var body: some View {
        @Bindable var vm = vm
        ZStack {
            Color.ckBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Search field.
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.ckTextSecondary)
                    TextField("Search your takes", text: $vm.query)
                        .focused($focused)
                        .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                        .foregroundStyle(Color.ckTextPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .accessibilityIdentifier("search-field")
                        .accessibilityLabel("Search Takes")
                        .accessibilityHint("Type to find Takes by their text.")
                    if !vm.query.isEmpty {
                        Button { vm.query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.ckTextSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                        .accessibilityHint("Double-tap to clear the search field.")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.ckSurface)
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Dimension chips + "Keep as Sequence" (filter-based Sequences,
                // 2026-06-10). Chips are dimensions of the user's own data —
                // activity types and the months their Takes actually span —
                // composed with the typed text; never predefined folders.
                chipsRow
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                if vm.canKeepAsSequence {
                    keepRow
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                // Results.
                if vm.hasNoMatches {
                    Text("No takes match.")
                        .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                        .foregroundStyle(Color.ckTextSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("No results.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(vm.results) { take in
                                TakeRowView(
                                    take: take,
                                    onTapCircle: { ui.openPetalFan(for: take) },
                                    onTapText: { ui.openEditor(for: take) }
                                )
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 120)
                    }
                }
            }
        }
        .onAppear {
            focused = true
            // Refresh results against the live store: an edit made from a
            // result row (or any other tab) since the last keystroke would
            // otherwise keep showing stale text here.
            vm.recompute()
        }
    }

    // MARK: - Dimension chips

    @ViewBuilder
    private var chipsRow: some View {
        @Bindable var vm = vm
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Tasks", isOn: $vm.requireTask)
                chip("Reminders", isOn: $vm.requireReminder)
                chip("Notes", isOn: $vm.requireNoteOnly)
                chip("Done", isOn: $vm.requireCompleted)
                ForEach(vm.monthOptions, id: \.self) { key in
                    monthChip(key)
                }
            }
        }
        .accessibilityIdentifier("search-chips")
    }

    private func chip(_ label: String, isOn: Binding<Bool>) -> some View {
        let selected = isOn.wrappedValue
        return Button {
            isOn.wrappedValue.toggle()
        } label: {
            chipLabel(label, selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) filter")
        .accessibilityValue(selected ? "on" : "off")
        .accessibilityHint("Double-tap to toggle.")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func monthChip(_ key: String) -> some View {
        let selected = vm.selectedMonths.contains(key)
        let label = SearchViewModel.monthLabel(forKey: key)
        return Button {
            vm.toggleMonth(key)
        } label: {
            chipLabel(label, selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) filter")
        .accessibilityValue(selected ? "on" : "off")
        .accessibilityHint("Double-tap to toggle.")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func chipLabel(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(CatchlightFont.ui(.medium, size: 13, relativeTo: .footnote))
            .foregroundStyle(selected ? Color.ckBackground : Color.ckTextPrimary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 32)
            .background(Capsule().fill(selected ? Color.ckAdd : Color.ckSurface))
            .contentShape(Capsule())
    }

    // MARK: - Keep as Sequence

    private var keepRow: some View {
        HStack {
            Spacer()
            Button {
                guard !justKept else { return }
                // Creating a Sequence is a mutation — gate it like every other
                // create/edit (Task 6.20).
                guard app.ensureEntitled() else { return }
                if vm.keepAsSequence() != nil {
                    justKept = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        justKept = false
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: justKept ? "checkmark" : "pin")
                        .font(.system(size: 12, weight: .medium))
                        .accessibilityHidden(true)
                    Text(justKept ? "Kept" : "Keep as Sequence")
                        .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .subheadline))
                }
                .foregroundStyle(Color.ckTextObie)
                .frame(minHeight: CatchlightLayout.minTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search-keep-sequence")
            .accessibilityLabel(justKept ? "Kept as Sequence" : "Keep as Sequence")
            .accessibilityHint("Double-tap to save this search as a Sequence.")
        }
    }
}

#Preview("Search — results") {
    let store = InMemoryTakeStore()
    for t in SeedTakes.make() { try? store.upsert(t) }
    let vm = SearchViewModel(store: store)
    vm.query = "take"
    return SearchView()
        .environment(vm)
        .environment(UIState())
        .environment(AppModel.preview(store: store, onboarded: true))
        .preferredColorScheme(.dark)
}

#Preview("Search — no match") {
    let store = InMemoryTakeStore()
    for t in SeedTakes.make() { try? store.upsert(t) }
    let vm = SearchViewModel(store: store)
    vm.query = "zzzzz"
    return SearchView()
        .environment(vm)
        .environment(UIState())
        .environment(AppModel.preview(store: store, onboarded: true))
        .preferredColorScheme(.light)
}
