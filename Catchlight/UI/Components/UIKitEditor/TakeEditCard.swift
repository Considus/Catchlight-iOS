//
//  TakeEditCard.swift
//  Catchlight (iOS app target) — Pillar 2 / M5b (2026-07-16)
//
//  The editing card around `BlockEditor`, in two layers so all THREE hosts share one
//  implementation without being forced into one shape:
//
//    • `TakeEditCard`      — THE CARD. `TakeCardStyle` chrome + `BlockEditor` + the creation
//                            stamp + the grow-to-a-cap height maths. Host-agnostic: it does
//                            not know where it sits or what it is anchored to.
//    • `KeyboardTakeEditor` — THE ANCHORING. Pins the card just above the keyboard and grows it
//                            UPWARD, carrying the owner-tuned descent/drop geometry.
//
//  Who uses what:
//    - `DailiesView`       → `KeyboardTakeEditor` (Iris in the card's top-left)
//    - `StoryboardView`    → `KeyboardTakeEditor` (no Iris there, owner 2026-06-19)
//    - `LockedCaptureView` → `TakeEditCard` directly, TOP-anchored under its header (proven
//                            stable; the lock-screen capture has no timeline to sit against).
//
//  Replaces `InlineTakeEditCard` at the same seam. That view survives only for the OLD timeline
//  behind the A/B toggle, and dies with it at M7.
//

import SwiftUI
import CatchlightCore

// MARK: - The card

struct TakeEditCard: View {
    @Environment(\.irisLeadingInset) private var irisLeadingInset
    /// Single source of truth — the host owns the draft. `BlockEditor`'s coordinator mutates it
    /// only through `Take`'s block mutators, so the derived flags never drift. Hosts must GUARD
    /// the setter of any binding built from an Optional: the coordinator is UIKit and outlives
    /// the SwiftUI teardown, so a late write can resurrect a cleared draft.
    @Binding var draft: Take
    @Binding var focusedBlockID: UUID?

    /// The height past which the card stops growing and `BlockEditor` scrolls internally, so the
    /// caret can never slip behind the keyboard. The host computes it from its own geometry.
    var maxHeight: CGFloat
    /// A minimum CONTENT floor: the frame is held here while the text is short, so the caret can
    /// FALL through the reserve before the card starts growing. 0 = size straight to the content.
    var minContent: CGFloat = 0
    /// Floor for the editor frame, so a one-line Take is still a proper editing surface.
    var minEditorHeight: CGFloat = 60
    /// The Iris in the card's top-left. Dailies yes; the Storyboard and the lock-screen capture
    /// have none.
    var showsIris: Bool = false

