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

    // MARK: View

    var body: some View {
        let lit = Self.lights(for: take)
        let shape = Self.innerShape(for: take)
        let isObie = take.isObie
        Canvas { context, size in
            let s = min(size.width, size.height) / 44
            let outline = IrisGeometry.outline(scale: s)

            // The fill matches the card the Iris sits on: Important and Obie cards are raised.
            context.fill(outline, with: .color(take.isImportant ? .ckCardObieSurface : .ckCard))

            for (index, kind) in IrisLight.allCases.enumerated() {
                let isLit = lit[kind] == true
                context.stroke(IrisGeometry.light(index, of: outline),
                               with: .color(isLit ? .ckLit : Self.unlitLightColor),
                               style: StrokeStyle(lineWidth: (isLit ? IrisGeometry.litWidth : IrisGeometry.unlitWidth) * s,
                                                  lineCap: .round))
            }

            if isObie {
                context.stroke(IrisGeometry.obieSquare(scale: s), with: .color(.ckLit),
                               lineWidth: IrisGeometry.obieSquareWidth * s)
            }

            context.stroke(IrisGeometry.innerPath(shape, scale: s),
                           with: .color(.ckTextPrimary),
                           style: StrokeStyle(lineWidth: IrisGeometry.innerWidth(shape) * s,
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
