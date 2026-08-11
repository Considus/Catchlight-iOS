//
//  ExpandTakeMenuButton.swift
//  Catchlight (iOS app target)
//
//  The long-press menu's "Expand Take" / "Collapse Take" (owner 2026-08-11): read a whole
//  Take without moving the Settings "Preview" length to All for everything.
//
//  WHY IT'S A VIEW AND NOT A CALLBACK. Every other row action (mark done, Important, Obie,
//  export, delete) is a store mutation, so it's injected as a closure and routed through the
//  view model. This one isn't — it's a device-local view preference (see
//  `SettingsViewModel.ExpandedTakes`), so it needs no store, no entitlement gate, and no
//  routing. Making it a self-contained view means the TWO menus that exist —
//  `TakeRowView.rowMenuItems` and `TimelineReadCell.menuItems` — embed the SAME thing rather
//  than each growing their own copy. That pair has drifted before: the UIKit timeline draws
//  `TakeCardSurface` directly and lost the SwiftUI row's whole accessibility layer for six
//  milestones without anyone noticing.
//
//  The @AppStorage read is what makes a tap visible immediately: `TakeCardSurface` observes
//  the same key, so toggling here re-renders the card in place.
//

import SwiftUI
import CatchlightCore

struct ExpandTakeMenuButton: View {
    let take: Take

    @AppStorage(SettingsViewModel.ExpandedTakes.defaultsKey)
    private var expandedRaw: String = ""

    private var isExpanded: Bool {
        SettingsViewModel.ExpandedTakes.contains(take.id, in: expandedRaw)
    }

    var body: some View {
        Button {
            expandedRaw = SettingsViewModel.ExpandedTakes.toggling(take.id, in: expandedRaw)
        } label: {
            Label(isExpanded ? "Collapse Take" : "Expand Take",
                  systemImage: isExpanded
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
        }
    }
}