    var onOpenAngle: (() -> Void)? = nil
    var onEditReminder: (() -> Void)? = nil
    /// The keyboard × discards (revert); save is the host's tap-away.
    var onDiscard: (() -> Void)? = nil
    /// Tap the Iris → open the Focus row against the LIVE DRAFT (owner 2026-06-17, so the
    /// fan reflects unsaved shaping and its commit routes back to the draft — `RootView` does
    /// that routing off `ui.editingTakeID`). The `CGRect` is this card's frame in WINDOW coords
    /// (the recognizer's Iris centre plus the card's measured size), which is the Focus row
    /// overlay's space: the row runs along the card's bottom edge. Only meaningful with
    /// `showsIris`.
    ///
    /// Iris LONG-press is deliberately absent: it's disabled during editing (discard moved to the
    /// Take's long-press menu — owner 2026-06-17), matching the old timeline's row.
    var onTapIris: ((CGRect) -> Void)? = nil
    /// Reports the RAW (uncapped) content height, for a host that sizes itself off it.
    var onContentHeightChange: ((CGFloat) -> Void)? = nil
    /// Seals the UIKit text view out of the accessibility tree while an overlay covers this
    /// card (audit 2026-08, V31 — the Focus row opened from the Iris). See `BlockEditor`.
    var axHidden: Bool = false
    /// Hides the "Created on" stamp even when the setting shows it. `KeyboardTakeEditor` sets this
    /// at accessibility text sizes while the keyboard is up (owner 2026-09-30).
    var hidesStamp: Bool = false
    /// Reports the "Created on" row's real height (its top pad included), for a host whose
    /// grow-up cap has to discount it. See `chrome(stampRow:)`.
    var onStampRowHeightChange: ((CGFloat) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    /// The editor's live frame height, and the content height it last reported.
    @State private var editorHeight: CGFloat = 60
    @State private var editorContentHeight: CGFloat = 30
    /// The card's measured size, for the frame `onTapIris` reports.
    @State private var cardSize: CGSize = .zero

    /// The "Creation date" setting — the editor shows the stamp for `.editor` and `.always` (both
    /// include the editing surface), matching `InlineTakeEditCard`.
    @AppStorage(SettingsViewModel.CreationStamp.defaultsKey)
    private var creationStampRaw: String = SettingsViewModel.CreationStamp.default.rawValue
    private var creationStamp: SettingsViewModel.CreationStamp {
        SettingsViewModel.CreationStamp(rawValue: creationStampRaw) ?? .default
    }

    /// How far the editor's frame LEADS its content, so the frame is never shorter than the text
    /// (which would make `BlockEditor` scroll). Kept tiny — the owner wants the caret to sit right
    /// ON the "Created on" line, not a line above it.
    static let editorLineLead: CGFloat = 4
    /// A cap change bigger than this re-applies the editor height; smaller is keyboard settling.
    static let capJumpThreshold: CGFloat = 12

    /// The card's own chrome above and below the `BlockEditor` frame: the `cardPadding` top and
    /// bottom pads, PLUS the "Created on" stamp row's measured height when it shows (0 when off).
    ///
    /// The row is measured, not budgeted. A flat 20 fitted one line, but at the largest standard
    /// text size on an iPhone 16 the US stamp wraps to two lines whenever the hour has two digits
    /// ("10:34 AM" measured 258pt in a 257pt column, 37.7pt tall), so the card came out about 18pt
    /// past its cap and its Iris went under the heading fade (154 → 135pt), only from 10:00 to
    /// 12:59 (found by the iPhone Engineer, 2026-11-11).
    ///
    /// A host that computes a grow-up cap must discount THIS, not a guess: `KeyboardTakeEditor`
    /// carried a flat 38, exactly the stamp-OFF value at the time, so with the stamp on (Editor or Always,
    /// and Always is the busier default) the card came out 20pt taller than its own cap intended
    /// and its top overshot the limit by that much. Half of the "Iris behind the fade" report
    /// (owner 2026-08-11); `irisReserve` is the other half.
    static func chrome(stampRow: CGFloat) -> CGFloat {
        CatchlightLayout.cardPadding * 2 + stampRow
    }

    /// The stamp row's height before it has been measured: one line of the 11pt text plus its
    /// 6pt top pad.
    static let stampRowEstimate: CGFloat = 20

    /// The content height the frame should honour — the floor while short, the real content after.
    private var effectiveContent: CGFloat { max(editorContentHeight, minContent) }

    var body: some View {
        let style = TakeCardStyle(take: draft, scheme: scheme)
        let d = CatchlightLayout.circleDiameter
        let irisInset = CatchlightLayout.irisInset
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                BlockEditor(
                    draft: $draft,
                    focusedBlockID: $focusedBlockID,
                    onOpenAngle: onOpenAngle,
                    onEditReminder: onEditReminder,
                    onDiscard: onDiscard,
                    // Only a card pinned at its cap should scroll to follow the caret; below the cap
                    // let the card GROW instead of jumping the text. Derive this from the CONTENT
                    // (does it WANT to exceed the cap?) — NOT from the current frame vs maxHeight,
                    // which flickers false whenever maxHeight shifts by a few points as the keyboard
                    // settles, wrongly telling the editor it can still grow and pinning a long
                    // Take's caret off-screen (device 2026-07-15).
                    atMaxHeight: effectiveContent + Self.editorLineLead >= maxHeight,
                    axHidden: axHidden,
                    onContentHeightChange: { h in
                        editorContentHeight = h
                        onContentHeightChange?(h)
                        // Hold the frame at the floor while the text is short so the caret descends
                        // through the reserve; past that it tracks content, always leading by a hair
                        // so nothing scrolls until the cap. Any downward growth is the HOST's job
                        // (see `KeyboardTakeEditor.bottomLift`), NOT extra frame height — otherwise
                        // there'd be dead space below the caret (owner 2026-07-15).
                        let effective = max(h, minContent) + Self.editorLineLead
                        var t = Transaction(); t.disablesAnimations = true
                        withTransaction(t) {
                            editorHeight = min(max(effective, minEditorHeight), maxHeight)
                        }
                    })
                    .frame(height: editorHeight)
                    // The cap can change with no content change: a notice strip standing down as the
                    // keyboard rises lifts the cap from the floor to the real room. Re-apply it, or the
                    // frame keeps the height it took under the old cap (measured: a card left
                    // at the 60pt floor under a 211pt cap). Only for a real jump: the cap also drifts a
                    // few points while the keyboard settles, and following that moved the default-size
                    // card 3pt, where the owner's resting layout must stay exactly as it is.
                    .onChange(of: maxHeight) { old, cap in
                        guard abs(cap - old) > Self.capJumpThreshold else { return }
                        let effective = max(editorContentHeight, minContent) + Self.editorLineLead
                        var t = Transaction(); t.disablesAnimations = true
                        withTransaction(t) {
                            editorHeight = min(max(effective, minEditorHeight), cap)
                        }
                    }

                // Created-at stamp, gated by the setting — Editor-only + Always both show it while
                // editing (matches `InlineTakeEditCard` so all three options stay consistent).
                if creationStamp != .off && !hidesStamp {
                    CreationStampLabel(date: draft.createdAt)
                        .padding(.top, 6)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            onStampRowHeightChange?($0)
                        }
                }
            }
            // Card text inset: `cardPadding` top, bottom and trailing / text column leading,
            // clear of the Iris. Matches TakeCardSurface, so read↔edit don't shift.
            .padding(EdgeInsets(top: CatchlightLayout.cardPadding,
                                leading: CatchlightLayout.cardTextLeadingPad(irisLeadingInset: irisLeadingInset),
                                bottom: CatchlightLayout.cardPadding,
                                trailing: CatchlightLayout.cardPadding))
            .background(
                RoundedRectangle(cornerRadius: TakeCardStyle.cornerRadius, style: .continuous)
                    .fill(style.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TakeCardStyle.cornerRadius, style: .continuous)
                    .strokeBorder(style.border, lineWidth: TakeCardStyle.borderWidth)
            )
            .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }

            if showsIris {
                // The SAME Iris the timeline rows use, from the same view. This card is
                // a row's stand-in: identical card padding, Iris inside the card's
                // top-left in the same place.
                IrisView(take: draft)
                    .allowsHitTesting(false)
                    .offset(x: irisLeadingInset, y: irisInset)
                // The touch and VoiceOver surface, separate from the drawing.
                Color.clear
                    .frame(width: d, height: d)
                    .contentShape(Rectangle())
                    // Tap → the Focus row, as on a read card. This card's Iris was purely
                    // DECORATIVE from M4.7 until 2026-07-16: on the old timeline the row's own
                    // Iris stays beside the editor and carries the gesture, so nothing was lost
                    // until M5a routed every edit through this floating card. Reuses the row's
                    // recognizer, which reports the view's centre in WINDOW coords.
                    .overlay {
                        if let onTapIris {
                            TapAndLongPressRecognizer(minimumDuration: 0.45,
                                                      onTap: { onTapIris(FocusRowView.cardFrame(irisCentre: $0, cardSize: cardSize, irisLeadingInset: irisLeadingInset)) },
                                                      onLongPress: {})
                        }
                    }
                    // ⚠️ TEST CONTRACT: the XCUITests open the Focus row through "editor-shape"
                    // (the EDITING card's Iris) — the retired row-hosted editor published it, and
                    // it moved here with the card. Queried type-agnostically (`anyElement`), since
                    // a SwiftUI a11y element surfaces as .other on some runtimes and .button on
                    // others — but the IDENTIFIER must survive.
                    .accessibilityElement()
                    .accessibilityIdentifier("editor-shape")
                    // The shared Iris label: the same control must not carry a
                    // name of its own per host — and this was the only Iris that never
                    // said what the Take is. Reads the DRAFT, so it follows the shape
                    // as the user changes it.
                    .accessibilityLabel(TakeRowView.irisAccessibilityLabel(for: draft))
                    .accessibilityHint("Opens the Focus row to change what this Take is.")
                    // V10 (audit 2026-08): announce as a button like the Obie row's
                    // Iris — the same control must not read differently per host.
                    .accessibilityAddTraits(.isButton)
                    .offset(x: irisLeadingInset, y: irisInset)
            }
        }
    }
}

