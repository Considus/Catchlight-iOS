//
//  TakeRowView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  A single Take on the timeline: the quadrant circle (aligned to the spine) on the
//  left, the Take's first line of text on the right. Reminder Takes show their alarm
//  time as a small Fog label beside the circle. Gestures:
//    • tap circle      → open the petal fan (activity-type selector)
//    • long-press circle → designate as Obie (caller handles replacement confirm)
//    • tap text        → open the Take edit surface
//
//  All three callbacks are injected so this view is reusable across Dailies,
//  Search, and Sequence with no behavioural assumptions of its own.
//

import SwiftUI
import CatchlightCore

struct TakeRowView: View {
    let take: Take
    /// Tap on the Iris. The `CGPoint` is the Iris's centre in WINDOW (global)
    /// coordinates, captured by the tap recognizer, so the caller can bloom the
    /// petal fan in place at the tapped Iris rather than at the screen centre
    /// (section 8). The window coordinate space matches the full-screen petal-fan
    /// overlay's space in RootView.
    var onTapCircle: (CGPoint) -> Void = { _ in }
    var onLongPressCircle: () -> Void = {}
    var onTapText: () -> Void = {}
    /// Optional row actions (2026-06-10): when supplied, a context menu on the
    /// TEXT column offers "Mark as done" (Tasks only) and "Delete Take". The
    /// menu is deliberately NOT attached to the whole row — a row-level context
    /// menu's long-press recognizer preempts the circle's long-press (Obie
    /// designation). VoiceOver gets the same actions as named accessibility
    /// actions on the combined row element.
    var onToggleComplete: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    /// Revert the in-progress edit (owner 2026-06-17). Supplied only while this row
    /// is being edited in place, so "Discard changes" appears in the long-press menu
    /// (and as a VoiceOver action) exactly when there are edits to discard.
    var onDiscard: (() -> Void)? = nil
    /// Accessibility id for the Iris. Defaults to "take-iris"; the row being edited in
    /// place passes "editor-shape" — it plays the role the retired top-anchored
    /// editor's footer Iris did (tap = open the Focus ring), so the test contract and
    /// the semantic carry over.
    var irisIdentifier: String = "take-iris"
    /// Horizontal swipe offset applied to the CARD only (not the Iris). The Iris
    /// stays anchored on the spine so the timeline "wire" is unbroken while a Take
    /// is swiped for its actions — and so the future rings-on-a-wire still reads.
    /// Driven by `SwipeActionRow`; 0 everywhere the row isn't swipeable.
    var cardSwipeOffset: CGFloat = 0
    /// Edit-in-place (2026-06-17): when supplied, the read-only `TakeCardSurface` in
    /// the card slot is replaced by this live editor, IN POSITION — the Iris, spine,
    /// and card geometry are untouched (owner point 6). nil everywhere a row is at
    /// rest. The editor owns its own gestures + accessibility, so the row's tap /
    /// combined-element wrapping is dropped while editing.
    var editingCard: (() -> AnyView)? = nil

    private var firstLine: String {
        let line = take.plainText
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled Take" : trimmed
    }

    /// Composed VoiceOver label: text + status (+ progress) + reminder date.
    /// Example: "Buy milk. Task, 3 of 5 complete." or "The north star. Obie, your
    /// pinned Take. Note. Reminder set. Tomorrow at 3 PM."
    private var rowAccessibilityLabel: String {
        var parts: [String] = [firstLine, Self.statusDescription(for: take)]
        if let when = TakeCardSurface.reminderString(for: take) { parts.append(when) }
        return parts.filter { !$0.isEmpty }.joined(separator: ". ")
    }

    /// The spoken status (Obie / Task + progress / Note / reminder-set) portion of
    /// the row label, without the first line or the formatted reminder date.
    /// Internal + static so the progress/completed wording is unit-testable.
    static func statusDescription(for take: Take) -> String {
        var parts: [String] = []
        if take.isObie { parts.append("Obie, your pinned Take") }
        if take.isTask {
            if let progress = take.checklistProgress {
                parts.append("Task, \(progress.done) of \(progress.total) complete")
            } else {
                parts.append(take.isComplete ? "Task, complete" : "Task")
            }
        }
        if take.timeReminder != nil { parts.append("Reminder set") }
        if take.isNote && !take.isTask && take.timeReminder == nil { parts.append("Note") }
        return parts.joined(separator: ". ")
    }

