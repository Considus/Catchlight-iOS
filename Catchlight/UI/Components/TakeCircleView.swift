//
//  TakeCircleView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  The Take "circle": the quadrant-filled disc that encodes a Take's active
//  activity types at a glance, and the Obie ring + specular dot. Used on every
//  timeline row, in search/sequence results, and in the edit footer. Pure
//  rendering — no gestures here; callers attach taps/long-presses.
//
//  Quadrant map (clockwise from top-right), per the brief:
//    • Top-right    → Note      (Catchlight @ 50% Night / Ink @ 30% Daylight)
//    • Bottom-right → Reminder  (Ember, both)
//    • Bottom-left  → Task      (Glow @ 60% Night / Ink @ 12% Daylight)
//    • Top-left     → Reserved  (always empty)
//

import SwiftUI
import CatchlightCore

/// One ANNULAR quadrant of the Iris (HiFi v1.7 — section 7). The Iris reads as a
/// RING with a hollow aperture, not a solid disc: each quadrant fills only the
/// band between an inner radius (`innerRatio × R`, v1.7's r8-of-r18 ≈ 0.44) and
/// the outer radius, leaving the centre empty (the camera aperture). The path
/// runs along the outer arc, back along the inner arc, and closes — never
/// through the centre.
private struct QuadrantSlice: Shape {
    /// Start/end angles in degrees, 0° = 3 o'clock, increasing clockwise in screen
    /// space (SwiftUI's y grows downward, so `Angle` clockwise matches visual).
    let startDegrees: Double
    let endDegrees: Double
    /// Inner radius as a fraction of the outer radius (v1.7 r8/r18 ≈ 0.44).
    var innerRatio: CGFloat = 0.44

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outerR = min(rect.width, rect.height) / 2
        let innerR = outerR * innerRatio
        var p = Path()
        p.addArc(
            center: centre,
            radius: outerR,
            startAngle: .degrees(startDegrees),
            endAngle: .degrees(endDegrees),
            clockwise: false
        )
        p.addArc(
            center: centre,
            radius: innerR,
            startAngle: .degrees(endDegrees),
            endAngle: .degrees(startDegrees),
            clockwise: true
        )
        p.closeSubpath()
        return p
    }
}

struct TakeCircleView: View {
    let take: Take
    var diameter: CGFloat = CatchlightLayout.circleDiameter

    @Environment(\.colorScheme) private var scheme

    private var hasReminder: Bool { take.timeReminder != nil }

    var body: some View {
        ZStack {
            // Off-band: a faint full ANNULAR ring (v1.7 `--q-off`) so empty
            // quadrants still read as part of a ring while the centre stays
            // HOLLOW (the camera aperture). `strokeBorder` fills inward from the
            // edge to the inner radius (0.44·R), leaving the centre empty —
            // replacing the old solid base disc that filled the aperture.
            Circle()
                .strokeBorder(Color.ckIrisOff, lineWidth: diameter * 0.28)

            // Top-right: Note. Angles -90°..0° (12 o'clock to 3 o'clock).
            if take.isNote {
                QuadrantSlice(startDegrees: -90, endDegrees: 0)
                    .fill(Quadrant.note(scheme))
            }
            // Bottom-right: Reminder. 0°..90°.
            if hasReminder {
                QuadrantSlice(startDegrees: 0, endDegrees: 90)
                    .fill(Quadrant.reminder(scheme))
            }
            // Bottom-left: Task. 90°..180°.
            if take.isTask {
                QuadrantSlice(startDegrees: 90, endDegrees: 180)
                    .fill(Quadrant.task(scheme))
            }
            // Top-left (180°..270°) is reserved — intentionally empty.

            // Hairline outer ring (HiFi v1.7 — section 7): a 0.75pt rim around
            // the annular quadrants. Daylight #E7E7E7 (v1.7's iris SVG uses the
            // near-identical #ECECEC); Night rides the divider/line token.
            Circle()
                .strokeBorder(Color.ckIrisRing, lineWidth: 0.75)

            // Obie: full ring + specular dot at the upper-right.
            if take.isObie {
                Circle()
                    .strokeBorder(Quadrant.obieRing(scheme), lineWidth: max(2, diameter * 0.12))
                Circle()
                    .fill(Color.white.opacity(scheme == .dark ? 0.9 : 0.8))
                    .frame(width: diameter * 0.16, height: diameter * 0.16)
                    .offset(x: diameter * 0.22, y: -diameter * 0.22)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)   // the row exposes a combined label; the disc is decorative there
    }

    /// A spoken description of the active types, for callers that DO want the circle
    /// to announce itself (e.g. the edit footer).
    static func activityDescription(for take: Take) -> String {
        var parts: [String] = []
        if take.isObie { parts.append("Obie") }
        if take.isNote { parts.append("Note") }
        if take.isTask { parts.append(take.isComplete ? "completed Task" : "Task") }
        if take.timeReminder != nil { parts.append("Reminder") }
        return parts.isEmpty ? "Note" : parts.joined(separator: ", ")
    }
}

#Preview("Take circles — Night") {
    let reminder = TimeReminder(scheduledDate: .now, notificationIdentifier: "x")
    return HStack(spacing: 16) {
        TakeCircleView(take: Take(blocks: [.textLine("Note")]), diameter: 44)
        TakeCircleView(take: Take(blocks: [.checkItem("Task")]), diameter: 44)
        TakeCircleView(take: { var t = Take(blocks: [.textLine("Remind")]); t.timeReminder = reminder; return t }(), diameter: 44)
        TakeCircleView(take: Take(blocks: [.textLine("Obie")], isObie: true), diameter: 44)
        TakeCircleView(take: { var t = Take(blocks: [.checkItem("All")]); t.timeReminder = reminder; return t }(), diameter: 44)
    }
    .padding()
    .background(Color.ckBackground)
    .preferredColorScheme(.dark)
}

#Preview("Take circles — Daylight") {
    let reminder = TimeReminder(scheduledDate: .now, notificationIdentifier: "x")
    return HStack(spacing: 16) {
        TakeCircleView(take: Take(blocks: [.textLine("Note")]), diameter: 44)
        TakeCircleView(take: Take(blocks: [.checkItem("Task")]), diameter: 44)
        TakeCircleView(take: { var t = Take(blocks: [.textLine("Remind")]); t.timeReminder = reminder; return t }(), diameter: 44)
        TakeCircleView(take: Take(blocks: [.textLine("Obie")], isObie: true), diameter: 44)
    }
    .padding()
    .background(Color.ckBackground)
    .preferredColorScheme(.light)
}