// MARK: - The keyboard anchoring

/// The card pinned just above the keyboard, growing UPWARD — the timeline + Storyboard editor.
/// A NEW Take and an EXISTING-Take edit are the same card by owner decision (the M5a consistency
/// pass, 2026-07-15): a top-anchored editor ran its bottom off-screen under the keyboard ("the
/// edit-Take card has no bottom").
///
/// THE OWNER-TUNED GEOMETRY LIVES HERE AND ONLY HERE. It cost ~15 device rounds on 2026-07-15/16;
/// treat the numbers as owner decisions, not implementation detail:
///
///   1. DESCENT — the caret starts ~2 lines above its resting line and falls to just above the
///      "Created on" stamp, the card NOT yet moving (`descentFloor` holds the frame).
///   2. DROP — the card's bottom then grows DOWN by `downExpandLines` to the keyboard
///      (`bottomLift` closing to 0), so the card's bottom is actually used.
///   3. GROW UP — only then does the card grow upward, caret pinned low, older lines climbing and
///      scrolling off the top under the heading.
///   4. CAP — past `maxHeight` the card stops and `BlockEditor` scrolls internally. This is the
///      architectural fix for the caret-below-keyboard bug that returned four times.
struct KeyboardTakeEditor: View {
    @Binding var draft: Take
    @Binding var focusedBlockID: UUID?

