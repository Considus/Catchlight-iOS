//
//  PetalFanView.swift
//  Catchlight (iOS app target) — Phase 6 UI · constellation redesign 2026-06-11
//
//  The activity-type selector — the signature Catchlight interaction, rebuilt to
//  the owner-approved constellation (HiFi v1.6 §10, "organic peel"):
//
//  LAYOUT — petals settle on an arc to the RIGHT of the timeline: angles
//  −80° / −26.7° / +26.7° / +80° from horizontal (screen frame, y down), all at
//  R = 68pt from the Iris centre; order Notes · Tasks · Reminders · Obie
//  top→bottom. Petals (Marks) are 44pt — they FILL their 44pt touch circles, to
//  match the dock buttons + timeline Iris (owner 2026-06-15; the hub Iris and R
//  were scaled 36→44 / 56→68 in step so the Focus ring keeps its spacing:
//  adjacent chord 61 > 44; Iris clearance 68 > 44). Petals deliberately pass ABOVE
//  the Take card. On the Obie row the fan covers the page heading — approved.
//
//  MOTION — one fluid action in two distinct movements:
//    1 "emergence": the stacked deck (Notes on top, the others invisibly
//      beneath) rises STRAIGHT UP out of the Iris to R at −90°, easeInOutCubic,
//      340ms. The Iris does not rotate yet — the buttons "live" in the Iris.
//    2 "spread": the Iris rotation (90° CW, 700ms, overshooting ~6° then
//      settling) begins at the first peel, and Obie/Reminders/Tasks peel off
//      the deck DURING the rise (peels at 120/185/250ms), each spiralling
//      outward along its own arc (radius blends to R over 520ms) while
//      sweeping clockwise at ~5.5ms/° with easeOutBack (s 1.15) landings —
//      cascading arrivals, soft ~6–8° overshoot. Notes alone rides the deck
//      to the top, then nudges its final 10°.
//  CLOSE — the TRUE time-mirror of the open played 1.25× faster (exits are
//  quicker than entrances): petals kick slightly outward (the reversed
//  overshoot), spiral back into the descending deck, and the Iris reverses its
//  OWN turn on the SAME mirrored clock (it nudges to ~96° then sweeps back to 0 —
//  the open's soft-catch run backwards), so hub and Marks land together rather
//  than the Iris finishing first. Reduce Motion replaces all of it with a fade.
//
//  STYLE — petals share the dock-button language: background-colour face
//  (readable above cards), 1.5pt Ember@35% ring, no shadow, Ember glyphs at
//  the light weight; the Obie petal draws the ring+specular glyph in
//  ckTextObie. Active petals reverse like the dock toggles (Ember fill +
//  background glyph). The veil is ckDim (background @90%, no blur) — the
//  screens beneath stay full-opacity.
//
//  Petal taps toggle the working selection; tapping the veil COMMITS and
//  closes (unchanged semantics — Note remains the floor).
//

import SwiftUI
import CatchlightCore

struct PetalFanView: View {
    let take: Take
    /// Screen-space point of the hub (centre of the tapped circle).
    let hubCentre: CGPoint
    let onCommit: (_ isNote: Bool, _ isTask: Bool, _ hasReminder: Bool, _ isObie: Bool) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Working selection (mutated as petals are tapped).
    @State private var isNote: Bool
    @State private var isTask: Bool
    @State private var hasReminder: Bool
    @State private var isObie: Bool

    private enum FanPhase: Equatable {
        case opening(start: Date)
        case open
        case closing(start: Date, commit: Bool)
    }
    @State private var phase: FanPhase

    init(take: Take,
         hubCentre: CGPoint,
         onCommit: @escaping (Bool, Bool, Bool, Bool) -> Void,
         onDismiss: @escaping () -> Void) {
        self.take = take
        self.hubCentre = hubCentre
        self.onCommit = onCommit
        self.onDismiss = onDismiss
        _isNote = State(initialValue: take.isNote)
        _isTask = State(initialValue: take.isTask)
        _hasReminder = State(initialValue: take.timeReminder != nil)
        _isObie = State(initialValue: take.isObie)
        _phase = State(initialValue: .opening(start: .now))
    }

    // MARK: - Petals