    var body: some View {
        // Section 5 (HiFi v1.7 .card) — the text column rides a card SURFACE; the
        // Iris stays on the spine to its left, overlapping the card's leading
        // edge (`position:absolute; left:6px` in v1.7). The Iris is drawn on TOP
        // so its long-press still wins hit-testing; the card's text taps clear
        // the 44pt Iris touch frame.
        ZStack(alignment: .topLeading) {
            // The card fills from the row's leading edge, which DailiesView places
            // `cardSpineInset` (24) left of the spine — so the opaque card covers
            // the spine and the Iris nests into its top-left corner (HiFi §1). The
            // Iris is offset right to centre on the spine and UP by its radius to
            // STRADDLE the card's top edge (HiFi `.iw top:-18`): half sits in the
            // gap above, half over the corner; the card's 24pt top pad clears the
            // lower half so text never collides with it. Both offsets derive from
            // `cardSpineInset` + `circleDiameter`, so the card stays put when the
            // Iris is resized (previously the card was padded by the Iris diameter,
            // so enlarging the Iris pushed it right and narrowed it).
            cardColumn
                // Only the card slides on swipe; the Iris (below) keeps its spine
                // position so the wire stays threaded through it.
                .offset(x: cardSwipeOffset)
            // Crown occluder (owner 2026-06-16): the static dotted spine runs BEHIND
            // the whole row, so its bright dots were bleeding up through the Iris's
            // hollow aperture and making the crown look translucent. This page-coloured
            // 2pt segment sits at the wire column BEHIND the Iris: the opaque ring band
            // covers it (no notch), but in the aperture it reads as plain background —
            // blocking the dots behind, so the wire on top reads as clearly above the
            // ring. Same crown geometry as the visible wire segment below.
            Rectangle()
                .fill(Color.ckBackground)
                .frame(width: CatchlightLayout.spineWidth,
                       height: CatchlightLayout.circleDiameter / 2)
                .offset(x: CatchlightLayout.cardSpineInset - CatchlightLayout.spineWidth / 2,
                        y: -CatchlightLayout.circleDiameter / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            irisColumn
                .offset(x: CatchlightLayout.cardSpineInset - CatchlightLayout.circleDiameter / 2,
                        y: -CatchlightLayout.circleDiameter / 2)
            // Rings on a wire (owner spec 2026-06-16): the spine lies ON TOP of the
            // Iris's upper half — from the ring's crown down to the card's top edge
            // — then ducks BEHIND the card, which (being opaque) hides it for the
            // rest of the card's height. Drawn AFTER `irisColumn` so it sits in
            // FRONT of the ring; its height is exactly the Iris RADIUS and its
            // bottom lands on the card's top edge (the ZStack origin, y = 0), so
            // the wire is never drawn over the card surface — only over the Iris.
            // The rule: visible over the Iris OR hidden behind the card, never both.
            // Between Takes the gutter spine (DailiesView, behind the cards) carries
            // the wire through the gaps, reappearing above the next ring's crown.
            // Stays on the spine (no `cardSwipeOffset`) so the wire holds while the
            // card swipes. Same `ckSpineWire` fill + `spineWidth` as the gutter so
            // the two read as one continuous wire.
            Rectangle()
                .fill(Color.ckSpineWire)
                .frame(width: CatchlightLayout.spineWidth,
                       height: CatchlightLayout.circleDiameter / 2)
                .offset(x: CatchlightLayout.cardSpineInset - CatchlightLayout.spineWidth / 2,
                        y: -CatchlightLayout.circleDiameter / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            // …and the DOTS pass IN FRONT of the ring too, so the dotted spine reads
            // as convincingly ABOVE the Iris (owner 2026-06-16) — not behind it. The
            // GeometryReader anchors the dash phase to the segment's live SCREEN Y
            // (`+minY`), so the dots hold fixed screen positions as the row scrolls:
            // the ring slides UNDER a static dotted wire, matching the gutter dots
            // above and below. Same `SpineDots` pattern as the gutter. The sign MUST
            // be `+`: `−minY` advances the phase the wrong way, sliding these dots at
            // ~2× and OPPOSITE the gutter (the "two wires" bug).
            GeometryReader { geo in
                SpineLine()
                    .stroke(SpineDots.color,
                            style: SpineDots.style(phase: geo.frame(in: .global).minY))
            }
            .frame(width: CatchlightLayout.spineWidth,
                   height: CatchlightLayout.circleDiameter / 2)
            .offset(x: CatchlightLayout.cardSpineInset - CatchlightLayout.spineWidth / 2,
                    y: -CatchlightLayout.circleDiameter / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
    }

    /// The Iris circle on the spine — a 44pt disc filling its 44pt touch frame.
    /// Gestures are UIKit recognizers (2026-06-10): SwiftUI's `LongPressGesture`
    /// (plain or simultaneous, with or without a Button) never fires for
    /// synthesized presses inside this ScrollView on the current runtime — while
    /// UIKit long-press interactions (e.g. the context menu's) work for both real
    /// and synthesized touches. `tap.require(toFail: long)` preserves the
    /// original exclusive semantics.
    private var irisColumn: some View {
        ZStack {
            TakeCircleView(take: take)
        }
        .frame(width: CatchlightLayout.circleDiameter,
               height: CatchlightLayout.circleDiameter)
        .frame(minWidth: CatchlightLayout.minTouchTarget,
               minHeight: CatchlightLayout.minTouchTarget)
        .contentShape(Rectangle())
        .overlay(
            TapAndLongPressRecognizer(
                minimumDuration: 0.45,
                onTap: onTapCircle,
                onLongPress: onLongPressCircle
            )
        )
        .accessibilityElement()
        .accessibilityIdentifier(irisIdentifier)
        .accessibilityLabel(take.isObie
            ? "Iris. Obie — your pinned Take. \(TakeCircleView.activityDescription(for: take))"
            : "Iris. \(TakeCircleView.activityDescription(for: take))")
        .accessibilityHint("Double-tap to open actions. Long press to make this your Obie.")
        // VoiceOver intercepts long-press, so expose the Obie designation as a
        // named action too. VO activation lands as a tap on the recognizer.
        .accessibilityAction(named: "Make Obie") { onLongPressCircle() }
        .accessibilityAddTraits(.isButton)
    }

    /// The Take's text column on the v1.7 card surface. The visual is factored into
    /// `TakeCardSurface` (single-sourced) so the Focus-ring can lift a lit copy of
    /// the tapped Take's card above its dim veil (owner 2026-06-16: keep the tapped
    /// Take readable while everything else recedes). Here it carries the row's
    /// gestures, context menu, and combined VoiceOver element.
    @ViewBuilder
    private var cardColumn: some View {
        if let editingCard {
            // Editing in place: the live editor takes the card slot and owns its own
            // gestures + per-row accessibility (a combined element would merge the
            // editable fields into one and break VoiceOver editing). The long-press
            // menu rides along so "Discard changes" / Delete / Mark-done are reachable
            // mid-edit (owner 2026-06-17).
            editingCard()
                .contextMenu { rowMenuItems }
        } else {
            TakeCardSurface(take: take)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture { onTapText() }
                .contextMenu { rowMenuItems }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("take-row")
                .accessibilityLabel(rowAccessibilityLabel)
                .accessibilityHint("Double-tap to edit this Take.")
                .accessibilityActions { rowAccessibilityActions }
        }
    }

    @ViewBuilder
    private var rowMenuItems: some View {
        if take.isTask, let onToggleComplete {
            Button {
                onToggleComplete()
            } label: {
                Label(take.isComplete ? "Mark as not done" : "Mark as done",
                      systemImage: take.isComplete ? "circle" : "checkmark.circle")
            }
        }
        if let onDiscard {
            // Edit-in-place: revert the unsaved edits (owner 2026-06-17). Reverts —
            // never deletes — so it's not destructive-styled.
            Button {
                onDiscard()
            } label: {
                Label("Discard changes", systemImage: "arrow.uturn.backward")
            }
        }
        if let onDelete {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Take", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var rowAccessibilityActions: some View {
        if take.isTask, let onToggleComplete {
            Button(take.isComplete ? "Mark as not done" : "Mark as done") { onToggleComplete() }
        }
        if let onDiscard {
            Button("Discard changes") { onDiscard() }
        }
        if let onDelete {
            Button("Delete Take") { onDelete() }
        }
    }
}

/// The Take card's VISUAL surface — text column on the v1.7 card (radius 12,
/// content pad 24/14/14/14, Daylight shadow / Night tonal-only, variant borders).
/// Factored out of `TakeRowView` so the SAME card renders in two places without
/// drifting: the timeline row (wrapped with gestures/menu/VoiceOver), and the
/// Focus-ring's lit copy lifted above its dim veil (owner 2026-06-16 — keep the
/// tapped Take readable while everything else recedes; `PetalFanView`). Purely
/// visual: callers add interactivity. Fills the width PROPOSED to it (the row
/// proposes full width; the fan proposes the card's reconstructed width), so the
/// surface always reaches the card's trailing edge.
struct TakeCardSurface: View {
    let take: Take

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicSize

    /// The user's "Preview" length (Single/Some/All) — how many body lines a
    /// collapsed Take shows on the timeline. Independent of "View" density.
    @AppStorage(SettingsViewModel.TakePreview.defaultsKey)
    private var takePreviewRaw: String = SettingsViewModel.TakePreview.default.rawValue
    private var takePreview: SettingsViewModel.TakePreview {
        SettingsViewModel.TakePreview(rawValue: takePreviewRaw) ?? .default
    }
    /// Body line cap: the Preview choice, but never below 4 at accessibility text
    /// sizes so a sentence is not cut mid-word (`nil` = unlimited / "All").
    private var bodyLineLimit: Int? {
        guard let base = takePreview.lineLimit else { return nil }
        return dynamicSize.isAccessibilitySize ? max(base, 4) : base
    }

    /// The full Take body shown on the card — the `lineLimit` (driven by the
    /// "Preview" setting) decides how much is visible.
    private var displayBody: String {
        let text = take.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Untitled Take" : text
    }

    /// The "3 of 5 completed" progress marker, or nil (one-item Tasks / non-Tasks
    /// show none). The trailing word makes the count self-explanatory on the card
    /// (owner 2026-06-17) — the bare "3 of 5" read ambiguously.
    private var progressText: String? {
        guard let progress = take.checklistProgress else { return nil }
        return "\(progress.done) of \(progress.total) completed"
    }

    /// The Take's first-line colour. A complete Task recedes to the HiFi `.tt.done`
    /// treatment; Obie keeps its emphasis colour.
    private var textColor: Color {
        if take.isTask && take.isComplete { return .ckTextComplete }
        return take.isObie ? .ckTextObie : .ckTextPrimary
    }

    /// Cached formatter — this label is evaluated on every render, and a fresh
    /// `DateFormatter` per evaluation is one of Foundation's most expensive allocations.
    private static let reminderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// The formatted reminder time, or nil. Static so `TakeRowView` can reuse it for
    /// the row's VoiceOver label without re-deriving the formatter.
    static func reminderString(for take: Take) -> String? {
        guard let r = take.timeReminder else { return nil }
        return reminderFormatter.string(from: r.scheduledDate)
    }
    private var reminderLabel: String? { Self.reminderString(for: take) }

    /// Reminder date has passed — drives the overdue card variant (HiFi v1.7
    /// .card.overdue). Obie always wins the card treatment when both apply.
    private var isOverdue: Bool {
        guard let r = take.timeReminder else { return false }
        return r.scheduledDate < Date()
    }

    /// Card background — Obie warm tint, else the standard surface (overdue keeps
    /// the standard surface; only its border + shadow change).
    private var cardSurface: Color {
        take.isObie ? .ckCardObieSurface : .ckSurface
    }

    /// Card border (1.5pt). Obie → Ember (reserved exclusively for the Obie);
    /// overdue → overdue amber; standard → the surface colour (invisible, but
    /// reserves the 1.5pt so all cards are the same size).
    private var cardBorder: Color {
        if take.isObie { return .ckCardObieBorder }
        if isOverdue { return .ckCardOverdueBorder }
        return cardSurface
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayBody)
                // DM Sans 14 (.tt) — Take content is never the display face
                // (DS §2.2 / D-042). Was Cormorant display 20 italic.
                .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .body))
                .foregroundStyle(textColor)
                // Body length follows the "Preview" setting (Single 1 / Some 3 /
                // All = unlimited), with a 4-line floor at accessibility text sizes.
                .lineLimit(bodyLineLimit)
                .multilineTextAlignment(.leading)
                // A complete Task recedes by COLOUR only (`.ckTextComplete` via
                // `textColor`), no strikethrough (owner 2026-06-16).

            // Quiet meta line: the checklist progress marker (2+ items) and/or
            // the reminder time. New marker — HiFi v1.7 is silent on it, so it
            // matches the reminder label's scale (DM Sans caption, Secondary).
            // Stacked so neither fights the other.
            if let progressText {
                // Quiet meta scale (matches .tm size; non-italic — it's a count).
                Text(progressText)
                    .font(CatchlightFont.ui(.regular, size: 11, relativeTo: .caption))
                    .foregroundStyle(Color.ckTextSecondary)
                    .accessibilityHidden(true)   // already spoken in the row label
            }

            if let reminderLabel {
                // .tm — 11pt medium italic, Slate (overdue → overdue amber Daylight /
                // full Glow Night, the .tm.overdue token — distinct from the @35% border).
                Text(reminderLabel)
                    .font(CatchlightFont.ui(.medium, size: 11, relativeTo: .caption))
                    .italic()
                    .foregroundStyle(isOverdue ? Color.ckTextOverdue : Color.ckTextSecondary)
            }
        }
        // v1.7 .card padding: 24px top (clears the overlapping Iris) / 14 sides /
        // 14 bottom. Leading uses the shared token so the DAILIES heading + month
        // markers align to this same text column (owner 2026-06-16).
        .padding(EdgeInsets(top: 24, leading: CatchlightLayout.cardTextLeadingPad,
                            bottom: 14, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardSurface)
                // Daylight elevation only; Night is tonal (surface lighter than
                // bg). Overdue gets the slightly stronger shadow.
                .daylightCardShadow(strong: isOverdue && !take.isObie)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1.5)
        )
    }
}

