//
//  Angle.swift
//  Catchlight (iOS app target) — Phase 3 list Angle (D-033)
//
//  An Angle is a per-Take, ephemeral, TOGGLED alternative presentation of the
//  SAME Take (D-033 / Take_Blocks spec §6) — not a setting you leave on, not a
//  content or colour change. You enter an Angle, use it, and exit back to where
//  you were; the Take's data is untouched except by the ordinary block edits the
//  Angle performs (tick / reorder), which persist like any edit.
//
//  EXTENSIBLE BY DESIGN. An Angle declares (1) WHEN it applies to a Take and
//  (2) the full-screen view it toggles into. Adding a future Angle (a board, a
//  calendar, a reading view) is just appending one to `AngleRegistry.all` with
//  its own `appliesTo` predicate and presentation — the existing Angles are
//  untouched. Day one registers exactly ONE: the list Angle.
//

import SwiftUI
import CatchlightCore

struct Angle: Identifiable {
    /// Stable id — also the key the picker uses when more than one Angle applies.
    let id: String
    /// User-facing name (locked taxonomy).
    let title: String
    /// SF Symbol for the top-right affordance and the (multi-Angle) picker row.
    let systemImage: String
    /// Whether this Angle is offered for `take`. Pure over the Take so it is
    /// unit-testable in isolation.
    let appliesTo: (Take) -> Bool
    /// Builds the full-screen presentation, bound to the LIVE Take so the Angle's
    /// ticks / reorders mutate (and ultimately persist) the real thing, plus a
    /// close handler for the ephemeral exit.
    let makePresentation: (Binding<Take>, _ onClose: @escaping () -> Void) -> AnyView
}

enum AngleRegistry {
    /// Every registered Angle, in registration (display) order. To add an Angle,
    /// append it here and define it like `Angle.list` below — nothing else
    /// changes; each Angle's visibility is governed solely by its own predicate.
    static let all: [Angle] = [.list]

    /// The Angles that apply to `take`, in registration order. The top-right
    /// affordance shows when this is non-empty; a picker appears when it has more
    /// than one.
    static func applicable(to take: Take) -> [Angle] {
        all.filter { $0.appliesTo(take) }
    }
}

extension Angle {
    /// The shopping-aisle list view: a Take's checklist, big and glanceable.
    /// Applies whenever the Take has at least one check item (`isTask`).
    static let list = Angle(
        id: "list",
        title: "Shot List",
        systemImage: "checklist",
        appliesTo: { $0.isTask },
        makePresentation: { take, onClose in
            AnyView(ListAngleView(take: take, onClose: onClose))
        }
    )
}
