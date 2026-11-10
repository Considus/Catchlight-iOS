//
//  CatchlightWordmark.swift
//  Catchlight
//
//  The wordmark, drawn from the outlined brand SVG: the letters as one template image
//  in the text token, and the dot of the i as a circle in the `lit` token, so the mark
//  follows the chosen Scene and Light or Dark. The geometry is the SVG's own
//  (viewBox 0 -734 5171 927.55, dot at 3350, -644 with radius 90). Keep clear space of
//  at least the height of the "h" around it (marks-and-files.md).
//
//  The launch screen cannot read the Scene, so it shows the Cobalt files in the
//  `catchlight-wordmark` asset instead.
//

import SwiftUI

struct CatchlightWordmark: View {
    /// The SVG's viewBox, so the dot lands where the file puts it.
    private static let boxWidth: CGFloat = 5171
    private static let boxHeight: CGFloat = 927.55
    private static let boxTop: CGFloat = -734
    private static let dotCentre = CGPoint(x: 3350, y: -644)
    private static let dotRadius: CGFloat = 90

    /// Width over height of the mark.
    static let aspectRatio: CGFloat = boxWidth / boxHeight

    /// The size of the mark everywhere it is shown: onboarding, About, the privacy
    /// overlay and the launch screen (whose storyboard repeats these two numbers).
    static let width: CGFloat = 158
    static let height: CGFloat = width / aspectRatio
    /// The height of the "h", the unit of clear space (marks-and-files.md).
    static let hHeight: CGFloat = -boxTop / boxWidth * width
    /// Clear space above and below the wordmark (icon above it, tagline below): at least
    /// the "h" height.
    static let iconGap: CGFloat = 24
    /// The icon over the wordmark takes this much height in the opening chapter, as it
    /// did with the larger mark, so the hero below keeps its place.
    static let lockupHeight: CGFloat = 72 + 16 + 44

    /// On the colour field the letters take the on-field colour and the dot of the i the icon dot.
    @Environment(\.onColourField) private var onField

    var body: some View {
        Image("catchlight-wordmark-letters")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(onField ? Color.ckOnField : Color.ckTextPrimary)
            .overlay {
                GeometryReader { proxy in
                    let scale = proxy.size.width / Self.boxWidth
                    Circle()
                        .fill(onField ? Color.ckIconDot : Color.ckLit)
                        .frame(width: Self.dotRadius * 2 * scale, height: Self.dotRadius * 2 * scale)
                        .position(x: Self.dotCentre.x * scale,
                                  y: (Self.dotCentre.y - Self.boxTop) * scale)
                }
            }
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .frame(width: Self.width)
            // One element with one label: the letters and the dot read once.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Catchlight")
    }
}