/// UIKit tap + long-press recognizers bridged into SwiftUI. Exists because
/// SwiftUI's `LongPressGesture` does not fire for synthesized presses inside a
/// ScrollView on the current runtime (UIKit recognizers do — the context menu
/// proves it). `tap.require(toFail: long)` keeps the two mutually exclusive,
/// and the long press fires at `.began` (i.e. at the duration threshold while
/// the finger is still down), matching the previous SwiftUI behaviour.
/// (Internal, not private: the editor footer Iris reuses it for tap-to-shape /
/// long-press-to-discard — UX §19.)
struct TapAndLongPressRecognizer: UIViewRepresentable {
    var minimumDuration: TimeInterval
    /// Receives the recognizer view's centre in WINDOW coordinates (the Iris
    /// touch-frame centre ≈ the Iris circle centre) so the caller can anchor the
    /// petal fan there (section 8).
    var onTap: (CGPoint) -> Void
    var onLongPress: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let long = UILongPressGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.longPressed(_:)))
        long.minimumPressDuration = minimumDuration
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.tapped(_:)))
        tap.require(toFail: long)
        view.addGestureRecognizer(long)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject {
        var parent: TapAndLongPressRecognizer
        init(_ parent: TapAndLongPressRecognizer) { self.parent = parent }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            // The recognizer's view IS the Iris's 44pt touch overlay; its centre
            // converted to window coordinates is the Iris centre the petal fan
            // should bloom from (section 8). `convert(_:to: nil)` targets the
            // window — which equals the global / full-screen overlay space.
            let centre: CGPoint
            if let view = recognizer.view {
                centre = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            } else {
                centre = .zero
            }
            parent.onTap(centre)
        }

        @objc func longPressed(_ recognizer: UILongPressGestureRecognizer) {
            if recognizer.state == .began { parent.onLongPress() }
        }
    }
}

