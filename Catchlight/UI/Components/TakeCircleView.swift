//
//  TakeCircleView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  The Take "circle": the quadrant-filled disc that encodes a Take's active
//  activity types at a glance, and the Obie ring + specular dot. Used on every
//  timeline row, in search/sequence results, and in the edit footer. Pure
//  rendering — no gestures here; callers attach taps/long-presses.
//
//  Quadrant map — N/E/S/W DIAMOND (HiFi §2 Iris SVG, owner-confirmed 2026-06-14,
//  D-042). Each wedge is a 90° slice centred on a cardinal direction:
//    • Top    (N) → Note     (grey #BCBCBB Daylight / Catchlight@55% Night)
//    • Right  (E) → Task     (Ember — the warm accent, HiFi v1.6.9)
//    • Left   (W) → Remind   (#B5A283 Daylight / Glow@65% Night)
//    • Bottom (S) → Reserved (always empty)
//  (Supersedes the prior NE/SE/SW X-orientation and the DS §5.2 prose table.)
//

import SwiftUI
import CatchlightCore

/// One ANNULAR quadrant of the Iris (HiFi v1.7 — section 7). The Iris reads as a
/// RING with a hollow aperture, not a solid disc: each quadrant fills only the
/// band between an inner radius (`innerRatio × R`) and the outer radius, leaving
/// the centre empty (the camera aperture). The path runs along the outer arc,
/// back along the inner arc, and closes — never through the centre. Owner
/// 2026-06-15: aperture widened 0.44 → 0.55 of the radius ("the hole was a little
/// small") — the ring thins and the central hole opens up; the off-band ring's
/// `strokeBorder` width is kept in lock-step (see `body`).
private struct QuadrantSlice: Shape {
    /// Start/end angles in degrees, 0° = 3 o'clock, increasing clockwise in screen
    /// space (SwiftUI's y grows downward, so `Angle` clockwise matches visual).
    let startDegrees: Double
    let endDegrees: Double
    /// Inner radius as a fraction of the outer radius (owner 2026-06-15: 0.55,
    /// was v1.7's r8/r18 ≈ 0.44 — bigger aperture).
    var innerRatio: CGFloat = 0.55

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
            // edge to the inner radius, leaving the centre empty. The width MUST
            // track QuadrantSlice.innerRatio so the off-band and the filled wedges
            // share one inner edge: band = (1 − innerRatio)·R = (1 − 0.55)/2·D =
            // 0.225·D (was 0.28·D at innerRatio 0.44).
            Circle()
                .strokeBorder(Color.ckIrisOff, lineWidth: diameter * 0.225)

            // N/E/S/W diamond (D-042): each wedge is centred on a cardinal point,
            // spanning ±45° from it (corner-to-corner), so the slices read as a
            // diamond, not an X. 0° = 3 o'clock, increasing clockwise.
            // Top (N): Note — centred on -90°, spans -135°..-45°.
            if take.isNote {
                QuadrantSlice(startDegrees: -135, endDegrees: -45)
                    .fill(Quadrant.note(scheme))
            }
            // Right (E): Task — centred on 0°, spans -45°..45°.
            if take.isTask {
                QuadrantSlice(startDegrees: -45, endDegrees: 45)
                    .fill(Quadrant.task(scheme))
            }
            // Left (W): Remind — centred on 180°, spans 135°..225°.
            if hasReminder {
                QuadrantSlice(startDegrees: 135, endDegrees: 225)
                    .fill(Quadrant.reminder(scheme))
            }
            // Bottom (S, 45°..135°) is reserved — intentionally empty.

            // Hairline outer ring (HiFi v1.7 — section 7): a 0.75pt rim around
            // the annular quadrants. Daylight #E7E7E7 (v1.7's iris SVG uses the
            // near-identical #ECECEC); Night rides the divider/line token.
            Circle()
                .strokeBorder(Color.ckIrisRing, lineWidth: 0.75)

            // Obie: outer ring with a gap + a 3-layer specular catch.
            if take.isObie {
                // Ring: 2pt, sitting ~3pt OUTSIDE the disc edge (DS §5.1
                // obieRingWidth 2 / obieRingGap 3). `.stroke` on a larger circle
                // (overflowing the frame, as the HiFi Obie does) — was a ~2.6pt
                // strokeBorder at the rim with no gap.
                Circle()
                    .stroke(Quadrant.obieRing(scheme), lineWidth: 2)
                    .frame(width: diameter + 6, height: diameter + 6)
                // Specular catch (DS §5.4 / HiFi §2): a 3-layer dot upper-right
                // at ~0.305·D per axis — ground halo, warm core, bright catch —
                // replacing the flat single white pip.
                ZStack {
                    Circle().fill(scheme == .dark ? Color.black.opacity(0.35) : Color.ckInk.opacity(0.08))
                        .frame(width: diameter * 0.31, height: diameter * 0.31)
                    Circle().fill(Quadrant.obieRing(scheme))   // Ember (Daylight) / Glow (Night)
                        .frame(width: diameter * 0.19, height: diameter * 0.19)
                    Circle().fill(Color(hex: 0xFEFCF5))
                        .frame(width: diameter * 0.10, height: diameter * 0.10)
                }
                .offset(x: diameter * 0.305, y: -diameter * 0.305)
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
