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
import CatchlightCore

// MARK: - The beam

/// A vertical shaft of light, centred in its frame.
///
/// 🚨 THE BEAM CARRIES ITS OWN GROUND. Earlier cuts blended straight onto whatever lay
/// behind — additive on Ink, drawn on Paper — so the beam was never the same thing
/// twice: one appearance over the page, another over the shutter, a different beam
/// again per colour scheme. Crossing an Iris it visibly changed, because it was partly
/// made of the Iris.
///
/// An opaque core fixes the centre but not the bloom, and a bloom needs transparency to
/// be a bloom (owner 2026-08-16). The way to have both is to composite the light over
/// its OWN copy of the page colour, flatten that, and then feather only the outermost
/// edge:
///
///     ground (ckBackground) + light gradient  ->  compositingGroup  ->  soft-edge mask
///
/// Everything inside the feather is therefore independent of what the beam passes over
/// — the bloom keeps its transparency, but it is transparent to the beam's own ground,
/// not to the timeline. Only the last ~2.5pt each side touches the real backdrop, at an
/// alpha low enough that no backdrop can visibly change it.
///
/// This is also what lets the white core work on Paper. As an additive glow it clipped
/// everything it covered to white — the "blown out" look — because on a near-white
/// ground additive light has nowhere to go. Over its own ground, the warm shoulders give
/// the white something to be white against, on either ground.
struct TimelineBeam: View {
    /// The beam's footprint. Callers place it by its centre (`x - TimelineBeam.width / 2`).
    /// Narrowed 36 -> 18 (owner 2026-08-16: the white was right, the width was not).
    static let width: CGFloat = 18
    /// The middle of the beam, where the feather is fully opaque — see the mask stops.
    static let opaqueWidth: CGFloat = width * 0.72

    /// The light itself, laid over the beam's own ground. Symmetric, so the centre of
    /// the frame is the centre of the light — see `snappedToPixel` for why that has to
    /// land on the pixel grid.
    private static let light: [Gradient.Stop] = [
        .init(color: Color(hex: 0xC9A96E).opacity(0),    location: 0.00),
        .init(color: Color(hex: 0xC9A96E).opacity(0.40), location: 0.20),
        .init(color: Color(hex: 0xEDD9A3).opacity(0.90), location: 0.36),
        .init(color: Color(hex: 0xFFFFFF),               location: 0.455),
        .init(color: Color(hex: 0xFFFFFF),               location: 0.545),
        .init(color: Color(hex: 0xEDD9A3).opacity(0.90), location: 0.64),
        .init(color: Color(hex: 0xC9A96E).opacity(0.40), location: 0.80),
        .init(color: Color(hex: 0xC9A96E).opacity(0),    location: 1.00)
    ]

    /// Opaque across the middle, feathering to nothing at the two edges. The feather is
    /// the ONLY part that sees the real backdrop.
    private static let feather: [Gradient.Stop] = [
        .init(color: .black.opacity(0), location: 0.00),
        .init(color: .black,            location: 0.14),
        .init(color: .black,            location: 0.86),
        .init(color: .black.opacity(0), location: 1.00)
    ]