    private enum PetalKind: Int, CaseIterable {
        case note, task, remind, obie
        /// Final screen-frame angle in degrees (y down; −90 = straight up).
        var finalAngle: Double {
            switch self {
            case .note:   return -80
            case .task:   return -80 + 160.0 / 3
            case .remind: return -80 + 320.0 / 3
            case .obie:   return 80
            }
        }
        /// When this petal leaves the rising deck (seconds from open start).
        var peel: Double {
            switch self {
            case .note:   return Choreo.rise   // rides the deck to the top
            case .task:   return 0.250
            case .remind: return 0.185
            case .obie:   return 0.120
            }
        }
        var sweep: Double { finalAngle - Choreo.riseAngle }
        var sweepDuration: Double { max(0.28, sweep * 0.0055) }   // ~5.5ms/°
        var title: String {
            switch self {
            case .note: return "Note"
            case .task: return "Task"
            case .remind: return "Remind"
            case .obie: return "Obie"
            }
        }
        var systemImage: String? {
            switch self {
            case .note:   return "note.text"
            case .task:   return "checkmark.square"
            case .remind: return "bell"
            case .obie:   return nil   // ObiePetalGlyph
            }
        }
        /// Stable suffix for the XCUITest accessibilityIdentifier ("dial-petal-task" etc.).
        var identifierSuffix: String {
            switch self {
            case .note: return "note"
            case .task: return "task"
            case .remind: return "remind"
            case .obie: return "obie"
            }
        }
    }

    // MARK: - Choreography (constants from the approved HiFi v1.6 §10 mode B)

    private enum Choreo {
        static let riseAngle: Double = -90
        static let radius: CGFloat = 68     // owner 2026-06-15: 56 → 68, scaled with the 44pt hub/Marks
        static let startRadius: CGFloat = 8
        static let rise: Double = 0.340          // phase-1 emergence
        static let radialBlend: Double = 0.520   // spiral: radius reaches R over this
        static let irisTurn: Double = 0.700      // hub rotation incl. ±6° overshoot
        static let closeSpeed: Double = 1.25     // exit plays the mirror this much faster
        static var total: Double {               // open end (last petal settles)
            PetalKind.allCases.map { $0.peel + $0.sweepDuration }.max() ?? 1
        }
    }

    // Easings — identical curves to the prototype.
    private static func easeOutBack(_ p: Double) -> Double {
        let s = 1.15
        return 1 + (s + 1) * pow(p - 1, 3) + s * pow(p - 1, 2)
    }
    private static func easeOutCubic(_ p: Double) -> Double { 1 - pow(1 - p, 3) }
    private static func easeInCubic(_ p: Double) -> Double { p * p * p }
    private static func easeInOutCubic(_ p: Double) -> Double {
        p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
    }

    private struct PetalState {
        var angle: Double
        var radius: CGFloat
        var opacity: Double
    }

    /// Pure open-kinematics for a petal at time t. The close evaluates this at
    /// mirrored time (TOTAL − t·closeSpeed) — a strict reverse incl. the
    /// outward kick from the reversed overshoot.
    private static func openState(_ kind: PetalKind, at t: Double) -> PetalState {
        if t < kind.peel {
            // Riding the deck — rising straight up out of the Iris.
            let g = easeInOutCubic(min(max(t / Choreo.rise, 0), 1))
            return PetalState(
                angle: Choreo.riseAngle,
                radius: Choreo.startRadius + (Choreo.radius - Choreo.startRadius) * g,
                opacity: min(t / 0.08, 1)
            )
        }
        // Peeled off — sweeping clockwise while the radius blends out (spiral).
        let q = min((t - kind.peel) / kind.sweepDuration, 1)
        let rPeel = Choreo.startRadius + (Choreo.radius - Choreo.startRadius)
            * easeInOutCubic(min(kind.peel / Choreo.rise, 1))
        let rq = min((t - kind.peel) / min(Choreo.radialBlend, kind.sweepDuration), 1)
        return PetalState(
            angle: Choreo.riseAngle + kind.sweep * easeOutBack(q),
            radius: rPeel + (Choreo.radius - rPeel) * easeOutCubic(rq),
            opacity: 1
        )
    }