    /// The Iris in the card's top-left. Dailies yes; the Storyboard has none (owner 2026-06-19).
    var showsIris: Bool = true
    /// The card's left edge (`CatchlightLayout.cardMargin`).
    var leadingInset: CGFloat
    /// Passed through to the card's `BlockEditor` (audit 2026-08, V31).
    var axHidden: Bool = false
    /// While the Focus row is open on this card, the card keeps its place. Opening the row drops
    /// the keyboard, and following it down parked the card at the bottom of the screen, under
    /// the veil, with only the row's Iris left where it had been (owner 2026-11-11). The hide is
    /// held back until the row closes, by which time the keyboard is usually back.
    ///
    /// Read live, not passed as a value: the keyboard's hide arrives in the same update that opens
    /// the row, before this view has been handed the new value.
    var holdsPlace: () -> Bool = { false }
    /// The card's right margin. Nil matches the left (`leadingInset`), as every Take card does.
    var trailingInset: CGFloat? = nil

    var onOpenAngle: (() -> Void)? = nil
    var onEditReminder: (() -> Void)? = nil
    var onDiscard: (() -> Void)? = nil
    /// Tap the Iris → the Focus row on this card's WINDOW-coord frame (see `TakeEditCard`).
    var onTapIris: ((CGRect) -> Void)? = nil

    @Environment(\.deviceTopInset) private var deviceTopInset
    @Environment(\.homeIndicatorInset) private var homeIndicatorInset
    /// Measured, so the grow-up cap tracks a heading that has grown with the text size.
    @Environment(\.headingClearance) private var headingClearance