    var body: some View {
        ZStack {
            Color.ckBackground                                   // the beam's own ground
            LinearGradient(stops: Self.light, startPoint: .leading, endPoint: .trailing)
        }
        .compositingGroup()                                      // flatten before masking
        .mask(LinearGradient(stops: Self.feather, startPoint: .leading, endPoint: .trailing))
        .frame(width: Self.width)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Dust

/// The dust a projector beam shows you.
///
/// 🚨 THIS MUST NOT SCROLL. Dust hangs in the room; scrolling a list does not move the
/// room. It gets that for free by living in `DailiesView`'s spine layer, which is
/// screen-fixed and sits BEHIND the timeline — the same layer that made the old dotted
/// spine hold still. Put it inside the collection and it would ride the content, and
/// counter-offsetting it every frame is a fight with the compositor that shows up as a
/// stutter, since the two land on different frames.
///
/// The dust is also the only thing on the timeline that moves of its own accord, so it
/// is the only thing here that needs gating — see `isHeld`.
struct BeamDust: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// Held still — but still drawn — when the owner has asked for less motion, when the
    /// battery is being conserved, or when the app is not the thing on screen. Owner-
    /// approved gates, 2026-08-16. Holding rather than hiding matters: the beam keeps its
    /// air, it simply stops drifting.
    private var isHeld: Bool {
        reduceMotion || lowPower || scenePhase != .active
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isHeld)) { timeline in
            Canvas { context, size in
                draw(in: context, size: size,
                     t: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: TimelineBeam.width)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onReceive(NotificationCenter.default.publisher(
            for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func draw(in context: GraphicsContext, size: CGSize, t: TimeInterval) {
        guard size.height > 0 else { return }
        var gc = context
        gc.blendMode = scheme == .dark ? .plusLighter : .normal
        let colour = scheme == .dark ? Color(hex: 0xFFF4D6) : Color(hex: 0x654C21)
        let cx = size.width / 2

        for m in Mote.all {
            // Falling, and wrapping over the visible run. Screen space throughout — no
            // scroll term anywhere, which is the whole point.
            let y = (m.y * size.height + CGFloat(t) * m.speed)
                .truncatingRemainder(dividingBy: size.height)
            let x = cx + m.x + sin(CGFloat(t) * m.wobbleRate + m.wobblePhase) * 1.4
            // Brightest in the core of the beam, dying towards the edge of the haze —
            // a mote only shows where there is light on it.
            let near = 1 - min(1, abs(m.x) / 12)
            let alpha = 0.12 + 0.80 * near * near
            gc.fill(Path(ellipseIn: CGRect(x: x - m.radius, y: y - m.radius,
                                           width: m.radius * 2, height: m.radius * 2)),
                    with: .color(colour.opacity(alpha)))
        }
    }

    /// One speck. Fixed set, generated once from a fixed seed so the drift is smooth
    /// rather than reshuffling on every redraw.
    private struct Mote {
        let x: CGFloat            // offset from the beam's centre
        let y: CGFloat            // 0…1 down the run
        let radius: CGFloat
        let speed: CGFloat        // points per second, DOWNWARD
        let wobblePhase: CGFloat
        let wobbleRate: CGFloat

        static let all: [Mote] = {
            var seed: UInt64 = 20260816
            func rnd() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((seed >> 33) % 100_000) / 100_000
            }
            return (0..<100).map { _ in
                let r = 0.4 + rnd() * 1.15
                return Mote(x: (rnd() - 0.5) * 24,
                            y: rnd(),
                            radius: r,
                            // Settling speed off the RADIUS, not rolled separately: a
                            // bigger mote falls faster. One speed for all of them reads
                            // as snow.
                            speed: 0.8 + 2.2 * r * r,
                            wobblePhase: rnd() * 6.283,
                            wobbleRate: 0.15 + rnd() * 0.35)
            }
        }()
    }
}

// MARK: - The shutter, threaded

/// The Iris as it appears ON THE TIMELINE: leaned back off the card plane, with the
/// beam threaded through it and a shadow cast onto the card.
///
/// 🚨 BOTH timeline rows must use this. There are two of them and it is easy to
/// believe there is one: the recycling `TimelineReadCell` draws every scrolling Take,
/// and the SwiftUI `TakeRowView` draws the PINNED OBIE (via `DailiesView.rowContent`).
/// The first cut of this work treated the cell alone, on a mistaken reading that
/// `TakeRowView` was dead — so the Obie kept the flat Iris and the old dotted wire
/// while every other row had been rebuilt (owner, on device 2026-08-16). Putting the
/// treatment in one view is what stops that happening again.
///
/// Draw order, and every part of it is load-bearing — see `TimelineBeamOccluder` for
/// the piece that has to sit under the CARD rather than in here:
///
///     shadow → shutter FAR half → beam → shutter NEAR half
///
/// The caller owns the card behind it, the occluder beneath that, and the gestures on
/// top; this view is pure rendering and takes no touches.
struct ThreadedIris: View {
    let take: Take
    var diameter: CGFloat = CatchlightLayout.circleDiameter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var foreshorten: CGFloat { IrisDepth.foreshorten }
    /// How far the leaned shutter's top edge sits below the untilted frame's top.
    private var leanTop: CGFloat { (diameter - diameter * foreshorten) / 2 }

    var body: some View {
        // The light is fixed in the WORLD, not on the Iris, so as a Take travels up the
        // screen its rim catchlight arcs round — which is what makes the timeline read
        // as a lit space rather than a list of stickers (owner 2026-08-16). The reader
        // is inside the shared view on purpose: computed at either call site, one of the
        // two rows would eventually be left without it, exactly as the Obie was left
        // without the tilt. Direction: WEST at the top of the screen, NORTH at the
        // bottom — see `IrisDepth.specularTravelDegrees`.
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                shadow
                half(.far, specular: specularOffset(geo))
                beam
                half(.near, specular: specularOffset(geo))
            }
        }
        .frame(width: diameter, height: diameter, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Degrees to turn this row's catchlight by, from where the Iris sits on SCREEN.
    /// Zero under Reduce Motion, which parks every light at ten o'clock.
    private func specularOffset(_ geo: GeometryProxy) -> Double {
        guard !reduceMotion else { return 0 }
        let screen = UIScreen.main.bounds.height
        guard screen > 0 else { return 0 }
        let t = min(1, max(0, geo.frame(in: .global).midY / screen))
        // Positive turns the light clockwise from ten o'clock, i.e. towards north. So
        // the sign is + as t grows: low on the screen means lit from above.
        return (Double(t) - 0.5) * 2 * IrisDepth.specularTravelDegrees
    }

    // MARK: Parts

    private enum Half { case far, near }

    private func half(_ which: Half, specular: Double) -> some View {
        TakeCircleView(take: take,
                       diameter: diameter,
                       specularOffset: specular,
                       apertureLitFromWithin: true)
            .frame(width: diameter, height: diameter)
            .rotation3DEffect(.degrees(-IrisDepth.tiltDegrees),
                              axis: (x: 1, y: 0, z: 0),
                              perspective: 1 / IrisDepth.perspective)
            .clipShape(HalfShape(isFar: which == .far))
    }

    /// The halves overlap by 4% rather than meeting exactly: a hairline cut lands on
    /// fractional pixels once tilted and opens a seam onto the card behind.
    private struct HalfShape: Shape {
        let isFar: Bool
        func path(in rect: CGRect) -> Path {
            // Generous horizontally — the Obie's outer ring and the catchlight bloom
            // both sit proud of the 44pt frame and must never be clipped.
            let pad = rect.width
            let y = isFar ? rect.minY - pad : rect.midY - rect.height * 0.04
            let h = isFar ? (rect.height * 0.46 + pad) : (rect.height * 0.54 + pad)
            return Path(CGRect(x: rect.minX - pad, y: y, width: rect.width + pad * 2, height: h))
        }
    }

    /// The shutter's shadow, cast onto the card.
    ///
    /// Its own flat ellipse rather than a `.shadow` on the tilted view, because a
    /// shadow lies on the CARD and must not be foreshortened with the object throwing
    /// it — a filter riding the tilt squashes exactly when it should be lengthening.
    ///
    /// 🚨 Drawn in BOTH modes: the DS §4 exception the owner approved 2026-08-16. §4
    /// forbids shadows against the dark GROUND, where they cannot be seen. This one
    /// lands on the CARD (Dusk), lighter than the page (Ink), so it registers; where it
    /// falls past onto Ink it is near-black on near-black and vanishes by itself.
    private var shadow: some View {
        let standoff = IrisDepth.standoff(diameter: diameter)
        return Ellipse()
            .fill(Color.ckIrisShade)
            .frame(width: diameter, height: diameter * foreshorten)
            .blur(radius: 7 + standoff * 0.34)
            .offset(x: 1 + standoff * 0.20, y: leanTop + 2 + standoff * 0.42)
    }

    /// The run of beam crossing the shutter: from the top of the LEANED shutter down to
    /// the card's top edge, where the card takes over the occluding. Started at the
    /// untilted top it leaked onto the page above the leaned ellipse.
    ///
    /// No separate spill layer — the beam is drawn OVER the far blades, so it lights
    /// them itself. A spill band on top of that was the same light counted twice.
    private var beam: some View {
        TimelineBeam()
            .frame(height: diameter / 2 - leanTop)
            .offset(x: diameter / 2 - TimelineBeam.width / 2, y: leanTop)
    }
}

/// Hides the GUTTER beam directly behind a shutter, so the row's own threaded beam is
/// the only one there.
///
/// Both runs are the same feathered shaft, and where they overlap — through the open
/// aperture — their soft edges composite twice and the beam reads slightly wider and
/// stronger across each Iris than it does anywhere else. Exactly the inconsistency the
/// opaque beam exists to remove.
///
/// Sized to the beam's OPAQUE middle rather than its full width, and hard-edged: a
/// full-width block showed as a page-coloured rectangle against the blades, because the
/// beam's own edges are feathered and could not cover it. At this width the block hides
/// under the solid part of the beam.
struct TimelineBeamOccluder: View {
    var diameter: CGFloat = CatchlightLayout.circleDiameter

    var body: some View {
        let leanTop = (diameter - diameter * IrisDepth.foreshorten) / 2
        Rectangle()
            .fill(Color.ckBackground)
            .frame(width: TimelineBeam.opaqueWidth, height: diameter / 2 - leanTop)
            .offset(y: leanTop)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
