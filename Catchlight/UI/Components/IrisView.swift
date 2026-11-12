//
//  IrisView.swift
//  Catchlight (iOS app target)
//
//  The Take "Iris": the small mark on every timeline row (and in the Focus row,
//  the conflict view and the edit card) that shows a Take's types at a glance.
//
//  A flat rounded square whose outline is cut into six equal lights. A lit light
//  is a thicker `ckLit` stroke, an unlit one a thin `ckUnlit` stroke (2:1). Clockwise from
//  the top: Important, Task, Audio, Note, Image, Reminder. Inside sits one shape:
//  the Take's single type, four dots for two or more types, the Note shape for
//  none. An Obie adds an inner rounded square in `ckLit`.
//
//  The geometry is in `IrisGeometry` (44 x 44 units, scaled by `diameter / 44`), shared
//  with the widgets. Pure rendering; callers attach taps and long-presses.
//

import SwiftUI
import CatchlightCore

struct IrisView: View {
    let take: Take
    var diameter: CGFloat = CatchlightLayout.circleDiameter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: State

    /// The stroke of an unlit light: the softer `unlit` role, 2:1 on every surface.
    static let unlitLightColor: Color = .ckUnlit

    /// Which lights are lit for `take`.
    static func lights(for take: Take) -> [IrisLight: Bool] {
        // Audio and Image are wired for attachments, which v1.0 never has: nothing
        // user-facing may name them until they ship.
        let hasAudio = take.attachments.contains { $0.mimeType.hasPrefix("audio/") }
        let hasImage = take.attachments.contains { $0.mimeType.hasPrefix("image/") }
        return [
            .important: take.isImportant,
            .task: take.isTask,
            .audio: hasAudio,
            .note: take.isNote,
            .image: hasImage,
            .reminder: take.timeReminder != nil || take.locationReminder != nil
        ]
    }

    /// The inner shape for `take`. Important is never a type, and Note is the floor:
    /// it counts only when nothing else is on, so Note + Task shows the tick (R10).
    static func innerShape(for take: Take) -> IrisInnerShape {
        let lit = lights(for: take)
        let types: [(IrisLight, IrisInnerShape)] = [
            (.task, .task), (.reminder, .reminder), (.audio, .audio), (.image, .image)
        ]
        let active = types.filter { lit[$0.0] == true }
        switch active.count {
        case 0: return .note
        case 1: return active[0].1
        default: return .fourDots
        }
    }

    /// The Iris's inside: the plain card colour on every Take, Important ones included, so its
    /// marks keep their contrast on the tinted card; the Obie's matches its own tinted card
    /// (owner 2026-11-12).
    static func fill(for take: Take) -> Color {
        take.isObie ? .ckCardImportantSurface : .ckCard
    }

    // MARK: View

    var body: some View {
        let state = IrisMorphState(shape: Self.innerShape(for: take), lit: Self.lights(for: take))
        // Not Reduce Motion: one mark per Take, whose strokes move to the new state. A different
        // Take (a recycled row) replaces the mark without a transition, so rows never morph into
        // each other. Reduce Motion: no movement; each state is its own mark and fades in.
        let key: AnyHashable = reduceMotion ? AnyHashable(IrisMarkKey(id: take.id, state: state)) : AnyHashable(take.id)
        ZStack {
            IrisMark(values: state.vector,
                     fill: Self.fill(for: take),
                     isObie: take.isObie)
                .id(key)
                .transition(reduceMotion ? .opacity : .identity)
        }
        .animation(Self.morphAnimation(held: IrisMorphHold.isHeld(take.id), reduceMotion: reduceMotion), value: state)
        .frame(width: diameter, height: diameter)
        // Decorative in every host: rows expose a combined label, and the callers that
        // want the Iris to speak (editor footer) label their own wrapper. 🚨 Do NOT add
        // `.accessibilityHidden(true)` here — on iOS 18.6/26.3 the modifier MATERIALIZES
        // an anonymous, selectable VoiceOver element for this non-textual view instead of
        // hiding it (measured by AX-tree dump, audit 2026-08 §15; removing it removes the
        // element). Shape/gradient/canvas content vends nothing by itself.
    }

