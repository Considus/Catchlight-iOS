//
//  CatchlightMark.swift
//  Catchlight
//
//  The Catchlight icon art as a view: a ring with a notch at upper right, and the dot in
//  the notch. It is drawn from the geometry of the brand's app icon (64 grid, in
//  `Brand_System/svg/app-icon`) in the Scene's `iconRing`, `iconDot` and `iconBg` tokens, so
//  it follows the Scene and needs no file per colour.
//
//  `.tile` is the app icon: the `iconBg` tile with the surface corner, for a page ground
//  (About, the lock screen, the privacy curtain). `.bare` is the ring and dot alone, sized so
//  the ring's outer edge fills the box, for the colour field (onboarding), as in the lockup.
//  The launch screen cannot read the Scene, so it shows the Cobalt tile in the
//  `catchlight-icon` asset.
//

import SwiftUI

struct CatchlightMark: View {
    enum Style { case tile, bare }

    /// The icon art on the brand's 64 grid.
    enum Art {
        static let grid: CGFloat = 64
        static let ringCentre = CGPoint(x: 32, y: 33)
        static let ringRadius: CGFloat = 15
        static let ringStroke: CGFloat = 7.5
        static let dotCentre = CGPoint(x: 43.6, y: 21.4)
        static let dotRadius: CGFloat = 5.1
        static let notchRadius: CGFloat = 8.1
        /// The ring's outer diameter: what a `.bare` mark fits to its box.
        static let ringOuterDiameter: CGFloat = (ringRadius + ringStroke / 2) * 2
    }

    var style: Style
    var size: CGFloat = 72

    /// Grid units to points, and where the grid's origin lands, for a style and box.
    static func placement(style: Style, size: CGFloat) -> (scale: CGFloat, origin: CGPoint) {
        switch style {
        case .tile:
            return (size / Art.grid, .zero)
        case .bare:
            let scale = size / Art.ringOuterDiameter
            return (scale, CGPoint(x: size / 2 - Art.ringCentre.x * scale,
                                   y: size / 2 - Art.ringCentre.y * scale))
        }
    }

    var body: some View {
        Canvas { context, _ in
            let (scale, origin) = Self.placement(style: style, size: size)
            func point(_ p: CGPoint) -> CGPoint {
                CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale)
            }
            func circle(_ centre: CGPoint, _ radius: CGFloat) -> Path {
                let c = point(centre), r = radius * scale
                return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            }
            if style == .tile {
                let tile = Path(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                                cornerRadius: CatchlightLayout.surfaceRadius, style: .continuous)
                context.fill(tile, with: .color(Color.ckIconBg))
            }
            let ring = circle(Art.ringCentre, Art.ringRadius)
                .strokedPath(StrokeStyle(lineWidth: Art.ringStroke * scale))
                .subtracting(circle(Art.dotCentre, Art.notchRadius))
            context.fill(ring, with: .color(Color.ckIconRing))
            context.fill(circle(Art.dotCentre, Art.dotRadius), with: .color(Color.ckIconDot))
        }
        .frame(width: size, height: size)
    }
}
