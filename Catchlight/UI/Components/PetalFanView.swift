//
//  PetalFanView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  The activity-type selector — the signature Catchlight interaction. Four petals
//  arc out from the hub (the tapped circle) along fixed angles; tapping a petal
//  toggles that activity type; Note is the floor (re-asserts if all others are
//  removed). Presented as a full-screen overlay so it can dim and de-emphasise the
//  surrounding timeline.
//
//  Geometry note: screen-space angles. SwiftUI's y axis grows downward, so to place
//  a petal at a conventional math angle θ (0° = east, CCW positive) we use
//  offset = (cos θ, −sin θ) · radius. The brief's angles (Note 210°, Obie 250°,
//  Remind 310°, Task 350°) are interpreted in that conventional frame, giving the
//  documented fan that opens up-and-out around the hub.
//
//  Animation (per brief):
//    • hub rotates +90° (cubic ease-in-out, 480ms) while deploying, counter-rotates
//      on dismiss.
//    • petals arc out together with staggered spring delays (0/65/130/195 ms).
//    • surrounding content fades to 18%; a dim overlay covers the background.
//

import SwiftUI
import CatchlightCore

struct PetalFanView: View {
    /// The take being shaped. The fan reads its current types and reports a new set.
    let take: Take
    /// Screen-space point of the hub (centre of the tapped circle).
    let hubCentre: CGPoint
    /// Apply the chosen types (note/task/reminder/obie). Note floor enforced upstream.
    let onCommit: (_ isNote: Bool, _ isTask: Bool, _ hasReminder: Bool, _ isObie: Bool) -> Void
    /// Dismiss without committing (tap the dim overlay).
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var scheme

    // Working selection (mutated as petals are tapped).
    @State private var isNote: Bool
    @State private var isTask: Bool
    @State private var hasReminder: Bool
    @State private var isObie: Bool

    // Animation state.
    @State private var deployed = false
    @State private var hubRotation: Double = 0

