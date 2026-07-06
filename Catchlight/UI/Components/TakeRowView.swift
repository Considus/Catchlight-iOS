//
//  TakeRowView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  A single Take on the timeline: the quadrant circle (aligned to the spine) on the
//  left, the Take's first line of text on the right. Reminder Takes show their alarm
//  time as a small Fog label beside the circle. Gestures:
//    • tap circle      → open the focus-ring fan (activity-type selector)
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
    /// focus-ring fan in place at the tapped Iris rather than at the screen centre
    /// (section 8). The window coordinate space matches the full-screen focus-ring-fan
    /// overlay's space in RootView.
    var onTapCircle: (CGPoint) -> Void = { _ in }
    var onLongPressCircle: () -> Void = {}
    var onTapText: () -> Void = {}
    /// Optional row actions (2026-06-10): when supplied, a context menu on the
    /// TEXT column offers "Mark as done" (Tasks AND reminders — 2026-06-18) and
    /// "Delete Take". For reminders the menu is the ONLY way to mark done (swipe-right
    /// stays Task-only); marking done settles the whole Take (`setMarkedDone`). The
    /// menu is deliberately NOT attached to the whole row — a row-level context
    /// menu's long-press recognizer preempts the circle's long-press (Obie
    /// designation). VoiceOver gets the same actions as named accessibility
    /// actions on the combined row element.
    var onToggleComplete: (() -> Void)? = nil
    /// Toggle the Take's Important flag from the long-press menu (owner 2026-06-19 —
    /// the manual mark, mirroring the keyboard dock's Important button). Orthogonal
    /// to type, so it's offered on every Take.
    var onSetImportant: (() -> Void)? = nil
    /// Designate this Take as the Obie from the long-press menu (owner 2026-06-19 —
    /// an accessible, discoverable path alongside the Iris long-press). Offered only
    /// when the Take isn't already the Obie.
    var onMakeObie: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    /// Export THIS single Take from the long-press menu (owner 2026-06-27). Routes the one
    /// Take through the system share sheet (`ExportCoordinator`), mirroring Settings' bulk
    /// export. Offered on every Take; the caller supplies the share-sheet plumbing.
    var onExport: (() -> Void)? = nil
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
    /// This Take's reminder currently has a pending snoozed re-nudge — the edge reads
    /// "SNOOZED" instead of "OVERDUE" (owner 2026-06-21). Defaults false everywhere the
    /// snooze state isn't tracked.
    var isSnoozed: Bool = false
    /// Edit-in-place (2026-06-17): when supplied, the read-only `TakeCardSurface` in
    /// the card slot is replaced by this live editor, IN POSITION — the Iris, spine,
    /// and card geometry are untouched (owner point 6). nil everywhere a row is at
    /// rest. The editor owns its own gestures + accessibility, so the row's tap /
    /// combined-element wrapping is dropped while editing.
    /// Whether detected URLs in this row's resting card are tappable (owner 2026-06-27).
    /// Forwarded to `TakeCardSurface`; the dimmed background rows during edit-in-place pass
    /// false so a save/discard tap can't land on a URL under the mask (only affects the
    /// resting card — the editing row renders the live editor, not `TakeCardSurface`).
    var linksInteractive: Bool = true
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
        if let loc = take.locationReminder {
            // A silent place tag (alarm off) doesn't remind — say so for VoiceOver.
            if loc.alarmEnabled {
                parts.append(loc.triggerOnArrival ? "Reminds on arrival" : "Reminds on leaving")
            } else {
                parts.append(loc.triggerOnArrival ? "Place set, arrival, silent" : "Place set, leaving, silent")
            }
        }
        if take.isNote && !take.isTask && take.timeReminder == nil && take.locationReminder == nil {
            parts.append("Note")
        }
        return parts.joined(separator: ". ")
    }

    var body: some View {
        // Section 5 (HiFi v1.7 .card) — the text column rides a card SURFACE; the
        // Iris stays on the spine to its left, overlapping the card's leading
        // edge (`position:absolute; left:6px` in v1.7). The Iris is drawn on TOP
        // so its long-press still wins hit-testing; the card's text taps clear
        // the 44pt Iris touch frame.
        // Explicit `.zIndex` pins the paint order (card < occluder < Iris < wire <
        // dots). Without it, when the card REPAINTS on a state change — e.g. the
        // border recolouring on "mark done" (D-044, [[catchlight-take-colour-system]])
        // — SwiftUI could momentarily reshuffle these siblings, and the freshly drawn
        // card painted over the Iris's lower half (which overlaps the card's top-left
        // corner) for a beat before the Iris re-composited. Pinning the order keeps
        // the Iris above the card through any redraw (owner 2026-06-18).
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
                .zIndex(0)
            // Crown occluder (owner 2026-06-16): the static dotted spine runs BEHIND
            // the whole row, so its bright dots were bleeding up through the Iris's
            // hollow aperture and making the crown look translucent. This page-coloured
            // 2pt segment sits at the wire column BEHIND the Iris: the opaque ring band
            // covers it (no notch), but in the aperture it reads as plain background —
            // blocking the dots behind, so the wire on top reads as clearly above the
            // ring. Same crown geometry as the visible wire segment below.
            Rectangle()
                .fill(Color.ckBackground)
                // Widened to the full THREE-track span so all three dotted tracks are
                // occluded behind the Iris, not just the centre one (owner 2026-07-04).
                .frame(width: CatchlightLayout.spineWidth + CatchlightLayout.spineTrackOffset * 2,
                       height: CatchlightLayout.circleDiameter / 2)
                .offset(x: CatchlightLayout.cardSpineInset
                        - (CatchlightLayout.spineWidth + CatchlightLayout.spineTrackOffset * 2) / 2,
                        y: -CatchlightLayout.circleDiameter / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(1)
            irisColumn
                .offset(x: CatchlightLayout.cardSpineInset - CatchlightLayout.circleDiameter / 2,
                        y: -CatchlightLayout.circleDiameter / 2)
                .zIndex(2)
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
            SpineLine()
                .stroke(Color.ckSpineWire, lineWidth: CatchlightLayout.spineWidth)
                .frame(width: CatchlightLayout.spineWidth,
                       height: CatchlightLayout.circleDiameter / 2)
                .offset(x: CatchlightLayout.cardSpineInset - CatchlightLayout.spineWidth / 2,
                        y: -CatchlightLayout.circleDiameter / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(3)
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
            .zIndex(4)
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
        .accessibilityHint(take.isObie
            ? "Double-tap to open actions. Long press to turn this back into a standard Take."
            : "Double-tap to open actions. Long press to make this your Obie.")
        // VoiceOver intercepts long-press, so expose the Obie toggle as a named
        // action too. VO activation lands as a tap on the recognizer.
        .accessibilityAction(named: take.isObie ? "Make standard Take" : "Make Obie") { onLongPressCircle() }
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
            TakeCardSurface(take: take, isSnoozed: isSnoozed, linksInteractive: linksInteractive)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture { onTapText() }
                // iOS's standard long-press lift: the card rises cleanly (its own
                // shape + shadow, no platter, no duplicate). The Iris is a separate
                // sibling so it stays put for the brief lift — accepted (owner
                // 2026-06-18): the "Iris-rides" custom/UIKit previews each cost more
                // than the flourish is worth (platter, or a row restructure). Revisit
                // only if the row ever moves to a UIKit-hosted cell.
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
        if take.canBeMarkedDone, let onToggleComplete {
            Button {
                onToggleComplete()
            } label: {
                Label(take.isMarkedDone ? "Mark Not Done" : "Mark Done",
                      systemImage: take.isMarkedDone ? "circle" : "checkmark.circle")
            }
        }
        if let onSetImportant {
            Button {
                onSetImportant()
            } label: {
                // The standard Important mark (`ImportantGlyph`, "!"), baked for the menu;
                // crossed-out when already Important (owner 2026-06-29).
                if take.isImportant {
                    Label { Text("Remove Important") } icon: { MenuGlyph.removeImportant }
                } else {
                    Label { Text("Make Important") } icon: { MenuGlyph.makeImportant }
                }
            }
        }
        if let onMakeObie, !take.isObie {
            Button {
                onMakeObie()
            } label: {
                Label { Text("Make Obie") } icon: { MenuGlyph.obie }
            }
        }
        if let onExport {
            // Export just this one Take to the share sheet (owner 2026-06-27) — the
            // single-Take counterpart to Settings' bulk export.
            Button {
                onExport()
            } label: {
                Label("Export Take", systemImage: "square.and.arrow.up")
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
        if take.canBeMarkedDone, let onToggleComplete {
            Button(take.isMarkedDone ? "Mark Not Done" : "Mark Done") { onToggleComplete() }
        }
        if let onSetImportant {
            Button(take.isImportant ? "Remove Important" : "Make Important") { onSetImportant() }
        }
        if let onMakeObie, !take.isObie {
            Button("Make Obie") { onMakeObie() }
        }
        if let onExport {
            Button("Export Take") { onExport() }
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
/// tapped Take readable while everything else recedes; `FocusRingFanView`). Purely
/// visual: callers add interactivity. Fills the width PROPOSED to it (the row
/// proposes full width; the fan proposes the card's reconstructed width), so the
/// surface always reaches the card's trailing edge.
struct TakeCardSurface: View {
    let take: Take
    /// This Take's reminder has a pending snoozed re-nudge — the edge reads "SNOOZED"
    /// instead of "OVERDUE" (owner 2026-06-21). Defaults false (e.g. previews).
    var isSnoozed: Bool = false
    /// Whether detected URLs are TAPPABLE (owner 2026-06-27). The visual treatment
    /// (accent + underline) is unchanged either way; when false the `.link` attribute is
    /// simply omitted so the text can't open Safari. The dimmed background rows during
    /// edit-in-place pass false — otherwise a tap meant to save/discard the edit lands on
    /// a URL under the mask and navigates away instead of dismissing (owner-reported
    /// 2026-06-27): a SwiftUI `Text` link beats the card's own `onTapGesture`.
    var linksInteractive: Bool = true

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicSize

    /// The user's "Preview" length (Single/Some/All) — how many body lines a
    /// collapsed Take shows on the timeline. Independent of "View" density.
    @AppStorage(SettingsViewModel.TakePreview.defaultsKey)
    private var takePreviewRaw: String = SettingsViewModel.TakePreview.default.rawValue
    private var takePreview: SettingsViewModel.TakePreview {
        SettingsViewModel.TakePreview(rawValue: takePreviewRaw) ?? .default
    }
    /// The "Creation date" setting — the resting card shows the stamp only in `.always`
    /// (the editor handles `.editor`). See `CreationStampLabel`.
    @AppStorage(SettingsViewModel.CreationStamp.defaultsKey)
    private var creationStampRaw: String = SettingsViewModel.CreationStamp.default.rawValue
    private var creationStamp: SettingsViewModel.CreationStamp {
        SettingsViewModel.CreationStamp(rawValue: creationStampRaw) ?? .default
    }
    /// Body line cap: the Preview choice, but never below 4 at accessibility text
    /// sizes so a sentence is not cut mid-word (`nil` = unlimited / "All").
    private var bodyLineLimit: Int? {
        guard let base = takePreview.lineLimit else { return nil }
        return dynamicSize.isAccessibilitySize ? max(base, 4) : base
    }

    /// The Take body as plain text — `blocks` joined by newlines (untrimmed so block
    /// offsets line up for per-item colouring + link mapping below).
    private var bodyText: String { take.plainText }

    /// Detected links in the body (schemed, `www.`, or bare domains with an assumed
    /// `https://` — see `LinkDetector`).
    private var bodyLinks: [LinkDetector.Match] { LinkDetector.detect(in: bodyText) }

    /// Whether to add breathing room between body lines. With 2+ links, stacked link
    /// lines sit only a line-height apart and are easy to mis-tap, so we open the
    /// spacing up; single-link / plain Takes keep their normal density (owner 2026-06-22).
    private var bodyNeedsLinkSpacing: Bool { bodyLinks.count >= 2 }

    /// The full Take body shown on the card — the `lineLimit` (driven by the "Preview"
    /// setting) decides how much is visible. Colour rule (owner 2026-06-22, refined
    /// 2026-07-02):
    ///   • **Whole Take marked done** (all items ticked, or a swipe/long-press marks the
    ///     reminder/task done → `isMarkedDone`) → the ENTIRE body greys, via
    ///     `style.bodyText` = `ckTextComplete`. Single-sourced with `TakeCardStyle` so the
    ///     timeline and the inline editor recede by the same amount, in BOTH schemes
    ///     (`ckTextComplete` is adaptive: Fog @82% Daylight / @58% Night).
    ///   • **One item of several ticked** (NOT `isMarkedDone`) → base stays primary/Obie
    ///     and only that completed check item greys on its own (loop below) — so a single
    ///     tick never greys the whole Take.
    /// URLs render as tappable accent links.
    private var displayBody: AttributedString {
        let baseColor: Color = style.bodyText
        guard !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            var placeholder = AttributedString("Untitled Take")
            placeholder.foregroundColor = baseColor
            return placeholder
        }

        var attr = AttributedString(bodyText)
        attr.foregroundColor = baseColor

        // Grey each completed check item's run. `plainText` is `blocks` joined by "\n",
        // so walk the blocks tracking the cursor and recolour the completed ones.
        var cursor = bodyText.startIndex
        for (i, block) in take.blocks.enumerated() {
            let end = bodyText.index(cursor, offsetBy: block.text.count)
            if case .check(let item) = block, item.isComplete,
               let lo = AttributedString.Index(cursor, within: attr),
               let hi = AttributedString.Index(end, within: attr) {
                attr[lo..<hi].foregroundColor = .ckTextComplete
            }
            cursor = end
            if i < take.blocks.count - 1, cursor < bodyText.endIndex {
                cursor = bodyText.index(after: cursor)   // skip the "\n" joiner
            }
        }

        for match in bodyLinks {
            guard let lo = AttributedString.Index(match.range.lowerBound, within: attr),
                  let hi = AttributedString.Index(match.range.upperBound, within: attr) else { continue }
            if linksInteractive { attr[lo..<hi].link = match.url }
            attr[lo..<hi].foregroundColor = .ckAccent
            attr[lo..<hi].underlineStyle = .single
        }
        return attr
    }

    /// The "0 of 1 / 3 of 5 completed" progress marker, or nil (non-Tasks show
    /// none). The trailing word makes the count self-explanatory on the card
    /// (owner 2026-06-17) — the bare "3 of 5" read ambiguously.
    private var progressText: String? {
        guard let progress = take.checklistProgress else { return nil }
        return "\(progress.done) of \(progress.total) completed"
    }

    /// The card's full colour treatment (surface, border, text, overdue/done flags),
    /// derived from the Take + scheme. Single-sourced with the inline editor via
    /// `TakeCardStyle` so read↔edit never drift (owner 2026-06-18).
    private var style: TakeCardStyle { TakeCardStyle(take: take, scheme: scheme) }

    /// What the left-edge label lane shows. An overdue reminder reads vertical ruby
    /// "OVERDUE" — or "SNOOZED" (same ruby, ruby border/italic kept) when it currently
    /// has a pending snoozed re-nudge (owner 2026-06-21). Future user colour-labels
    /// render through the same lane (`TakeLabelLane`).
    private var laneContent: TakeLabelLane.Content {
        guard style.isOverdue else { return .none }
        return .systemText(isSnoozed ? "SNOOZED" : "OVERDUE", .ckRuby)
    }

    /// Cached formatters — this label is evaluated on every render, and a fresh
    /// `DateFormatter` per evaluation is one of Foundation's most expensive allocations.
    /// `reminderFormatter` shows an absolute date + time; the date-only variant drops
    /// the (meaningless) time for an all-day "when". Both relative-format so today /
    /// tomorrow read naturally; all locale-driven (no hardcoded patterns).
    private static let reminderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()
    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.doesRelativeDateFormatting = true
        return f
    }()

    /// The formatted reminder "when", or nil. Static so `TakeRowView` can reuse it for
    /// the row's VoiceOver label without re-deriving the formatter. A repeating reminder
    /// always shows its NEXT due instant plus the cadence word — e.g. "Tomorrow at 9:00
    /// AM · Daily" (owner 2026-06-21), so the card never goes stale and reads as a live
    /// recurring entry.
    static func reminderString(for take: Take) -> String? {
        guard let r = take.timeReminder else { return nil }
        let formatter = r.isAllDay ? dateOnlyFormatter : reminderFormatter
        if r.repeats {
            let due = r.effectiveNextDue(now: Date())
            return "\(formatter.string(from: due)) · \(r.recurrence.label)"
        }
        return formatter.string(from: r.scheduledDate)
    }
    private var reminderLabel: String? { Self.reminderString(for: take) }

    /// The location reminder's one-line label — place name + arrive/leave — or nil. A
    /// reminder is either time- or location-based (owner 2026-06-24), so this and
    /// `reminderLabel` are mutually exclusive on a given Take.
    private var locationLabel: String? {
        guard let loc = take.locationReminder else { return nil }
        let place = (loc.locationName?.isEmpty == false) ? loc.locationName! : "Location"
        return "\(place) · \(loc.triggerOnArrival ? "On arrival" : "On leaving")"
    }

    /// Whether this reminder's alarm will actually fire — drives the bell vs bell.slash
    /// glyph ahead of the "when". A dated-but-silent Take (or a dismissed one-shot) reads
    /// `alarmEnabled == false`; absent a reminder there's no label to mark.
    private var alarmOn: Bool { take.timeReminder?.alarmEnabled ?? false }

    /// Whether a LOCATION reminder will fire — drives its bell vs bell.slash (owner
    /// 2026-06-27). A silent place tag reads `alarmEnabled == false`.
    private var locationAlarmOn: Bool { take.locationReminder?.alarmEnabled ?? false }

    /// The reminder subtext colour: ruby when overdue, the done grey when done, else
    /// the quiet secondary scale.
    private var reminderLabelColor: Color {
        if style.isOverdue { return .ckTextOverdue }
        if style.isDone { return .ckTextComplete }
        return .ckTextSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayBody)
                // DM Sans 14 (.tt) — Take content is never the display face
                // (DS §2.2 / D-042). Was Cormorant display 20 italic.
                .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .body))
                // Body + link colours are carried on the AttributedString (`displayBody`)
                // so detected URLs render accent; `.tint` colours the link's tap state.
                .tint(.ckAccent)
                // Open the line spacing up only when stacked links would otherwise be
                // hard to tap apart (owner 2026-06-22).
                .lineSpacing(bodyNeedsLinkSpacing ? 8 : 0)
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

            if let locationLabel {
                // Location reminder (owner 2026-06-24): a place pin ahead of the place + "On
                // arrival/leaving". Mutually exclusive with the time line below.
                HStack(spacing: 4) {
                    LocationPinGlyph(color: Color.ckTextSecondary, size: 13)
                        .accessibilityHidden(true)
                    // Bell vs bell.slash — same "will it nag" cue as the time line (owner
                    // 2026-06-27): a silent place tag (alarm off) shows bell.slash.
                    Image(systemName: locationAlarmOn ? "bell" : "bell.slash")
                        .font(CatchlightFont.ui(.medium, size: 11, relativeTo: .caption))
                        .foregroundStyle(Color.ckTextSecondary)
                        .accessibilityHidden(true)
                    Text(locationLabel)
                        .font(CatchlightFont.ui(.medium, size: 11, relativeTo: .caption))
                        .foregroundStyle(Color.ckTextSecondary)
                }
            } else if let reminderLabel {
                // .tm — 11pt medium. Italic ONLY when overdue (owner 2026-06-18): the
                // slant + ruby together signal "late"; active & done read upright.
                // Colour: ruby overdue / done grey / quiet Secondary otherwise.
                HStack(spacing: 4) {
                    // Type glyph (owner 2026-06-24): a clock marks this as a time reminder,
                    // sitting LEFT of the alarm bell — so the two read as "scheduled" + "will
                    // it nag". Same size/colour as the label so they form one unit.
                    Image(systemName: "clock")
                        .font(CatchlightFont.ui(.medium, size: 11, relativeTo: .caption))
                        .foregroundStyle(reminderLabelColor)
                        .accessibilityHidden(true)
                    // Small bell ahead of the "when" (owner 2026-06-22): a quiet at-a-glance
                    // signal of whether this reminder will actually nag — `bell` when the
                    // alarm is on, `bell.slash` when it's a silent/dismissed dated item.
                    // Inherits the label's size + colour so it reads as one unit; never
                    // italicised (the slant is the text's "late" cue, not the glyph's).
                    Image(systemName: alarmOn ? "bell" : "bell.slash")
                        .font(CatchlightFont.ui(.medium, size: 11, relativeTo: .caption))
                        .foregroundStyle(reminderLabelColor)
                        .accessibilityHidden(true)
                    Text(reminderLabel)
                        .font(CatchlightFont.ui(.medium, size: 11, relativeTo: .caption))
                        .italic(style.isOverdue)
                        .foregroundStyle(reminderLabelColor)
                }
            }

            // Created-at stamp pinned at the very bottom of the card, shown when the
            // "Creation date" setting is Always (owner 2026-07-01).
            if creationStamp == .always {
                CreationStampLabel(date: take.createdAt)
                    .padding(.top, 2)
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
                .fill(style.surface)
                // Daylight elevation only; Night is tonal (surface lighter than
                // bg). Overdue gets the slightly stronger shadow.
                .daylightCardShadow(strong: style.isOverdue && !take.isObie)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style.border, lineWidth: TakeCardStyle.borderWidth)
        )
        // The label lane hugs the card's left edge, in the clear strip before the
        // Iris (owner 2026-06-18). Rides with the card (incl. swipe).
        .overlay(alignment: .leading) {
            TakeLabelLane(content: laneContent)
        }
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
    /// focus-ring fan there (section 8).
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
            // converted to window coordinates is the Iris centre the focus-ring fan
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