    /// A spoken description of the active types, for callers that DO want the circle
    /// to announce itself (e.g. the edit footer).
    ///
    /// `includesObie: false` is for callers whose own label already says "Obie"
    /// (the Iris label helper) — the word must not be spoken twice in one breath
    /// (owner device pass, audit 2026-08 §15i). On that path an empty list returns
    /// "" rather than the "Note" fallback: an Obie carrying no other quality is not
    /// a Note, and the caller's intro stands alone.
    static func activityDescription(for take: Take, includesObie: Bool = true) -> String {
        var parts: [String] = []
        if take.isObie && includesObie { parts.append(String(localized: "Obie")) }
        if take.isImportant { parts.append(String(localized: "Important")) }
        if take.isNote { parts.append(String(localized: "Note")) }
        if take.isTask { parts.append(take.isComplete ? String(localized: "completed Task") : String(localized: "Task")) }
        if take.timeReminder != nil || take.locationReminder != nil { parts.append(String(localized: "Reminder")) }
        if parts.isEmpty { return includesObie ? String(localized: "Note") : "" }
        return parts.joined(separator: ", ")
    }
}

extension IrisView {
    /// How the Iris moves to a new state: the shape morph, the Reduce Motion fade, or (held)
    /// a plain switch.
    static func morphAnimation(held: Bool, reduceMotion: Bool) -> Animation? {
        if held { return nil }
        return reduceMotion ? CatchlightMotion.reduced : CatchlightMotion.shape
    }
}

/// One change, one morph (art director 2026-11-11). A change made in the Focus row morphs in the
/// row's own Iris, where the user tapped. The card's Iris then switches under the row's fade
/// instead of morphing a second time beneath it: the two layers overlapped and showed both marks
/// at once for about 0.3s. Every other route (the editor, sync) still morphs the card.
@MainActor
enum IrisMorphHold {
    /// Long enough to cover the row's close and the store's update reaching the card. A later
    /// change to the same Take, from any route, morphs as usual.
    static let window: TimeInterval = 1.5
    private static var heldUntil: [UUID: Date] = [:]

    static func hold(_ id: UUID, now: Date = Date()) {
        heldUntil = heldUntil.filter { $0.value > now }
        heldUntil[id] = now.addingTimeInterval(window)
    }

    static func isHeld(_ id: UUID, now: Date = Date()) -> Bool {
        guard let until = heldUntil[id] else { return false }
        return now < until
    }
}

/// A fixed-length list of numbers that SwiftUI can interpolate, one straight line each.
struct IrisVector: VectorArithmetic {
    var values: [Double]

    static var zero: IrisVector { IrisVector(values: []) }

    private static func combine(_ a: IrisVector, _ b: IrisVector, _ f: (Double, Double) -> Double) -> IrisVector {
        // `zero` is the empty list: it stands for all zeros of the other's length.
        let n = max(a.values.count, b.values.count)
        return IrisVector(values: (0..<n).map { f(i(a, $0), i(b, $0)) })
    }
    private static func i(_ v: IrisVector, _ k: Int) -> Double { k < v.values.count ? v.values[k] : 0 }

    static func + (a: IrisVector, b: IrisVector) -> IrisVector { combine(a, b, +) }
    static func - (a: IrisVector, b: IrisVector) -> IrisVector { combine(a, b, -) }
    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}

/// What the Iris shows: the inner shape and which lights are lit.
struct IrisMorphState: Hashable {
    let shape: IrisInnerShape
    let lit: [Bool]

    init(shape: IrisInnerShape, lit: [IrisLight: Bool]) {
        self.shape = shape
        self.lit = IrisLight.allCases.map { lit[$0] == true }
    }

    /// The numbers that move: 20 segment coordinates, 5 segment opacities (padding is 0), the inner
    /// stroke width, and 6 light levels (0 unlit, 1 lit).
    var vector: IrisVector {
        var v: [Double] = []
        for seg in IrisGeometry.morphSegments(shape) { v += seg.map(Double.init) }
        let real = IrisGeometry.realSegmentCount(shape)
        v += (0..<IrisGeometry.morphSegmentCount).map { $0 < real ? 1 : 0 }
        v.append(Double(IrisGeometry.innerWidth(shape)))
        v += lit.map { $0 ? 1 : 0 }
        return IrisVector(values: v)
    }
}