    /// The "Creation date" setting — read here for the SAME reason `TakeEditCard` reads it: the
    /// stamp row is part of the card's height, so the grow-up cap has to know whether it's there.
    @AppStorage(SettingsViewModel.CreationStamp.defaultsKey)
    private var creationStampRaw: String = SettingsViewModel.CreationStamp.default.rawValue
    private var showsStamp: Bool {
        (SettingsViewModel.CreationStamp(rawValue: creationStampRaw) ?? .default) != .off
            && !hidesStampForRoom
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The "Created on" row's last measured height, top pad included. It wraps to a second line
    /// when the time is wide enough, so the cap reads this instead of assuming one line.
    @State private var stampRowHeight: CGFloat = TakeEditCard.stampRowEstimate

    /// At accessibility text sizes the stamp wraps onto several large lines, and with the keyboard
    /// up there is no room for it: the heading, the editor's minimum height, the stamp and the
    /// keyboard do not fit together, the minimum wins, and the card grows past its cap until its
    /// Iris and first line sit under the heading fade (measured: a 143pt stamp row
    /// against 249pt of room). So the stamp stands down while typing at those sizes and returns
    /// when the keyboard goes (owner's choice 2026-09-30). Default sizes are untouched.
    private var hidesStampForRoom: Bool {
        dynamicTypeSize.isAccessibilitySize && keyboardTopY < UIScreen.main.bounds.height
    }

    /// The keyboard's top edge in screen coords, INCLUDING its docked toolbar.
    @State private var keyboardTopY: CGFloat = .greatestFiniteMagnitude
    /// A keyboard hide that arrived while `holdsPlace`, applied when the hold ends.
    @State private var heldKeyboardTopY: CGFloat?
    /// Where the card's bottom sits, in window coordinates, while the Focus row holds it. Set when
    /// the hold catches a keyboard hide, cleared once the keyboard is back and this view's bottom
    /// edge has returned to where it was. While it is set the padding is worked out from the live
    /// bottom edge in the same layout pass, so the card stays put while the edge moves. The edge
    /// moves in steps a frame apart as the keyboard goes (measured on an iPhone 16 simulator:
    /// 462, 818, 852), and a fixed home-indicator shift matched only the last step, so the card
    /// jumped 34pt up for a frame (owner report 2026-11-14, "jumpy").
    @State private var heldCardBottom: CGFloat?
    /// This view's bottom edge, in window coordinates, as last laid out. A box, so recording it
    /// never asks for another layout.
    @State private var edge = EdgeBox()
    /// `settled` is the edge as last laid out while nothing held the card: the edge to hold from.
    final class EdgeBox {
        var maxY: CGFloat = 0; var settled: CGFloat = 0; var atHold: CGFloat = 0; var keyboardAtHold: CGFloat = 0
    }

    /// Hold the card where it is now. The keyboard's hide and this view's bottom edge can arrive in
    /// either order (iOS 27 sends the hide first, iOS 26 moves the edge first, measured on
    /// simulators), so the hold starts from the edge as it was before either, not the latest edge.
    private func startHold() {
        guard heldCardBottom == nil else { return }
        edge.atHold = edge.settled
        edge.keyboardAtHold = keyboardTopY
        heldCardBottom = edge.settled - bottomPadding(edgeMaxY: edge.settled)
    }

    /// The bottom padding that puts the card where it belongs for a bottom edge at `edgeMaxY`.
    private func bottomPadding(edgeMaxY: CGFloat) -> CGFloat {
        if let heldCardBottom { return max(0, edgeMaxY - heldCardBottom) }
        // With the keyboard up and the bar's real top known, the card's bottom sits 8pt above the
        // bar, on every iOS version (iOS 26 reports a keyboard top that includes the bar, iOS 27
        // one that leaves it out, so the keyboard alone can't place it).
        if keyboardTopY < UIScreen.main.bounds.height, let barPanelTop {
            return max(0, edgeMaxY - (barPanelTop - 8))
        }
        return max(0, UIScreen.main.bounds.height - keyboardTopY) + bottomLift + barRoom
    }

    /// The top of the editor bar's panel on screen, as the bar last reported it.
    @State private var barPanelTop: CGFloat?

    /// The extra room under the card, on top of `bottomLift`, that keeps the card's bottom 8pt
    /// above the editor's bar while the keyboard is up, whatever the lift (Art Director
    /// 2026-11-14: the card always shows its own bottom edge above the solid panel).
    ///
    /// The keyboard's last frame report leaves the bar out (measured on an iPhone 16 simulator:
    /// 430 with it, then 524 without), and this view's bottom edge sits the home-indicator inset
    /// above the screen's. With the old ringed 62pt bar that room happened to clear the bar on a
    /// phone with a home indicator at full lift (34 + 36 = 70), but not once the lift closed, and
    /// never on an iPhone SE (0 + 36), where the card ran under the buttons behind the fade.
    private var barRoom: CGFloat {
        guard keyboardTopY < UIScreen.main.bounds.height else { return 0 }
        // Used only before the bar has reported where it is: the estimate from its height.
        let bar = EditorKeyboardBar.panelHeight(for: dynamicTypeSize, screenWidth: UIScreen.main.bounds.width)
        return max(0, bar + 18 + 8 - homeIndicatorInset - bottomLift)
    }

    /// The card's last reported RAW content height — drives the bottom drop.
    @State private var editorContentHeight: CGFloat = 30

    /// One text line — the metric behind the descent and the downward growth.
    private static let lineH: CGFloat = 18
    /// How many lines the card's bottom drops (grows DOWN) after the descent, before it grows up.
    private static let downExpandLines: CGFloat = 2
    /// The content floor the caret descends through. One text line is ~18pt and a 1-line block is
    /// ~30pt, so 66pt ≈ room for the caret to drop two lines.
    private static let descentFloor: CGFloat = 66
    /// Keyboard + toolbar estimate, used only before the real keyboard frame arrives.
    private static let keyboardReserveFallback: CGFloat = 400
    /// Inert while `descentFloor` dominates (the floor forces a taller frame regardless), but kept
    /// at the value `DailiesView` was device-validated with rather than quietly re-tuned.
    private static let minEditorHeight: CGFloat = 44

    /// How far the card's bottom is LIFTED above the keyboard right now. It stays
    /// `downExpandLines` up through the whole DESCENT (while content < the floor, the caret falling
    /// to the stamp), then closes to 0 over the next that-many lines of content — so the card's
    /// bottom drops to the keyboard only AFTER the caret has reached the bottom.
    private var bottomLift: CGFloat {
        let span = Self.lineH * Self.downExpandLines
        let phase = min(1, max(0, (editorContentHeight - Self.descentFloor) / span))
        return span * (1 - phase)
    }

    /// How far below the cap's limit the card's TOP EDGE stops, so the Iris inside it keeps
    /// `irisHeadroom` clear of the pinned heading.
    ///
    /// That heading is drawn AFTER this card in `DailiesView`'s ZStack and takes taps across its whole
    /// frame (`contentShape` + `timelineBackgroundTap`), so an overlapped Iris isn't merely hidden
    /// under the fade, it's dead: a tap meant for the Focus row commits the edit instead (owner
    /// 2026-08-11). The Iris sits `irisInset` below the card's top, so the card itself needs only
    /// the rest of the headroom.
    private var irisReserve: CGFloat {
        showsIris ? max(0, Self.irisHeadroom - CatchlightLayout.irisInset) : 0
    }

    /// Breathing room between the heading's limit and the Iris's top edge (owner 2026-08-11,
    /// device round 2): with less, the Iris cleared the fade but sat hard against it and read as
    /// crowded ("sits a little high still"). An OWNER-TUNED number like the descent / drop
    /// geometry below; push it either way rather than re-deriving it. Each point costs a point of
    /// editor height, but only once the card is at full extension.
    private static let irisHeadroom: CGFloat = 18

    /// The grow-UP cap: how tall the card may get before its TOP reaches the heading, past which
    /// `BlockEditor` scrolls internally.
    private var maxHeight: CGFloat {
        let topLimit = deviceTopInset + headingClearance + 12 + irisReserve
        // Use the live keyboard top; fall back to the static estimate before it settles.
        let kbTop = keyboardTopY < UIScreen.main.bounds.height
            ? keyboardTopY
            : UIScreen.main.bounds.height - Self.keyboardReserveFallback
        // The floor is small on purpose. It used to be 160, and a fixed floor larger than the room
        // pushes the card past its own cap and its Iris under the heading fade (a notice
        // strip on an iPhone 16 left 114pt of room). With ample room, the usual case, the cap is
        // the room itself and the floor never applies.
        // The card's bottom: 8pt above the bar once the bar has said where it is.
        let floorY = keyboardTopY < UIScreen.main.bounds.height ? barPanelTop.map { $0 - 8 } : nil
        return max(Self.editorFloor, (floorY ?? kbTop - barRoom) - topLimit
                                     - TakeEditCard.chrome(stampRow: showsStamp ? stampRowHeight : 0))
    }

    /// The least the editor frame ever shrinks to while typing: about two lines at the default size.
    private static let editorFloor: CGFloat = 60

    /// Bottom-anchored, riding the system keyboard. NO custom keyboard animation — it rides in sync
    /// with `BlockEditor`'s own handling (a custom rise desynced and scrolled the text off-screen,
    /// the first M5a attempt).
    ///
    /// Never move the editor yourself in answer to the keyboard. Driving it from
    /// `keyboardWillChangeFrameNotification` with a constraint animation of its own hard-locked the
    /// device, and only a reboot recovered it: that animation deadlocks against `BlockEditor`'s own
    /// keyboard handling. `BlockEditor` owns the keyboard. This view only reads the keyboard's top
    /// edge to set its bottom padding, adds no animation, and caps the card at the room above the
    /// keyboard (`maxHeight`) so the editor's own scrolling starts before the caret reaches it.
    var body: some View {
        GeometryReader { proxy in
        let edgeMaxY = proxy.frame(in: .global).maxY
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            TakeEditCard(
                draft: $draft,
                focusedBlockID: $focusedBlockID,
                maxHeight: maxHeight,
                minContent: Self.descentFloor,
                minEditorHeight: Self.minEditorHeight,
                showsIris: showsIris,
                onOpenAngle: onOpenAngle,
                onEditReminder: onEditReminder,
                onDiscard: onDiscard,
                onTapIris: onTapIris,
                onContentHeightChange: { editorContentHeight = $0 },
                axHidden: axHidden,
                hidesStamp: hidesStampForRoom,
                onStampRowHeightChange: { stampRowHeight = $0 }
            )
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset ?? leadingInset)
        }
        .padding(.bottom, bottomPadding(edgeMaxY: edgeMaxY))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onGeometryChange(for: CGFloat.self) { _ in edgeMaxY } action: { newEdge in
            edge.maxY = newEdge
            // The edge moved while the Focus row holds the card: the keyboard is leaving.
            if holdsPlace(), heldCardBottom == nil, keyboardTopY < .greatestFiniteMagnitude, newEdge != edge.settled {
                startHold()
            }
            if heldCardBottom == nil, !holdsPlace() { edge.settled = newEdge }
            // The keyboard is back and the edge has returned to where the hold began: the usual
            // padding now puts the card exactly where it is held, so let go.
            if heldCardBottom != nil, heldKeyboardTopY == nil, !holdsPlace(), abs(newEdge - edge.atHold) < 0.5,
               abs(keyboardTopY - edge.keyboardAtHold) < 0.5 {
                heldCardBottom = nil
            }
        }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .transition(.opacity)
        // Track the keyboard's top edge (incl. its docked toolbar). willHide reports
        // origin.y = screen height, which parks the card back at the bottom.
        .onReceive(NotificationCenter.default.publisher(for: EditorBarPlacement.panelTopDidChange)) { note in
            // While the Focus row holds the card the bar is leaving with the keyboard: its moving
            // top must not move the card before the hold catches it.
            guard !holdsPlace(), let top = note.userInfo?["top"] as? CGFloat, top != barPanelTop else { return }
            barPanelTop = top
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let rawFrame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            else { return }
            let frame = rawFrame
            if holdsPlace() && frame.origin.y > keyboardTopY {
                if heldCardBottom == nil {
                    startHold()
                }
                heldKeyboardTopY = frame.origin.y
                return
            }
            heldKeyboardTopY = nil
            keyboardTopY = frame.origin.y
            // The returning keyboard can first report a top that is too high (462, then 524 a frame
            // later, measured), so the hold lasts until it reports the top it had when held.
            if heldCardBottom != nil, !holdsPlace(), abs(edge.maxY - edge.atHold) < 0.5,
               abs(keyboardTopY - edge.keyboardAtHold) < 0.5 { heldCardBottom = nil }
        }
        .onChange(of: holdsPlace()) { _, holds in
            guard !holds else { return }
            // The keyboard came back while the row was still open: nothing is held any more.
            guard heldKeyboardTopY != nil else {
                heldCardBottom = nil
                return
            }
            // The keyboard usually comes back as the row closes, and its show then clears the
            // held hide. Applying the hide here first parked the card at the bottom of the
            // screen for the few frames before the show arrived. Apply it only if no show came.
            // Either way let go of the card: a keyboard that came back at a different top (the
            // predictive bar, another keyboard, a hardware keyboard) never matches the top it
            // was held at, and the card would otherwise stop following the keyboard.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard !holdsPlace() else { return }
                if let held = heldKeyboardTopY {
                    heldKeyboardTopY = nil
                    keyboardTopY = held
                }
                heldCardBottom = nil
            }
        }
    }
}

