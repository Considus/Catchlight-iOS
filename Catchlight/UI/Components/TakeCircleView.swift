//
//  TakeCircleView.swift
//  Catchlight (iOS app target)
//
//  The Take "Iris": the small disc on every timeline row (and in search/sequence
//  results and the edit footer) that encodes a Take's active types at a glance.
//
//  REDESIGN 2026-07 — the Iris is now a SIX-BLADE CAMERA SHUTTER (geometry from
//  `02_Design/.../Shutter-Aperture.svg`, normalised to a unit circle). It reads as
//  an aperture: six overlapping blades leaving a hexagonal centre, one shared
//  outline drawn on every blade — which, traced end to end, also outlines the hex.
//  Pure rendering; callers attach taps/long-presses. Size, position, and the
//  timeline around it are UNCHANGED from the previous Iris (44 pt, flat, on the
//  card's top edge) — this swap is the mark only.
//
//  Blade map (blade 0 sits at 12 o'clock; going clockwise). Keeps the old Iris's
//  N/E/S/W bearings and adds the two lower diagonals for features still to ship:
//    • 0  Top          → Important  (Shadow / Stone — indicator, shown on Obie too)
//    • 1  Upper-right  → Task       (Ember / amber)
//    • 2  Lower-right  → Image       (v1.1 image attachment — colour wired, off until built)
//    • 3  Bottom       → Note        (grey / cream)
//    • 4  Lower-left   → Voice       (audio attachment — colour wired, off until built)
//    • 5  Upper-left   → Remind      (#B5A283 tan / Glow — time OR place)
//  Inactive blades fall to the off-band tone (ckIrisOff) so the shutter always
//  reads as a complete six-blade aperture. Colours are the existing segment tokens
//  (`Quadrant`) verbatim; Voice/Image use two new warm-neutral fills, wired here so
//  they light automatically when those attachment types arrive.
//

import SwiftUI
import CatchlightCore

// MARK: - Blade geometry
//
// Each row: a start point followed by cubic curves as flat [c1x,c1y,c2x,c2y,ex,ey]
// groups, in a unit space centred on the disc (±1 = the outer arc / frame edge).
// Generated from the aperture SVG; do not hand-edit — regenerate from the source.
private let irisBladeData: [[CGFloat]] = [
    [0.4418, -0.2549, 0.3762, -0.3043, 0.3047, -0.3516, 0.2285, -0.3956, 0.1520, -0.4397, 0.0755, -0.4778, 0.0000, -0.5102, -0.1252, -0.5638, -0.2468, -0.6005, -0.3583, -0.6206, -0.6001, -0.6636, -0.7930, -0.6255, -0.8657, -0.5000, -0.8657, -0.5000, -0.8657, -0.5000, -0.8657, -0.5000, -0.6929, -0.7987, -0.3699, -0.9997, 0.0000, -0.9997, 0.1453, -0.9997, 0.2747, -0.8516, 0.3583, -0.6206, 0.3967, -0.5141, 0.4256, -0.3903, 0.4418, -0.2549],
    [0.7165, 0.0000, 0.6435, 0.0864, 0.5508, 0.1735, 0.4418, 0.2553, 0.4517, 0.1738, 0.4570, 0.0885, 0.4570, 0.0000, 0.4570, -0.0885, 0.4517, -0.1738, 0.4418, -0.2553, 0.4256, -0.3903, 0.3967, -0.5145, 0.3583, -0.6206, 0.2747, -0.8516, 0.1453, -0.9997, 0.0000, -0.9997, 0.3699, -0.9997, 0.6929, -0.7987, 0.8657, -0.5000, 0.8657, -0.5000, 0.8657, -0.5000, 0.8657, -0.5000, 0.9383, -0.3741, 0.8745, -0.1879, 0.7165, 0.0000],
    [0.9997, 0.0000, 0.9997, 0.1819, 0.9510, 0.3526, 0.8660, 0.5000, 0.8660, 0.5000, 0.8660, 0.5000, 0.8660, 0.5000, 0.7934, 0.6259, 0.6005, 0.6636, 0.3586, 0.6206, 0.2472, 0.6009, 0.1255, 0.5638, 0.0004, 0.5102, 0.0758, 0.4781, 0.1523, 0.4397, 0.2288, 0.3956, 0.3054, 0.3516, 0.3766, 0.3043, 0.4422, 0.2549, 0.5511, 0.1731, 0.6439, 0.0864, 0.7169, -0.0004, 0.8748, -0.1883, 0.9387, -0.3745, 0.8660, -0.5000, 0.8660, -0.5000, 0.8660, -0.5000, 0.8660, -0.5000, 0.9510, -0.3526, 0.9997, -0.1819, 0.9997, 0.0000],
    [0.8657, 0.5000, 0.6929, 0.7987, 0.3699, 0.9997, -0.0000, 0.9997, -0.1453, 0.9997, -0.2747, 0.8516, -0.3583, 0.6206, -0.3967, 0.5141, -0.4256, 0.3903, -0.4418, 0.2553, -0.3762, 0.3047, -0.3047, 0.3519, -0.2285, 0.3960, -0.1520, 0.4401, -0.0755, 0.4785, -0.0000, 0.5106, 0.1252, 0.5642, 0.2468, 0.6012, 0.3583, 0.6210, 0.6001, 0.6636, 0.7930, 0.6255, 0.8657, 0.5000, 0.8657, 0.5000, 0.8657, 0.5000, 0.8657, 0.5000],
    [0.0000, 0.9997, -0.3699, 0.9997, -0.6929, 0.7987, -0.8657, 0.5000, -0.8657, 0.5000, -0.8657, 0.5000, -0.8657, 0.5000, -0.9383, 0.3741, -0.8745, 0.1883, -0.7165, 0.0004, -0.6435, -0.0860, -0.5508, -0.1731, -0.4418, -0.2549, -0.4517, -0.1735, -0.4570, -0.0882, -0.4570, 0.0004, -0.4570, 0.0889, -0.4517, 0.1742, -0.4418, 0.2556, -0.4256, 0.3907, -0.3967, 0.5148, -0.3583, 0.6210, -0.2743, 0.8516, -0.1453, 0.9997, 0.0000, 0.9997],
    [0.0000, -0.5102, -0.0755, -0.4781, -0.1520, -0.4397, -0.2285, -0.3956, -0.3050, -0.3516, -0.3762, -0.3043, -0.4418, -0.2549, -0.5508, -0.1731, -0.6435, -0.0864, -0.7165, 0.0004, -0.8745, 0.1883, -0.9383, 0.3745, -0.8657, 0.5000, -0.8657, 0.5000, -0.8657, 0.5000, -0.8657, 0.5000, -0.9506, 0.3530, -0.9993, 0.1823, -0.9993, -0.0000, -0.9993, -0.1823, -0.9506, -0.3526, -0.8657, -0.5000, -0.8657, -0.5000, -0.8657, -0.5000, -0.8657, -0.5000, -0.7930, -0.6259, -0.6001, -0.6636, -0.3583, -0.6206, -0.2468, -0.6005, -0.1252, -0.5638, 0.0000, -0.5102],
]