    private let hubDiameter: CGFloat = 56
    private let petalDiameter: CGFloat = 56
    private let arcRadius: CGFloat = 96

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
    }

    private enum PetalKind: CaseIterable {
        case note, obie, remind, task
        /// Conventional-frame angle in degrees (0° = east, CCW positive).
        var angle: Double {
            switch self {
            case .note:   return 210
            case .obie:   return 250
            case .remind: return 310
            case .task:   return 350
            }
        }
        /// Staggered spring delay (ms → s).
        var delay: Double {
            switch self {
            case .note:   return 0.000
            case .obie:   return 0.065
            case .remind: return 0.130
            case .task:   return 0.195
            }
        }
        var title: String {
            switch self {
            case .note: return "Note"
            case .obie: return "Obie"
            case .remind: return "Remind"
            case .task: return "Task"
            }
        }
        var systemImage: String {
            switch self {
            case .note: return "note.text"
            case .obie: return "star.fill"
            case .remind: return "bell.fill"
            case .task: return "checkmark.circle"
            }
        }
        /// Stable suffix for the XCUITest accessibilityIdentifier ("dial-petal-task" etc.).
        var identifierSuffix: String {
            switch self {
            case .note: return "note"
            case .obie: return "obie"
            case .remind: return "remind"
            case .task: return "task"
            }
        }
    }

    private func isActive(_ kind: PetalKind) -> Bool {
        switch kind {
        case .note: return isNote
        case .obie: return isObie
        case .remind: return hasReminder
        case .task: return isTask
        }
    }

    private func offset(for kind: PetalKind) -> CGSize {
        guard deployed else { return .zero }
        let r = arcRadius
        let radians = kind.angle * .pi / 180
        return CGSize(width: cos(radians) * r, height: -sin(radians) * r)
    }

    var body: some View {
        ZStack {
            // Dim overlay — tap to COMMIT the current selection and dismiss.
            // Petal taps toggle the working state but never close the fan on
            // their own (the user may toggle multiple types in one session),
            // so the dim tap is the commit gesture. Before the 4.5/7.4 audit
            // this called `retractAndDismiss()` with the default commit=false,
            // which silently dropped every Dial edit; that path is the bug
            // referenced in the post-7.4 fix-up.
            Color.ckDim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { retractAndDismiss(commit: true) }
                .accessibilityIdentifier("dial-dim")
                .accessibilityLabel("Save and close")
                .accessibilityHint("Double-tap to apply your selection and close.")
                .accessibilityAddTraits(.isButton)

            ZStack {
                // Petals.
                ForEach(Array(PetalKind.allCases.enumerated()), id: \.offset) { _, kind in
                    petal(kind)
                        .offset(offset(for: kind))
                        .opacity(deployed ? 1 : 0)
                        .scaleEffect(deployed ? 1 : 0.3)
                }

                // Hub (the tapped circle, enlarged), rotating as petals deploy.
                ZStack {
                    Circle().fill(Color.ckSurface)
                    TakeCircleView(take: workingTake, diameter: hubDiameter * 0.7)
                }
                .frame(width: hubDiameter, height: hubDiameter)
                .rotationEffect(.degrees(hubRotation))
                .shadow(color: Color.ckShadow.opacity(0.5), radius: 8, y: 2)
                .accessibilityLabel("Selected: \(TakeCircleView.activityDescription(for: workingTake))")
            }
            .position(hubCentre)
            // Let VoiceOver navigate into the hub + each petal as siblings.
            .accessibilityElement(children: .contain)
        }
        .onAppear { deploy() }
    }

    /// A synthetic Take reflecting the working selection, so the hub circle previews
    /// the result live.
    private var workingTake: Take {
        var t = take
        t.isNote = isNote
        t.isTask = isTask
        t.isObie = isObie
        if hasReminder, t.timeReminder == nil {
            t.timeReminder = TimeReminder(scheduledDate: .now, notificationIdentifier: t.id.uuidString)
        } else if !hasReminder {
            t.timeReminder = nil
        }
        return t
    }

    @ViewBuilder
    private func petal(_ kind: PetalKind) -> some View {
        let active = isActive(kind)
        Button {
            toggle(kind)
        } label: {
            ZStack {
                Circle()
                    .fill(petalFill(kind, active: active))
                Circle()
                    .strokeBorder(petalBorder(kind), lineWidth: petalBorderWidth(kind, active: active))
                Image(systemName: kind.systemImage)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(petalIcon(kind, active: active))
            }
            .frame(width: petalDiameter, height: petalDiameter)
            .frame(minWidth: CatchlightLayout.minTouchTarget,
                   minHeight: CatchlightLayout.minTouchTarget)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dial-petal-\(kind.identifierSuffix)")
        .accessibilityLabel(kind.title)
        .accessibilityValue(active ? "active" : "inactive")
        .accessibilityHint("Double-tap to \(active ? "remove" : "add") \(kind.title).")
        // .isButton is redundant under a Button{} but the spec asks for it
        // explicitly so the role is preserved if this view is ever rebuilt.
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : [.isButton])
    }

    // MARK: - Petal styling (mode-dependent, per brief)

    private func petalFill(_ kind: PetalKind, active: Bool) -> Color {
        switch kind {
        case .remind:
            // Ember fill, both modes.
            return active ? .ckEmber : (scheme == .dark ? .ckDusk : .ckStone)
        case .note, .task, .obie:
            // Dark fill (Night) / Stone fill (Daylight). Active state filled brighter.
            if active {
                return scheme == .dark ? Color.ckCatchlight.opacity(0.22) : Color.ckEmber.opacity(0.20)
            }
            return scheme == .dark ? .ckDusk : .ckStone
        }
    }

    private func petalBorder(_ kind: PetalKind) -> Color {
        switch kind {
        case .note:
            // Subtle light border (Night) / dark border (Daylight).
            return scheme == .dark ? Color.ckCatchlight.opacity(0.35) : Color.ckInk.opacity(0.45)
        case .remind:
            return scheme == .dark ? Color.ckInk.opacity(0.4) : Color.ckEmber
        case .task:
            // Glow border (Night) / Ember border (Daylight).
            return scheme == .dark ? .ckGlow : .ckEmber
        case .obie:
            // Glow ring border (Night) / Ember ring border (Daylight).
            return scheme == .dark ? .ckGlow : .ckEmber
        }
    }

    private func petalBorderWidth(_ kind: PetalKind, active: Bool) -> CGFloat {
        switch kind {
        case .obie: return active ? 3 : 2     // a distinct "ring"
        default:    return active ? 2 : 1
        }
    }

    private func petalIcon(_ kind: PetalKind, active: Bool) -> Color {
        switch kind {
        case .remind:
            return .ckInk                       // dark icon, both modes
        default:
            return scheme == .dark ? .ckCatchlight : .ckInk
        }
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

    // MARK: - Deploy / retract

    private func deploy() {
        withAnimation(.timingCurve(0.45, 0, 0.55, 1, duration: 0.48)) {
            hubRotation = 90
        }
        for kind in PetalKind.allCases {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.68).delay(kind.delay)) {
                deployed = true
            }
        }
    }

    private func retractAndDismiss(commit: Bool = false) {
        withAnimation(.timingCurve(0.45, 0, 0.55, 1, duration: 0.40)) {
            hubRotation = 0
            deployed = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
            if commit {
                onCommit(isNote, isTask, hasReminder, isObie)
            } else {
                onDismiss()
            }
        }
    }
}

#Preview("Petal fan — Night") {
    GeometryReader { geo in
        PetalFanView(
            take: Take(bodyText: "Shape me", isTask: true),
            hubCentre: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2),
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
            take: Take(bodyText: "Shape me"),
            hubCentre: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2),
            onCommit: { _, _, _, _ in },
            onDismiss: {}
        )
    }
    .background(Color.ckBackground)
    .preferredColorScheme(.light)
}
