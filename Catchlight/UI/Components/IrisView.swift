//
//  IrisView.swift
//  Catchlight (iOS app target)
//
//  The Take "Iris": the small mark on every timeline row (and in the Focus row,
//  the conflict view and the edit card) that shows a Take's types at a glance.
//
//  A flat rounded square whose outline is cut into six equal lights. A lit light
//  is a thicker `ckLit` stroke, an unlit one a thin `ckOutline` stroke (3:1). Clockwise from
//  the top: Important, Task, Audio, Note, Image, Reminder. Inside sits one shape:
//  the Take's single type, four dots for two or more types, the Note shape for
//  none. An Obie adds an inner rounded square in `ckLit`.
//
//  All geometry is in a 44 x 44 unit space, scaled by `diameter / 44`. Pure
//  rendering; callers attach taps and long-presses.
//

import SwiftUI
import CatchlightCore

/// The six lights round the Iris outline, in clockwise order from the top.
enum IrisLight: CaseIterable {
    case important, task, audio, note, image, reminder
}

/// The shape drawn inside the Iris.
enum IrisInnerShape {
    case note, task, reminder, audio, image, fourDots
}

struct IrisView: View {
    let take: Take
    var diameter: CGFloat = CatchlightLayout.circleDiameter

    // MARK: State

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

    // MARK: Geometry (44 x 44 units)

    /// The outline: a rounded square from (1.5, 1.5) to (42.5, 42.5), corner radius 11,
    /// traced clockwise from the top centre so the trims below land on the right edges.
    private static func outline(scale s: CGFloat) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        let lo: CGFloat = 1.5, hi: CGFloat = 42.5, r: CGFloat = 11 * s
        var path = Path()
        path.move(to: p(22, lo))
        path.addArc(tangent1End: p(hi, lo), tangent2End: p(hi, hi), radius: r)
        path.addArc(tangent1End: p(hi, hi), tangent2End: p(lo, hi), radius: r)
        path.addArc(tangent1End: p(lo, hi), tangent2End: p(lo, lo), radius: r)
        path.addArc(tangent1End: p(lo, lo), tangent2End: p(hi, lo), radius: r)
        path.closeSubpath()
        return path
    }

    /// Light `index`, from (index*100 - 39)/600 to (index*100 + 39)/600 of the outline.
    /// Light 0 straddles the start of the path, so it is two trims.
    private static func light(_ index: Int, of outline: Path) -> Path {
        let from = CGFloat(index * 100 - 39) / 600
        let to = CGFloat(index * 100 + 39) / 600
        guard from < 0 else { return outline.trimmedPath(from: from, to: to) }
        var path = outline.trimmedPath(from: 1 + from, to: 1)
        path.addPath(outline.trimmedPath(from: 0, to: to))
        return path
    }

    /// Inner shape segments as [x1, y1, x2, y2] in a 24-unit grid.
    private static func segments(_ shape: IrisInnerShape) -> [[CGFloat]] {
        switch shape {
        case .note:     return [[7.5, 9, 16.5, 9], [7.5, 12, 16.5, 12], [7.5, 15, 13, 15]]
        case .task:     return [[7.2, 12.4, 10.4, 15.6], [10.4, 15.6, 16.8, 8.6]]
        case .reminder: return [[12, 12.6, 12, 6.2], [12, 12.6, 16.6, 15]]
        case .audio:    return [[7, 10.6, 7, 13.4], [9.5, 8.2, 9.5, 15.8], [12, 6.2, 12, 17.8],
                                [14.5, 8.6, 14.5, 15.4], [17, 10.6, 17, 13.4]]
        case .image:    return [[5.6, 17, 10, 12], [10, 12, 13.2, 15.6], [12.2, 14.6, 14.8, 11.6],
                                [14.8, 11.6, 18.4, 17], [16.2, 7.2, 17.4, 7.2]]
        case .fourDots: return [[9, 9, 9, 9], [15, 9, 15, 9], [9, 15, 9, 15], [15, 15, 15, 15]]
        }
    }

    /// The inner shape's path: the 24 grid mapped by translate(22,22) scale(1.3)
    /// translate(-12,-12) into 44 space, then by `s`.
    private static func innerPath(_ shape: IrisInnerShape, scale s: CGFloat) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: (22 + (x - 12) * 1.3) * s, y: (22 + (y - 12) * 1.3) * s)
        }
        var path = Path()
        for seg in segments(shape) {
            path.move(to: p(seg[0], seg[1]))
            path.addLine(to: p(seg[2], seg[3]))
        }
        return path
    }

    // MARK: View

    var body: some View {
        let lit = Self.lights(for: take)
        let shape = Self.innerShape(for: take)
        let isObie = take.isObie
        Canvas { context, size in
            let s = min(size.width, size.height) / 44
            let outline = Self.outline(scale: s)

            // The fill matches the card the Iris sits on: Important and Obie cards are raised.
            context.fill(outline, with: .color(take.isImportant ? .ckCardObieSurface : .ckCard))

            for (index, kind) in IrisLight.allCases.enumerated() {
                let isLit = lit[kind] == true
                context.stroke(Self.light(index, of: outline),
                               with: .color(isLit ? .ckLit : .ckOutline),
                               style: StrokeStyle(lineWidth: (isLit ? 3 : 1.5) * s, lineCap: .round))
            }

            if isObie {
                let inner = Path(roundedRect: CGRect(x: 5.2 * s, y: 5.2 * s, width: 33.6 * s, height: 33.6 * s),
                                 cornerRadius: 7.3 * s)
                context.stroke(inner, with: .color(.ckLit), lineWidth: 1.5 * s)
            }

            context.stroke(Self.innerPath(shape, scale: s),
                           with: .color(.ckTextPrimary),
                           style: StrokeStyle(lineWidth: (shape == .fourDots ? 3.4 : 1.9) * s,
                                              lineCap: .round, lineJoin: .round))
        }
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