#Preview("Rows — Night") {
    let reminder = TimeReminder(scheduledDate: .now.addingTimeInterval(86_400),
                                notificationIdentifier: "x")
    return VStack(alignment: .leading, spacing: 0) {
        TakeRowView(take: Take(blocks: [.textLine("A plain thought, nothing more.")]))
        TakeRowView(take: Take(blocks: [.checkItem("Ship the Phase 6 UI")]))
        TakeRowView(take: Take(blocks: [.checkItem("Done already", isComplete: true)]))
        TakeRowView(take: Take(blocks: [.textLine("Weekend shop"), .checkItem("milk", isComplete: true),
                                        .checkItem("eggs"), .checkItem("bread", isComplete: true),
                                        .checkItem("coffee"), .checkItem("apples")]))
        TakeRowView(take: Take(blocks: [.checkItem("wash", isComplete: true),
                                        .checkItem("fold", isComplete: true)]))
        TakeRowView(take: { var t = Take(blocks: [.textLine("Call the framer back")]); t.timeReminder = reminder; return t }())
        TakeRowView(take: Take(blocks: [.textLine("The north star")], isObie: true))
    }
    .padding()
    .background(Color.ckBackground)
    .preferredColorScheme(.dark)
}

#Preview("Rows — Daylight") {
    VStack(alignment: .leading, spacing: 0) {
        TakeRowView(take: Take(blocks: [.textLine("A plain thought.")]))
        TakeRowView(take: Take(blocks: [.checkItem("A task to do")]))
        TakeRowView(take: Take(blocks: [.textLine("The north star")], isObie: true))
    }
    .padding()
    .background(Color.ckBackground)
    .preferredColorScheme(.light)
}
