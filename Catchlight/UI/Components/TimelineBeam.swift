//
//  TimelineBeam.swift
//  Catchlight (iOS app target)
//
//  The timeline's wire, as a BEAM of light rather than a drawn line (owner
//  2026-08-16, D-207). This supersedes the three dotted tracks of D-112: the spine
//  is no longer a drawn line with a screen-fixed dotted overlay, it is a shaft of
//  light with a hot core, a bloom, and haze in the air around it.
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
/// 🚨 THE TWO MODES USE DIFFERENT TECHNIQUES ON PURPOSE, AND THAT IS THE WHOLE LESSON
/// OF THIS FILE. One shared treatment was tried and it cost Night its beam: fixing
/// Daylight dragged Night along with it until the owner's verdict went from "perfect"
/// to "it looks like a pole, not light". Light on a dark ground and light on a light
/// ground are not the same problem and do not have the same answer.
///
/// NIGHT — ADDITIVE. Core, bloom and haze composited with `.plusLighter` so the layers
/// bloom into one another and into the page. This is what makes it read as LIGHT rather
/// than as an object, and it is the version the owner approved. Do not "unify" it.
///
/// DAYLIGHT — OPAQUE, OVER ITS OWN GROUND. Additive cannot work on Paper: there are
/// about ten steps of luminance between #F7F4EF and white, so adding light clips
/// everything it covers to flat white — the "blown out" look. Instead the light is
/// composited over its OWN copy of the page colour, flattened, and feathered only at
/// the very edge:
///
///     ground (ckBackground) + light  ->  compositingGroup  ->  soft-edge mask
///
/// so the shaft is the same wherever it goes, the bloom keeps its transparency (to the
/// beam's own ground rather than to the timeline), and the white core has warm shoulders
/// to be white against.
struct TimelineBeam: View {
    @Environment(\.colorScheme) private var scheme

    /// The LAYOUT footprint, constant in both modes even though Daylight draws a much
    /// narrower shaft inside it. Callers place the beam by its centre
    /// (`x - width / 2`); a footprint that changed with the colour scheme would shift
    /// the beam sideways on a light/dark switch, off the spine and away from the Add
    /// button it plugs into.
    static let width: CGFloat = 36

    /// What Daylight actually fills. Halved twice at the owner's request (18 -> 9): the
    /// beam passes IN FRONT of the shutter, and IMPORTANT is blade 0 at twelve o'clock,
    /// so a wide beam runs straight down the one marker it must not hide.
    static let daylightWidth: CGFloat = 11

    /// Night's haze is the light in the AIR. It belongs in the open gutter and NOT over
    /// the shutter: 36pt of additive warmth is as wide as the Iris itself, so crossing
    /// one it stopped reading as a beam passing in front and washed the whole upper half
    /// of the blades.
    var includesHaze: Bool = true

    var body: some View {
        Group {
            if scheme == .dark { night } else { daylight }
        }
        .frame(width: Self.width)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Night — additive

    private var night: some View {
        ZStack {
            if includesHaze { band(36, Color(hex: 0xC9A96E).opacity(0.10)) }
            band(12, Color(hex: 0xE9CB8C).opacity(0.55))
            band(2.8, Color(white: 1.0).opacity(0.95))
        }
        .blendMode(.plusLighter)
    }

    /// One layer: transparent at both edges, full strength down the middle, so the
    /// layers stack into a single soft-edged shaft rather than three hard bands.
    private func band(_ width: CGFloat, _ colour: Color) -> some View {
        LinearGradient(colors: [colour.opacity(0), colour, colour.opacity(0)],
                       startPoint: .leading, endPoint: .trailing)
            .frame(width: width)
    }

    // MARK: Daylight — opaque, over its own ground

    /// 🚨 WHITE, AT GRADED ALPHA, STRAIGHT ONTO WHATEVER IS THERE. No warm shoulders and
    /// no substituted ground — both were tried and both failed in ways worth recording:
    ///
    ///   • WARM shoulders are darker than the white core AND darker than Paper, so they
    ///     framed the core instead of fading from it. The owner read them as "two
    ///     stripes", which is exactly what they were.
    ///
    ///   • Compositing over the beam's OWN Paper ground made it uniform, but Paper is
    ///     lighter than the shutter's blades — so across the feather the beam swapped a
    ///     grey blade for near-Paper and that showed, making the beam look like it
    ///     WIDENED as it crossed an Iris. Tightening the feather removed the widening and
    ///     gave it hard edges instead: a bar, not a glow.
    ///
    /// White at graded alpha has neither fault. It always lightens toward white and
    /// always falls off to whatever it crosses, so it reads as one glow everywhere — a
    /// whisper over Paper, plainer over a blade, which is what light actually does.
    private static let daylightLight: [Gradient.Stop] = [
        .init(color: .white.opacity(0),    location: 0.00),
        .init(color: .white.opacity(0.18), location: 0.18),
        .init(color: .white.opacity(0.55), location: 0.33),
        .init(color: .white.opacity(0.92), location: 0.44),
        .init(color: .white,               location: 0.50),
        .init(color: .white.opacity(0.92), location: 0.56),
        .init(color: .white.opacity(0.55), location: 0.67),
        .init(color: .white.opacity(0.18), location: 0.82),
        .init(color: .white.opacity(0),    location: 1.00)
    ]

    private var daylight: some View {
        LinearGradient(stops: Self.daylightLight, startPoint: .leading, endPoint: .trailing)
            .frame(width: Self.daylightWidth)
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
        // White in BOTH modes (owner 2026-08-16). Dark specks inside a white glow read as
        // holes in the light rather than dust lit by it; the beam is white on Paper now,
        // so the dust in it has to be too.
        let colour = scheme == .dark ? Color(hex: 0xFFF4D6) : Color(hex: 0xFFFFFF)
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
    /// Whether the beam crosses this Iris.
    ///
    /// False in the EDITOR, where the gutter beam is deliberately hidden (owner
    /// 2026-06-17: a wire reads as a remnant behind a focused Take). Threading an Iris
    /// with a beam that exists nowhere else on the screen leaves a stub of light with
    /// nothing above or below it. The lean, the lighting and the cast shadow all stay —
    /// only the beam goes.
    var showsBeam: Bool = true

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
                if showsBeam { beam }
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
