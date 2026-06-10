//
//  SearchView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  Full-text search over Takes. A single autofocused field at the top; matching
//  Takes appear below as a LazyVStack of TakeRowViews (the same component used on
//  the timeline). Matching is delegated to TakeStore.search (FTS5 in production).
//  Empty/no-match state: "No takes match." in Fog, centred.
//

import SwiftUI
import CatchlightCore

struct SearchView: View {
    @Environment(SearchViewModel.self) private var vm
    @Environment(UIState.self) private var ui

    @FocusState private var focused: Bool

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
        .onAppear { focused = true }
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
        .preferredColorScheme(.light)
}
