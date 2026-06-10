//
//  TakeEditView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  Creating / editing a Take. A card that rises into the upper third of the screen
//  above a dimmed background, holding a full-surface TextEditor and a footer row
//  with the Take's circle + a muted "Shape this take" label. Tapping the footer
//  circle opens the petal fan from that origin. Auto-saves on dismiss — there is no
//  explicit save button. Dismiss by tapping the dim overlay; the card retreats and
//  the keyboard dismisses.
//
//  Keyboard handling: the card is top-anchored and uses `.ignoresSafeArea(.keyboard)`
//  on the dim layer only, while the card itself stays pinned to the top — so the
//  writing surface is always visible above the keyboard, never behind it.
//

import SwiftUI
import CatchlightCore

struct TakeEditView: View {
    @Environment(DailiesViewModel.self) private var vm
    @Environment(UIState.self) private var ui
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme

    let take: Take

    @State private var text: String
    @FocusState private var focused: Bool

    init(take: Take) {
        self.take = take
        _text = State(initialValue: take.bodyText)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Dim background — tap to save + dismiss.
            Color.ckDim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { saveAndDismiss() }
                .accessibilityIdentifier("editor-done")
                .accessibilityLabel("Done editing")
                .accessibilityHint("Double-tap to save this take and close.")
                .accessibilityAddTraits(.isButton)

            card
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
        .onAppear { focused = true }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $text)
                .focused($focused)
                .font(CatchlightFont.display(size: 22, relativeTo: .body))
                .foregroundStyle(Color.ckTextPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 160, maxHeight: 260)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .accessibilityIdentifier("take-edit-body")
                .accessibilityLabel("Take text")
                .accessibilityHint("Write your take. It saves automatically.")

            Divider().background(Color.ckTextSecondary.opacity(0.2))

            // Footer: circle + "Shape this take".
            HStack(spacing: 12) {
                Button {
                    ui.openPetalFan(for: currentTake)
                } label: {
                    TakeCircleView(take: currentTake, diameter: 28)
                        .frame(minWidth: CatchlightLayout.minTouchTarget,
                               minHeight: CatchlightLayout.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shape this take. \(TakeCircleView.activityDescription(for: currentTake))")
                .accessibilityHint("Double-tap to choose activity types.")

                Text("Shape this take")
                    .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Color.ckTextSecondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.ckSurface)
                .shadow(color: Color.ckShadow.opacity(0.5), radius: 18, y: 6)
        )
    }

    /// The take with the live (unsaved) text, so the footer circle + petal fan
    /// reflect what's on screen.
    private var currentTake: Take {
        var t = take
        t.bodyText = text
        return t
    }

    private func saveAndDismiss() {
        focused = false
        // Task 6.20: the gate lives at the commit, not the navigation. Any path
        // that reaches the editor (Dailies, Search, Sequence, future deep links)
        // funnels through here; lapsed users have their edit redirected to the
        // paywall without losing what they typed (the close still happens so the
        // dim layer and keyboard get released — the paywall overlays cleanly).
        guard app.ensureEntitled() else {
            ui.closeEditor()
            return
        }
        let t = currentTake
        // Blank-Take discard (2026-06-10): a dismissed editor with no text and
        // no shaping leaves nothing behind. Previously a blank Take was persisted
        // the moment the editor opened, so cancelling accumulated permanent
        // "Untitled take" rows with no way to remove them.
        let isBlank = t.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !t.isTask && t.timeReminder == nil && !t.isObie
        if isBlank {
            vm.discardIfPresent(t)
        } else {
            vm.save(t)
        }
        ui.closeEditor()
    }
}

#Preview("Edit — Night") {
    let vm = DailiesViewModel(store: InMemoryTakeStore())
    return TakeEditView(take: Take(bodyText: "A thought half-formed,\nstill worth keeping.", isTask: true))
        .environment(vm)
        .environment(UIState())
        .background(Color.ckBackground)
        .preferredColorScheme(.dark)
}

#Preview("Edit — Daylight") {
    let vm = DailiesViewModel(store: InMemoryTakeStore())
    return TakeEditView(take: Take(bodyText: ""))
        .environment(vm)
        .environment(UIState())
        .background(Color.ckBackground)
        .preferredColorScheme(.light)
}