/// One shutter blade, scaled from unit space to the frame.
private struct IrisBlade: Shape {
    let index: Int
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let cx = rect.midX, cy = rect.midY
        let d = irisBladeData[index]
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + x * r, y: cy + y * r) }
        var p = Path()
        p.move(to: P(d[0], d[1]))
        var k = 2
        while k + 6 <= d.count {
            p.addCurve(to: P(d[k + 4], d[k + 5]),
                       control1: P(d[k], d[k + 1]),
                       control2: P(d[k + 2], d[k + 3]))
            k += 6
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - View

struct TakeCircleView: View {
    let take: Take
    var diameter: CGFloat = CatchlightLayout.circleDiameter

    @Environment(\.colorScheme) private var scheme

    private enum Seg { case important, task, image, note, voice, remind }
    private let bladeSegments: [Seg] = [.important, .task, .image, .note, .voice, .remind]

    /// Voice/Image are wired for the v1.1 attachment features; the fills come from
    /// the redesign study (warm taupe / grey-sage). Until those features land the
    /// blades resolve to `false` below (attachments are always empty in v1.0).
    private static let voiceFill = Color(hex: 0xA99C8B)
    private static let imageFill = Color(hex: 0x9AA091)

    private func isActive(_ s: Seg) -> Bool {
        switch s {
        case .important: return take.isImportant
        case .task:      return take.isTask
        case .image:     return take.attachments.contains { $0.mimeType.hasPrefix("image/") }
        case .note:      return take.isNote
        case .voice:     return take.attachments.contains { $0.mimeType.hasPrefix("audio/") }
        case .remind:    return take.timeReminder != nil || take.locationReminder != nil
        }
    }

    private func color(_ s: Seg) -> Color {
        switch s {
        case .important: return Quadrant.important(scheme)
        case .task:      return Quadrant.task(scheme)
        case .image:     return Self.imageFill
        case .note:      return Quadrant.note(scheme)
        case .voice:     return Self.voiceFill
        case .remind:    return Quadrant.reminder(scheme)
        }
    }

    /// Active blade → its segment colour; inactive → the off-band tone, so the
    /// shutter always reads as a complete aperture.
    private func fill(for index: Int) -> Color {
        let s = bladeSegments[index]
        return isActive(s) ? color(s) : .ckIrisOff
    }

    /// The ONE outline used on the rim, every blade, and the hex centre. Thin GOLD on
    /// an Obie (owner 2026-07-04: a delicate gold tracery on the blades, distinct from
    /// the bolder outer ring), the WCAG-raised graphite otherwise.
    private var edge: Color { take.isObie ? Quadrant.obieRing(scheme) : .ckIrisRing }

    private var bladeLine: CGFloat { max(0.6, diameter * 0.017) }        // ~0.75 at 44 pt
    // Standard-width rim for EVERY Take (owner 2026-07-04): a thick gold rim on an
    // Obie read as a second thick gold ring next to the outer one. The bolder Obie
    // ring is the outer overlay only.
    private var rimLine: CGFloat { diameter * 0.024 }                    // ~1 pt at 44 pt
    /// Gap between the shutter's outer edge and the Obie ring — main's DS §5.1
    /// obieRingGap 3 (ring at `diameter + 6`). Tunable.
    private var obieRingGap: CGFloat { 3 }

    var body: some View {
        ZStack {
            // The hex aperture is left hollow (owner 2026-07-04): the earlier centre
            // catchlight sat at the Iris centre, which straddles the card's top edge,
            // so it read as a stray flare where the timeline meets the card.

            // Blade fills.
            ForEach(0..<6, id: \.self) { i in
                IrisBlade(index: i).fill(fill(for: i))
            }

            // Shared outline on every blade — traces the blade edges AND the hex.
            ForEach(0..<6, id: \.self) { i in
                IrisBlade(index: i).stroke(edge, lineWidth: bladeLine)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())                                   // clean circular silhouette
        .overlay(Circle().strokeBorder(edge, lineWidth: rimLine))
        // Obie ring — a larger gold ring OUTSIDE the shutter with a gap (owner 2026-07-04,
        // "as it was before"). In an overlay sized to `diameter + gap`, so — like the
        // old obieDecorations (D-042) — the larger ring can't inflate the disc's layout.
        .overlay {
            if take.isObie {
                Circle()
                    .stroke(Quadrant.obieRing(scheme), lineWidth: 2)
                    .frame(width: diameter + obieRingGap * 2, height: diameter + obieRingGap * 2)
            }
        }
        .accessibilityHidden(true)   // the row exposes a combined label; the disc is decorative there
    }

    /// A spoken description of the active types, for callers that DO want the circle
    /// to announce itself (e.g. the edit footer).
    static func activityDescription(for take: Take) -> String {
        var parts: [String] = []
        if take.isObie { parts.append("Obie") }
        if take.isImportant { parts.append("Important") }
        if take.isNote { parts.append("Note") }
        if take.isTask { parts.append(take.isComplete ? "completed Task" : "Task") }
        if take.timeReminder != nil || take.locationReminder != nil { parts.append("Reminder") }
        return parts.isEmpty ? "Note" : parts.joined(separator: ", ")
    }
}

#Preview("Iris — Night") {
    let reminder = TimeReminder(scheduledDate: .now, notificationIdentifier: "x")
    return HStack(spacing: 16) {
        TakeCircleView(take: Take(blocks: [.textLine("Note")]), diameter: 44)
        TakeCircleView(take: Take(blocks: [.checkItem("Task")]), diameter: 44)
        TakeCircleView(take: { var t = Take(blocks: [.textLine("Remind")]); t.timeReminder = reminder; return t }(), diameter: 44)
        TakeCircleView(take: Take(blocks: [.textLine("Important")], isImportant: true), diameter: 44)
        TakeCircleView(take: Take(blocks: [.textLine("Obie")], isObie: true), diameter: 44)
        TakeCircleView(take: { var t = Take(blocks: [.checkItem("All")]); t.timeReminder = reminder; return t }(), diameter: 44)
    }
    .padding()
    .background(Color.ckBackground)
    .preferredColorScheme(.dark)
}

#Preview("Iris — Daylight") {
    let reminder = TimeReminder(scheduledDate: .now, notificationIdentifier: "x")
    return HStack(spacing: 16) {
        TakeCircleView(take: Take(blocks: [.textLine("Note")]), diameter: 44)
        TakeCircleView(take: Take(blocks: [.checkItem("Task")]), diameter: 44)
        TakeCircleView(take: { var t = Take(blocks: [.textLine("Remind")]); t.timeReminder = reminder; return t }(), diameter: 44)
        TakeCircleView(take: Take(blocks: [.textLine("Important")], isImportant: true), diameter: 44)
        TakeCircleView(take: Take(blocks: [.textLine("Obie")], isObie: true), diameter: 44)
    }
    .padding()
    .background(Color.ckBackground)
    .preferredColorScheme(.light)
}
