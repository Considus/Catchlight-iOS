//
//  UIState.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  Cross-cutting, presentation-only UI coordination shared by RootView and its
//  children: which tab is active, whether the petal fan / editor / add-fan are
//  presented, and the Take they target. @Observable (iOS 17+). It owns NO domain
//  data — the feature view models do — so it stays a thin coordinator that any
//  screen can read via the environment.
//

import SwiftUI
import CatchlightCore

@Observable
final class UIState {

    enum Tab: Hashable { case dailies, search, sequence }

    var tab: Tab = .dailies

    // Petal fan.
    var petalFanTake: Take?
    var petalFanOrigin: CGPoint = .zero
    var isPetalFanPresented: Bool { petalFanTake != nil }

    // Take editor.
    var editorTake: Take?
    var isEditorPresented: Bool { editorTake != nil }

    // Add-button bloom (New Take / New Sequence).
    var isAddExpanded = false

    /// Settings sheet — long-press on the Dailies dock button toggles this once the
    /// first-run orientation has finished (step >= 4 in `FirstRunOrientationState`).
    var isSettingsPresented = false

    /// Sync-conflict resolution sheet — opened from the timeline's "Review" banner
    /// when `AppModel.conflictQueue.pending` is non-empty (Task 6.15).
    var isConflictSheetPresented = false

    /// Animation for the surrounding-content fade when the petal fan appears or
    /// dismisses. Driven from the mutation site via `withAnimation` rather than a
    /// `.animation(_:value:)` view modifier, so the fade animates without coupling the
    /// views to a value-observing modifier (which tripped SwiftUI's type-checker).
    static let fanFade: Animation = .easeInOut(duration: 0.2)

    func openPetalFan(for take: Take, origin: CGPoint = .zero) {
        petalFanOrigin = origin
        withAnimation(Self.fanFade) { petalFanTake = take }
    }

    func closePetalFan() {
        withAnimation(Self.fanFade) { petalFanTake = nil }
    }

    func openEditor(for take: Take) {
        isAddExpanded = false
        editorTake = take
    }

    func closeEditor() { editorTake = nil }
}