private struct IrisMarkKey: Hashable {
    let id: UUID
    let state: IrisMorphState
}

/// The Iris drawn from interpolated numbers. A `Canvas` does not animate by itself, so this
/// view carries the numbers as `animatableData` and SwiftUI redraws it every frame.
struct IrisMark: View, Animatable {
    var values: IrisVector
    let fill: Color
    let isObie: Bool

    var animatableData: IrisVector {
        get { values }
        set { values = newValue }
    }

    /// How many numbers a full vector holds: 20 segment coordinates, 5 opacities, the stroke
    /// width and 6 lights (`IrisMorphState.vector`).
    static let vectorLength = IrisGeometry.morphSegmentCount * 5 + 1 + IrisLight.allCases.count

    var body: some View {
        // SwiftUI may hand this view its vector's `zero`, the empty list, which stands for all
        // zeros: pad it, so it draws as nothing instead of reading past the end (measured: an
        // empty vector crashed the drawing with an index out of range).
        let v = values.values.count >= Self.vectorLength
            ? values.values
            : values.values + Array(repeating: 0, count: Self.vectorLength - values.values.count)
        Canvas { context, size in
            let s = min(size.width, size.height) / 44
            let outline = IrisGeometry.outline(scale: s)

            // The fill matches the card the Iris sits on: Important and Obie cards are raised.
            context.fill(outline, with: .color(fill))

            for (index, _) in IrisLight.allCases.enumerated() {
                let t = CGFloat(v[26 + index])
                context.stroke(IrisGeometry.light(index, of: outline),
                               with: .color(t >= 0.5 ? .ckLit : IrisView.unlitLightColor),
                               style: StrokeStyle(lineWidth: (IrisGeometry.unlitWidth + (IrisGeometry.litWidth - IrisGeometry.unlitWidth) * t) * s,
                                                  lineCap: .round))
            }

            if isObie {
                context.stroke(IrisGeometry.obieSquare(scale: s), with: .color(.ckLit),
                               lineWidth: IrisGeometry.obieSquareWidth * s)
            }

            let style = StrokeStyle(lineWidth: CGFloat(v[25]) * s, lineCap: .round, lineJoin: .round)
            let segs = (0..<IrisGeometry.morphSegmentCount).map { i in (0..<4).map { CGFloat(v[i * 4 + $0]) } }
            // Fully visible segments are one path, as before; a fading one is its own stroke.
            let solid = (0..<segs.count).filter { v[20 + $0] >= 1 }.map { segs[$0] }
            context.stroke(IrisGeometry.innerPath(segments: solid, scale: s),
                           with: .color(.ckTextPrimary), style: style)
            for i in 0..<segs.count where v[20 + i] > 0 && v[20 + i] < 1 {
                context.stroke(IrisGeometry.innerPath(segments: [segs[i]], scale: s),
                               with: .color(Color.ckTextPrimary.opacity(v[20 + i])), style: style)
            }
        }
    }
}

private struct IrisPreviewRow: View {
    var body: some View {
        let reminder = TimeReminder(scheduledDate: .now, notificationIdentifier: "x")
        HStack(spacing: 16) {
            IrisView(take: Take(blocks: [.textLine("Note")]), diameter: 44)
            IrisView(take: Take(blocks: [.checkItem("Task")], isNote: false), diameter: 44)
            IrisView(take: Take(blocks: [.textLine("Remind")], isNote: false, timeReminder: reminder), diameter: 44)
            IrisView(take: Take(blocks: [.textLine("Note and remind")], timeReminder: reminder), diameter: 44)
            IrisView(take: Take(blocks: [.textLine("Important")], isImportant: true), diameter: 44)
            IrisView(take: Take(blocks: [.textLine("Obie")], isObie: true), diameter: 44)
        }
        .padding()
        .background(Color.ckGround)
    }
}

#Preview("Iris, Dark") {
    IrisPreviewRow().preferredColorScheme(.dark)
}

#Preview("Iris, Light") {
    IrisPreviewRow().preferredColorScheme(.light)
}
