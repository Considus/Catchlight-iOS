//
//  OrientationTooltip.swift
//  Catchlight (iOS app target) — Phase 6 UI, Task 3.13
//
//  The reusable bubble used by all four first-run orientation hints. A rounded
//  rect with a small triangular arrow pointing at the relevant UI element, sitting
//  lightly on top of the live UI (no dim overlay). Same component shape for every
//  hint so the visual vocabulary stays consistent.
//

import SwiftUI

struct OrientationTooltip: View {

    let text: String
    var arrowEdge: Edge = .bottom
    var maxWidth: CGFloat = 220

    var body: some View {
        Text(text)
            .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .body))
            .foregroundStyle(Color.ckTextPrimary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: maxWidth)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.ckSurface)
                    OrientationTooltipArrow(edge: arrowEdge)
                        .fill(Color.ckSurface)
                        .frame(width: 14, height: 8)
                        .modifier(ArrowPlacement(edge: arrowEdge))
                }
            )
            .shadow(color: Color.black.opacity(0.18), radius: 8, y: 2)
            .accessibilityElement()
            .accessibilityLabel(text)
    }
}

/// A tiny isosceles triangle pointing along the requested edge. Drawn in a 14×8
/// rect; rotated/positioned by `ArrowPlacement` so the same shape works for any edge.
private struct OrientationTooltipArrow: Shape {
    let edge: Edge

    func path(in rect: CGRect) -> Path {
        var p = Path()
        // Base triangle points down (apex at bottom-centre). ArrowPlacement rotates
        // and positions it for each edge so the apex sits flush against the bubble.
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Positions and rotates the arrow so its apex pokes out of the requested bubble edge.
private struct ArrowPlacement: ViewModifier {
    let edge: Edge

    func body(content: Content) -> some View {
        switch edge {
        case .top:
            content
                .rotationEffect(.degrees(180))
                .offset(y: -8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .bottom:
            content
                .offset(y: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        case .leading:
            content
                .rotationEffect(.degrees(90))
                .offset(x: -8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .trailing:
            content
                .rotationEffect(.degrees(-90))
                .offset(x: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }
}

#Preview("Tooltip — Night") {
    VStack(spacing: 40) {
        OrientationTooltip(text: "What's your first Take?", arrowEdge: .bottom)
        OrientationTooltip(text: "Tap the Iris to shape this Take.", arrowEdge: .leading)
        OrientationTooltip(text: "Long press here for settings.", arrowEdge: .bottom)
        OrientationTooltip(
            text: "This is your Obie — your one most important Take. It stays at the top of everything until it's done.",
            arrowEdge: .top
        )
    }
    .padding()
    .background(Color.ckBackground)
    .preferredColorScheme(.dark)
}

#Preview("Tooltip — Daylight") {
    VStack(spacing: 40) {
        OrientationTooltip(text: "What's your first Take?", arrowEdge: .bottom)
        OrientationTooltip(text: "Tap the Iris to shape this Take.", arrowEdge: .leading)
    }
    .padding()
    .background(Color.ckBackground)
    .preferredColorScheme(.light)
}