    private func petalState(_ kind: PetalKind, now: Date) -> PetalState {
        switch phase {
        case .opening(let start):
            let t = now.timeIntervalSince(start)
            return Self.openState(kind, at: t)
        case .open:
            return PetalState(angle: kind.finalAngle, radius: Choreo.radius, opacity: 1)
        case .closing(let start, _):
            let tm = Choreo.total - now.timeIntervalSince(start) * Choreo.closeSpeed
            if tm <= 0 { return PetalState(angle: Choreo.riseAngle, radius: Choreo.startRadius, opacity: 0) }
            return Self.openState(kind, at: tm)
        }
    }

    /// Open-time hub rotation with the petals' soft-catch character: ~6° past the
    /// mark, then settle — nothing moves precisely between two points. Factored out
    /// so the CLOSE can evaluate it at the mirrored time (below), making the hub a
    /// strict time-reverse of the open IN STEP with the petals (owner 2026-06-16:
    /// the close used to drive the hub on its OWN faster clock, so the Iris finished
    /// its turn well before the Marks had spiralled back into it).
    private static func openHubRotation(at t: Double) -> Double {
        func turn(_ p: Double, from a: Double, over b: Double, to c: Double) -> Double {
            // two-segment keyframe: a → b (72%, ease-out) → c (settle)
            if p < 0.72 { return a + (b - a) * easeOutCubic(p / 0.72) }
            return b + (c - b) * easeInOutCubic((p - 0.72) / 0.28)
        }
        let tt = t - PetalKind.obie.peel   // the hub starts turning at the first peel
        guard tt > 0 else { return 0 }
        return turn(min(tt / Choreo.irisTurn, 1), from: 0, over: 96, to: 90)
    }

    private func hubRotation(now: Date) -> Double {
        switch phase {
        case .opening(let start):
            return Self.openHubRotation(at: now.timeIntervalSince(start))
        case .open:
            return 90
        case .closing(let start, _):
            // Same mirrored clock the petals use (petalState .closing) — a strict
            // reverse of the open, so hub and Marks land together.
            let tm = Choreo.total - now.timeIntervalSince(start) * Choreo.closeSpeed
            if tm <= 0 { return 0 }
            return Self.openHubRotation(at: tm)
        }
    }

    private var isAnimating: Bool {
        if case .open = phase { return false }
        return true
    }

