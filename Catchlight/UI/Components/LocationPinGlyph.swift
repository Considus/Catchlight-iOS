//
//  LocationPinGlyph.swift
//  Catchlight (iOS app target)
//
//  A custom map-marker glyph — a teardrop balloon with an inner ring — for location
//  reminders (owner 2026-06-24). Drawn as a STROKED Shape, not an SF Symbol or a PNG, so
//  it tints with `foregroundStyle`/the ember palette and stays crisp at any size, matching
//  the thin-outline style of the card's bell/clock glyphs. The bulb's major arc is emitted
//  as an explicit polyline so the outline never depends on SwiftUI's ambiguous `addArc`
//  winding direction.
//

import SwiftUI

/// The marker outline + inner ring as a single path (so one stroke renders both). Drawn in
/// the given rect: bulb at the top filling the width, point at the bottom, ring centred in
/// the bulb. Intended aspect ~0.72 wide : 1 tall (a marker is taller than it is wide).
struct LocationPinShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // Inset so the stroke isn't clipped at the frame edge. All maths in Double to avoid
        // CGFloat/Double trig overload ambiguity; cast back only at CGPoint/CGRect.
        let inset = Double(rect.width) * 0.08
        let minX = Double(rect.minX) + inset
        let minY = Double(rect.minY) + inset
        let width = Double(rect.width) - inset * 2
        let height = Double(rect.height) - inset * 2
        let radius = width * 0.5                         // bulb radius = half the (inset) width
        let cx = minX + radius
        let cy = minY + radius                           // bulb sits at the top
        let tipY = minY + height                         // the point, at the bottom
        let d = tipY - cy
        guard d > radius else { return p }

        func point(_ angle: Double) -> CGPoint {
            CGPoint(x: CGFloat(cx + radius * cos(angle)), y: CGFloat(cy + radius * sin(angle)))
        }
        let tip = CGPoint(x: CGFloat(cx), y: CGFloat(tipY))
        let theta = acos(radius / d)                     // half-angle of the tangent gap
        let aLeft = Double.pi / 2 + theta                // lower-left tangent point
        let aRight = Double.pi / 2 - theta               // lower-right tangent point

        p.move(to: tip)
        p.addLine(to: point(aLeft))
        // Major arc: lower-left → up and over the top → lower-right, as a polyline (the long
        // way round, through the top — winding-safe, no reliance on addArc's direction flag).
        let steps = 48
        let end = aRight + 2 * Double.pi
        for i in 1...steps {
            p.addLine(to: point(aLeft + (end - aLeft) * Double(i) / Double(steps)))
        }
        p.addLine(to: tip)
        p.closeSubpath()

        // Inner ring — the marker "hole".
        let innerR = radius * 0.42
        p.addEllipse(in: CGRect(x: CGFloat(cx - innerR), y: CGFloat(cy - innerR),
                                width: CGFloat(innerR * 2), height: CGFloat(innerR * 2)))
        return p
    }
}

/// The marker glyph at a given cap height, stroked in `color` to match the sibling glyphs.
struct LocationPinGlyph: View {
    var color: Color
    var size: CGFloat = 13
    var lineWidth: CGFloat = 1.0

    var body: some View {
        LocationPinShape()
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .frame(width: size * 0.72, height: size)
    }
}

#Preview("Location pin glyph") {
    HStack(spacing: 16) {
        LocationPinGlyph(color: .primary, size: 13)
        LocationPinGlyph(color: .orange, size: 28)
        LocationPinGlyph(color: .secondary, size: 48)
    }
    .padding()
}
