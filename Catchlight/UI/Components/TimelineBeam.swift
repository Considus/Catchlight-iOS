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
        // Daylight is now the SAME KIND of thing as Night — light added to the ground,
        // brightest at the core — rather than a dark shape drawn on it (owner
        // 2026-08-16). A white core inside a DARKER warm halo was the odd hybrid: half
        // glow, half drawn rod.
        //
        // The trade is honest and worth knowing. Paper is #F7F4EF, so an additive beam
        // has about eight steps of luminance headroom before it clips to white — the
        // glow is real but it is subtle, and the warmth mostly survives as the blue
        // channel lagging rather than as visible amber. That is what a bright warm light
        // on white paper actually looks like; it is not a tuning failure.
        : BeamStyle(coreWidth: 4.1, bloomWidth: 12.8, hazeWidth: 30,
                    core:  Color(hex: 0xFFFFFF).opacity(0.98),
                    bloom: Color(hex: 0xE9CB8C).opacity(0.42),
                    haze:  Color(hex: 0xC9A96E).opacity(0.12),
                    additive: true)
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

    /// The haze is the light in the AIR. It belongs in the open gutter and NOT over the
    /// shutter: 36pt of additive warmth is as wide as the Iris itself, so crossing one it
    /// stopped reading as a beam passing in front and started washing the whole upper
    /// half of the blades (owner, on device 2026-08-16 — "right on the light-beam").
    /// Daylight never showed it because that beam is not additive.
    ///
    /// Core and bloom still cross the Iris: those are the beam itself, and a beam in
    /// front of metal does light it.
    var includesHaze: Bool = true

    /// The beam's footprint, the SAME in both modes even though the haze inside it is
    /// not. Callers place it by its centre (`x - TimelineBeam.width / 2`), and a width
    /// that changed with the colour scheme would shift the beam sideways on a
    /// light/dark switch — off the spine, and away from the Add button it plugs into.
    static let width: CGFloat = 36

    var body: some View {
        let s = BeamStyle.resolve(scheme)
        ZStack {
            if includesHaze { band(s.hazeWidth, s.haze) }
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
        TimelineBeam(includesHaze: false)
            .frame(height: diameter / 2 - leanTop)
            .offset(x: diameter / 2 - TimelineBeam.width / 2, y: leanTop)
    }
}

/// Masks the GUTTER beam across the shutter, so a row can paint its own threaded beam
/// without the two adding up.
///
/// 🚨 Place this UNDER the card, as the row's first element. Two reasons, both learned
/// the hard way: the gutter beam runs behind the whole timeline and shows through the
/// open aperture, so with the row's own beam on top, `.plusLighter` adds them into a
/// blown-out bar over every Iris and nowhere else; and painted OVER the card instead of
/// under it, this cuts a clean rectangle out of the card's own shadow — which on Paper
/// reads as a pale block hanging above every Iris.
///
/// This is the old crown occluder, reinstated for a completely different reason. It
/// used to hide the dotted spine bleeding through the aperture, which threading makes
/// desirable rather than a fault.
struct TimelineBeamOccluder: View {
    var diameter: CGFloat = CatchlightLayout.circleDiameter

    var body: some View {
        let leanTop = (diameter - diameter * IrisDepth.foreshorten) / 2
        Rectangle()
            .fill(Color.ckBackground)
            .frame(width: TimelineBeam.width, height: diameter / 2 - leanTop)
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