    // MARK: - Body

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isAnimating)) { context in
            let now = context.date
            ZStack {
                // The veil — tap to COMMIT the current selection and dismiss.
                // (Petal taps toggle but never close; the veil tap is the
                // commit gesture — see the 4.5/7.4 audit note in history.)
                Color.ckDim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { retractAndDismiss(commit: true) }
                    .accessibilityIdentifier("dial-dim")
                    .accessibilityLabel("Save and close")
                    .accessibilityHint("Double-tap to apply your selection and close.")
                    .accessibilityAddTraits(.isButton)

                ZStack {
                    ForEach(PetalKind.allCases.reversed(), id: \.rawValue) { kind in
                        // Reversed so Notes stacks on top during the emergence.
                        let s = petalState(kind, now: now)
                        let rad = s.angle * .pi / 180
                        petal(kind)
                            .offset(x: cos(rad) * s.radius, y: sin(rad) * s.radius)
                            .opacity(s.opacity)
                    }

                    // Hub — the Iris itself, rotating in place. A vertical
                    // marker line rides the rotation and lands horizontal at
                    // open (UX §6).
                    ZStack {
                        TakeCircleView(take: workingTake, diameter: 44)   // match the timeline Iris (owner 2026-06-15)
                        Capsule()
                            .fill(Color.ckEmber.opacity(0.6))
                            .frame(width: 1.5, height: 17)   // scaled with the 36→44 hub
                            .opacity(hubRotation(now: now) / 90 * 0.9)
                    }
                    .rotationEffect(.degrees(hubRotation(now: now)))
                    .accessibilityLabel("Selected: \(TakeCircleView.activityDescription(for: workingTake))")
                }
                .position(hubCentre)
                .accessibilityElement(children: .contain)
            }
        }
        .onAppear {
            if reduceMotion { phase = .open }
            else { phase = .opening(start: .now) }
            // Settle into the static .open phase once the choreography ends so
            // the TimelineView stops ticking.
            DispatchQueue.main.asyncAfter(deadline: .now() + Choreo.total + 0.05) {
                if case .opening = phase { phase = .open }
            }
        }
    }

    /// A synthetic Take reflecting the working selection, so the hub circle
    /// previews the result live.
    private var workingTake: Take {
        var t = take
        t.isNote = isNote
        t.setTask(isTask)
        t.isObie = isObie
        if hasReminder, t.timeReminder == nil {
            t.timeReminder = TimeReminder(scheduledDate: .now, notificationIdentifier: t.id.uuidString)
        } else if !hasReminder {
            t.timeReminder = nil
        }
        return t
    }

    private func isActive(_ kind: PetalKind) -> Bool {
        switch kind {
        case .note: return isNote
        case .obie: return isObie
        case .remind: return hasReminder
        case .task: return isTask
        }
    }

    @ViewBuilder
    private func petal(_ kind: PetalKind) -> some View {
        let active = isActive(kind)
        Button {
            toggle(kind)
        } label: {
            ZStack {
                // Dock-button language: background face + Ember@35% ring;
                // active reverses (Ember fill + background glyph), exactly
                // like the filter toggles.
                Circle().fill(active ? Color.ckEmber : Color.ckBackground)
                Circle().strokeBorder(
                    active ? Color.ckEmber : Color.ckEmber.opacity(0.35),
                    lineWidth: 1.5
                )
                if let symbol = kind.systemImage {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .light))   // scaled with the 36→44 Mark
                        .foregroundStyle(active ? Color.ckBackground : Color.ckEmber)
                } else {
                    ObiePetalGlyph(size: 20)   // scaled with the 36→44 Mark, keeping the petal's tuned ratio (D-042)
                        .foregroundStyle(active ? Color.ckBackground : Color.ckTextObie)
                }
            }
            .frame(width: 44, height: 44)
            .frame(minWidth: CatchlightLayout.minTouchTarget,
                   minHeight: CatchlightLayout.minTouchTarget)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dial-petal-\(kind.identifierSuffix)")
        .accessibilityLabel(kind.title)
        .accessibilityValue(isActive(kind) ? "active" : "inactive")
        .accessibilityHint("Double-tap to \(isActive(kind) ? "remove" : "add") \(kind.title).")
        .accessibilityAddTraits(isActive(kind) ? [.isSelected, .isButton] : [.isButton])
    }

    // MARK: - Toggle (Note is the floor)

    private func toggle(_ kind: PetalKind) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            switch kind {
            case .note:   isNote.toggle()
            case .task:   isTask.toggle()
            case .remind: hasReminder.toggle()
            case .obie:   isObie.toggle()
            }
            // Note is the floor: if nothing else is active, Note re-asserts.
            if !isTask && !hasReminder && !isObie { isNote = true }
        }
    }

    // MARK: - Retract

    private func retractAndDismiss(commit: Bool = false) {
        guard case .open = phase else {
            // Mid-choreography taps wait for the settle (matches the prototype guard).
            return
        }
        if reduceMotion {
            finish(commit: commit)
            return
        }
        phase = .closing(start: .now, commit: commit)
        let closeDuration = (Choreo.total / Choreo.closeSpeed) + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + closeDuration) {
            if case .closing(_, let c) = phase { finish(commit: c) }
        }
    }

    private func finish(commit: Bool) {
        if commit {
            onCommit(isNote, isTask, hasReminder, isObie)
        } else {
            onDismiss()
        }
    }
}

#Preview("Petal fan — Night") {
    GeometryReader { geo in
        PetalFanView(
            take: Take(blocks: [.checkItem("Shape me")]),
            hubCentre: CGPoint(x: 60, y: geo.size.height / 2),
            onCommit: { _, _, _, _ in },
            onDismiss: {}
        )
    }
    .background(Color.ckBackground)
    .preferredColorScheme(.dark)
}

#Preview("Petal fan — Daylight") {
    GeometryReader { geo in
        PetalFanView(
            take: Take(blocks: [.textLine("Shape me")]),
            hubCentre: CGPoint(x: 60, y: geo.size.height / 2),
            onCommit: { _, _, _, _ in },
            onDismiss: {}
        )
    }
    .background(Color.ckBackground)
    .preferredColorScheme(.light)
}
