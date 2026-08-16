//
//  TimelineBeam.swift
//  Catchlight (iOS app target)
//
//  The timeline's wire, as a BEAM of light rather than a drawn line (owner
//  2026-08-16). This supersedes the three dotted tracks of D-112: the spine is no
//  longer a solid `ckSpineWire` line with a screen-fixed dotted overlay, it is a
//  shaft of light with a hot core, a bloom, and haze in the air around it.
//
//  Why a beam at all. The old spine was one flat tint at 35% with dots painted on
//  the glass — nothing in it was lit, so no amount of shading was going to make it
//  read as an object. A beam sidesteps the problem instead of losing to it: it has
//  no material to shade, it needs no contact shadow, and it earns the word Dailies.
//
//  🚨 THE TWO MODES ARE NOT THE SAME BEAM, AND THAT IS THE POINT. On Ink the beam
//  is ADDITIVE — it blooms, because light on a dark ground can. On Paper it cannot
//  go brighter than the page, so the identical geometry collapses to a hairline.
//  Measured 2026-08-16 on the design preview: the BODY of the beam (the part
//  clearing a luminance contrast of 45 against the ground) came out 8pt in Night
//  and 2pt in Daylight from the same numbers. Daylight therefore carries its width
//  in WARMTH instead of glow, with its own widths and its own alphas, retuned until
//  the two measured within a point of each other at every threshold:
//
//               halo (>6)   visible (>18)   body (>45)
//      Night       22            11             8
//      Daylight    21           11.5            7
//
//  If either mode is ever retuned, re-measure BOTH. Matching them by eye is exactly
//  the mistake this table exists to stop — at a loose threshold Daylight measured
//  WIDER than Night while plainly looking like a thin line, because almost none of
//  its width cleared the threshold at which an eye reads an edge.
//

import SwiftUI

// MARK: - Style

/// The beam's per-mode geometry and colour. Widths are FULL widths in points.
struct BeamStyle {
    let coreWidth: CGFloat
    let bloomWidth: CGFloat
    let hazeWidth: CGFloat
    let core: Color
    let bloom: Color
    let haze: Color
    /// Night composites additively so the layers bloom into one another. Daylight
    /// cannot — additive on Paper is invisible — so it paints normally.
    let additive: Bool

    static func resolve(_ scheme: ColorScheme) -> BeamStyle {
        scheme == .dark
        ? BeamStyle(coreWidth: 2.8, bloomWidth: 12, hazeWidth: 36,
                    core:  Color(white: 1.0).opacity(0.95),
                    bloom: Color(hex: 0xE9CB8C).opacity(0.55),
                    haze:  Color(hex: 0xC9A96E).opacity(0.10),
                    additive: true)
        : BeamStyle(coreWidth: 4.1, bloomWidth: 12.8, hazeWidth: 30,
                    core:  Color(hex: 0x654C21).opacity(0.98),
                    bloom: Color(hex: 0x967434).opacity(0.72),
                    haze:  Color(hex: 0x8C6C3A).opacity(0.20),
                    additive: false)
    }
}

// MARK: - The beam

/// A vertical shaft of light, centred in its frame. Give it the full `hazeWidth` to
/// draw in; the narrower layers centre themselves inside that.
///
/// Used in TWO places that must stay identical, exactly as the old spine was: the
/// gutter run behind the cards (`DailiesView`) and the short segment that crosses
/// each Iris (`UIKitTimeline`). Both build it from this one view, so they cannot
/// drift into two different beams.
struct TimelineBeam: View {
    @Environment(\.colorScheme) private var scheme

    /// The beam's footprint, the SAME in both modes even though the haze inside it is
    /// not. Callers place it by its centre (`x - TimelineBeam.width / 2`), and a width
    /// that changed with the colour scheme would shift the beam sideways on a
    /// light/dark switch — off the spine, and away from the Add button it plugs into.
    static let width: CGFloat = 36

    var body: some View {
        let s = BeamStyle.resolve(scheme)
        ZStack {
            band(s.hazeWidth, s.haze)
            band(s.bloomWidth, s.bloom)
            band(s.coreWidth, s.core)
        }
        .frame(width: Self.width)
        .blendMode(s.additive ? .plusLighter : .normal)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One layer: transparent at both edges, full strength down the middle, so the
    /// layers stack into a single soft-edged shaft rather than three hard bands.
    private func band(_ width: CGFloat, _ colour: Color) -> some View {
        LinearGradient(colors: [colour.opacity(0), colour, colour.opacity(0)],
                       startPoint: .leading, endPoint: .trailing)
            .frame(width: width)
    }
}

#Preview("Beam — Night") {
    ZStack { Color.ckBackground; TimelineBeam().frame(maxHeight: .infinity) }
        .preferredColorScheme(.dark)
}

#Preview("Beam — Daylight") {
    ZStack { Color.ckBackground; TimelineBeam().frame(maxHeight: .infinity) }
        .preferredColorScheme(.light)
}
