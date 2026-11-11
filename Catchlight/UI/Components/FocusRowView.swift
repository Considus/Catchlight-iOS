//
//  FocusRowView.swift
//  Catchlight (iOS app target)
//
//  The Focus row: the activity-type selector, opened by tapping a Take's Iris. It
//  follows the Iris prototype's `openMarks` and `.mk` styles.
//
//  LAYOUT: four 44pt rounded-square marks, Note, Task, Reminder and Important from
//  left to right, 16pt apart, their centres 60, 120, 180 and 240pt right of the Iris
//  centre. While the row is open the tapped card grows 22pt (half a mark) at the
//  bottom, and the cards below move down with it; the marks' centres sit exactly on the
//  grown bottom edge, so they clear its last line of text (`rowY`). Where that would put
//  the row below the visible area (behind the dock, or above the bottom of the screen
//  while editing), the row lifts to stay on screen. On a screen too narrow for the full
//  row the gap shrinks evenly so the last mark stays 8pt inside the screen; the marks
//  never shrink or overlap (`slotX`).
//
//  MOTION (`Timing`): the marks start stacked under the Iris at 85% size, invisible.
//  They drop straight down to the card's grown bottom edge over 340ms (easeInOutCubic),
//  while the card grows on the same curve, reaching full size with the drop and fading
//  in over its first 80ms. The far marks peel off first and slide right to their slots while still
//  dropping (Important at 120ms, Reminder 185, Task 250, Note 340), each slide lasting
//  3.9ms per point travelled and at least 280ms, with a small easeOutBack overshoot:
//  about 1.06s in all. Closing plays the whole open backwards, 1.25 times faster. Reduce
//  Motion and UI tests skip straight to the end state.
//
//  STYLE: an off mark is a ground-coloured square with a half-strength lit border and a
//  lit line glyph; an on mark is filled with the Scene accent and its glyph takes the
//  on-accent colour. The lit colour marks the Focus marks and nothing else.
//
//  The veil (ckDim) dims everything beneath; the tapped Take's card is lifted back lit
//  above it (`showsFocusCard` / `TakeCardSurface`). From the editor footer there is no
//  lifted card: the editor is the context there.
//
//  Mark taps toggle the working selection; tapping the veil commits and closes. Note is
//  the floor.
//

import SwiftUI
import CatchlightCore

struct FocusRowView: View {
    let take: Take
    /// The tapped Take's card, in the overlay's (window) space. The hub sits on its Iris,
    /// the row runs along its bottom edge, and the lit copy is drawn over it.
    let cardFrame: CGRect
    /// Full overlay width (screen width): used to keep the row on screen.
    var containerWidth: CGFloat = 0
    /// The lowest y the row may reach: the top of the keyboard or the dock. 0 is unknown
    /// (previews): no clamp.
    var visibleBottom: CGFloat = 0
    /// Screen-space point of the hub (centre of the tapped Iris).
    private var hubCentre: CGPoint { Self.hubCentre(of: cardFrame) }
    /// Whether to lift the tapped Take's card above the veil (owner 2026-06-16).
    /// True when the row opens from a timeline Iris (`hubCentre` is a real row);
    /// false from the editor footer (the editor IS the context there, so no card to
    /// spotlight).
    var showsFocusCard: Bool = false
    /// `reminderDate` carries the time chosen in the picker (nil when no Reminder).
    /// `reminderAlarm` / `reminderAllDay` carry the model-C picker choices (owner
    /// 2026-06-18) — undefined/ignored when `hasReminder` is false.
    let onCommit: (_ isNote: Bool, _ isTask: Bool, _ hasReminder: Bool, _ reminderDate: Date?, _ reminderAlarm: Bool, _ reminderAllDay: Bool, _ reminderRecurrence: TimeReminder.Recurrence, _ reminderWeekdays: Set<Int>, _ reminderLocation: LocationTrigger?, _ isImportant: Bool) -> Void
    let onDismiss: () -> Void
    /// Grow (true) or shrink back (false) the tapped card over this many seconds (nil: at
    /// once), on the drop's curve. Only called when `showsFocusCard`: the row runs along a
    /// timeline card or the pinned Obie.
    var onCardGrowth: (_ grown: Bool, _ duration: Double?) -> Void = { _, _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Collapse the row's choreography to an instant open/close when the user has
    /// Reduce Motion on — OR under `--uitesting`, so XCUITest doesn't race the
    /// animation (a known flake source). Mirrors the app-wide
    /// `UIView.setAnimationsEnabled(false)` that UI-test launches set for UIKit.
    private var instantMotion: Bool {
        reduceMotion
            || (ProcessInfo.processInfo.arguments.contains("--uitesting")
                && Self.uiTestTimeScale == nil && frozenAt == nil)
    }

    /// UI tests only: `--uitesting -catchlight.focusRowFreezeAt <s>` holds every open after the
    /// first at `s` seconds into the choreography, and keeps it there: the marks stay where
    /// they are at that instant, and taps are judged against that layout and hit gate, so a
    /// test needs no timing. The first open still plays instantly, so a test can set the Take
    /// up first. Compiled out of Release, like the time scale.
    private static let uiTestFreezeAt: Double? = {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--uitesting") else { return nil }
        let at = UserDefaults.standard.double(forKey: "catchlight.focusRowFreezeAt")
        return at > 0 ? at : nil
        #else
        return nil
        #endif
    }()
    #if DEBUG
    nonisolated(unsafe) private static var opensSoFar = 0
    #endif
    /// The freeze for the open that is starting now: none for the first open.
    private static func freezeForThisOpen() -> Double? {
        #if DEBUG
        opensSoFar += 1
        return opensSoFar > 1 ? uiTestFreezeAt : nil
        #else
        return nil
        #endif
    }
    @State private var frozenAt: Double?

    /// Seconds into the open at `now`, held at the UI-test freeze when there is one.
    private func openTime(since start: Date, now: Date) -> Double {
        let t = now.timeIntervalSince(start) / Self.timeScale
        return frozenAt.map { min(t, $0) } ?? t
    }

    /// UI tests only: `--uitesting -catchlight.focusRowTimeScale <n>` plays the choreography
    /// n times slower instead of skipping it, so a test can tap the row mid-open.
    /// Compiled out of Release, like the `--uitesting` store in `Wiring`.
    private static let uiTestTimeScale: Double? = {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--uitesting") else { return nil }
        let scale = UserDefaults.standard.double(forKey: "catchlight.focusRowTimeScale")
        return scale > 0 ? scale : nil
        #else
        return nil
        #endif
    }()
    /// Real seconds per choreography second: 1 outside that UI-test hook.
    private static var timeScale: Double { uiTestTimeScale ?? 1 }

    /// Default "when" a freshly-added reminder opens to — now a user preference
    /// (Settings → Reminders → Default timing (hrs); owner 2026-06-18). Read at call
    /// time from UserDefaults so it always reflects the current setting; the picker
    /// opens here and the user refines or accepts it.
    static var defaultReminderDate: Date {
        SettingsViewModel.DefaultReminderHours.current().date()
    }

    // Working selection (mutated as marks are tapped).
    @State private var isNote: Bool
    @State private var isTask: Bool
    @State private var hasReminder: Bool
    /// The Important flag — the fourth Mark toggles it (owner 2026-07-06; replaced the
    /// Obie Mark). Orthogonal to the type Marks: an Important Take can be any type.
    /// Obie stays reachable via the Iris long-press; the row never changes it.
    @State private var isImportant: Bool
    /// The working Reminder time. Seeded from the Take's existing reminder (or the
    /// +24h default) and edited by the picker that pops when the Reminder Mark is
    /// tapped on (owner 2026-06-17).
    @State private var reminderDate: Date
    /// Model-C picker choices (owner 2026-06-18): whether the "when" also rings, and
    /// whether it's a date-only (all-day) placement. Seeded from any existing reminder.
    @State private var reminderAlarm: Bool
    @State private var reminderAllDay: Bool
    /// How often the reminder repeats (owner 2026-06-21). Seeded from any existing
    /// reminder; `.none` for a one-shot.
    @State private var reminderRecurrence: TimeReminder.Recurrence
    /// The weekdays a WEEKLY reminder repeats on (owner 2026-06-23) — empty for every other
    /// cadence. Seeded from any existing reminder; edited by the picker's day strip.
    @State private var reminderWeekdays: Set<Int>
    /// The location ("where") for this reminder (owner 2026-06-23) — nil for time-only.
    @State private var reminderLocation: LocationTrigger?
    /// Drives the date/time picker sheet the Reminder Mark pops.
    @State private var showingReminderPicker = false

    private enum RowPhase: Equatable {
        case opening(start: Date)
        case open
        case closing(start: Date, commit: Bool)
        /// Terminal STATIC state, set the instant the row commits — BEFORE the overlay
        /// is removed. `.closing` keeps the TimelineView animating, which prevented
        /// SwiftUI from tearing the view down when `focusRowTake` went nil: the veil
        /// lingered in `.closing` and ate every tap, stranding the user over a
        /// perfectly-fine editor (owner-reported lockup 2026-06-18, confirmed via an
        /// on-device state trace). `.dismissed` is non-animating (TimelineView pauses →
        /// the view can be removed) and renders fully retracted/invisible, matching the
        /// close animation's end frame so there's no flash.
        case dismissed
    }
    @State private var phase: RowPhase

    init(take: Take,
         cardFrame: CGRect,
         containerWidth: CGFloat = 0,
         visibleBottom: CGFloat = 0,
         showsFocusCard: Bool = false,
         onCommit: @escaping (Bool, Bool, Bool, Date?, Bool, Bool, TimeReminder.Recurrence, Set<Int>, LocationTrigger?, Bool) -> Void,
         onDismiss: @escaping () -> Void,
         onCardGrowth: @escaping (Bool, Double?) -> Void = { _, _ in }) {
        self.take = take
        self.cardFrame = cardFrame
        self.containerWidth = containerWidth
        self.visibleBottom = visibleBottom
        self.showsFocusCard = showsFocusCard
        self.onCommit = onCommit
        self.onDismiss = onDismiss
        self.onCardGrowth = onCardGrowth
        _isNote = State(initialValue: take.isNote)
        _isTask = State(initialValue: take.isTask)
        _hasReminder = State(initialValue: take.timeReminder != nil)
        _isImportant = State(initialValue: take.isImportant)
        _reminderDate = State(initialValue: take.timeReminder?.scheduledDate ?? Self.defaultReminderDate)
        _reminderAlarm = State(initialValue: take.timeReminder?.alarmEnabled ?? true)
        _reminderAllDay = State(initialValue: take.timeReminder?.isAllDay ?? false)
        _reminderRecurrence = State(initialValue: take.timeReminder?.recurrence ?? .none)
        _reminderWeekdays = State(initialValue: take.timeReminder?.weekdays ?? [])
        _reminderLocation = State(initialValue: take.locationReminder)
        _phase = State(initialValue: .opening(start: .now))
    }

    // MARK: - Marks

    /// The four marks, in row order from left to right.
    enum MarkKind: Int, CaseIterable {
        case note, task, remind, important
        var title: String {
            switch self {
            case .note: return String(localized: "Note")
            case .task: return String(localized: "Task")
            case .remind: return String(localized: "Remind")
            case .important: return String(localized: "Important")
            }
        }
        /// Stable suffix for the XCUITest accessibilityIdentifier ("focus-row-mark-task" etc.).
        var identifierSuffix: String {
            switch self {
            case .note: return "note"
            case .task: return "task"
            case .remind: return "remind"
            case .important: return "important"
            }
        }
    }

    // MARK: - Row geometry

    /// Each mark's side: a full touch target, never shrunk to fit.
    static let markSize: CGFloat = 44
    /// The marks are controls: the shared control radius, never circles or pills.
    static let markCornerRadius: CGFloat = CatchlightLayout.cappedRadius(forHeight: markSize)
    /// Centre-to-centre spacing on a screen with room for it: a 16pt gap between 44pt marks.
    static let markSpacing: CGFloat = markSize + 16
    /// The least room kept between the last mark and the screen's trailing edge.
    static let screenMargin: CGFloat = 8
    /// How far the Iris centre sits in from its card's top and leading edges (36).
    static let irisCentreInset = CatchlightLayout.irisInset + CatchlightLayout.circleDiameter / 2
    /// How much the tapped card grows at the bottom while the row is open (22, half a
    /// mark): the marks sit centred on its grown bottom edge, so this keeps them clear of
    /// its last line of text.
    static let cardGrowth: CGFloat = markSize / 2

    /// The Iris centre of a card: `irisCentreInset` in from its top and leading edges.
    static func hubCentre(of cardFrame: CGRect) -> CGPoint {
        CGPoint(x: cardFrame.minX + irisCentreInset, y: cardFrame.minY + irisCentreInset)
    }

    /// A card's frame from its Iris centre (as the Iris's tap recognizer reports it, in
    /// window coordinates) and the card's measured size.
    static func cardFrame(irisCentre: CGPoint, cardSize: CGSize) -> CGRect {
        CGRect(x: irisCentre.x - irisCentreInset, y: irisCentre.y - irisCentreInset,
               width: cardSize.width, height: cardSize.height)
    }

    /// The row's resting y offset from the Iris centre: exactly on the card's bottom edge
    /// once it has grown by `cardGrowth`, lifted so a mark's bottom stays at or above
    /// `visibleBottom` (0 = no clamp), and never above the Iris centre.
    static func rowY(cardFrame: CGRect, visibleBottom: CGFloat) -> CGFloat {
        let y = cardFrame.height + cardGrowth - irisCentreInset
        guard visibleBottom > 0 else { return y }
        let lowest = visibleBottom - markSize / 2 - hubCentre(of: cardFrame).y
        return max(0, min(y, lowest))
    }

    /// A mark's resting x offset from the Iris centre. Marks sit `markSpacing` apart;
    /// when the last one would cross `screenMargin`, the spacing shrinks evenly so it
    /// lands on the margin, but never below `markSize`, so the marks never overlap. With
    /// the Iris at its real place that starts below about 319pt wide, narrower than any
    /// supported phone. `containerWidth` 0 means unknown (previews): no squeeze.
    static func slotX(for index: Int, hubX: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let count = CGFloat(MarkKind.allCases.count)
        var spacing = markSpacing
        if containerWidth > 0 {
            let limit = containerWidth - screenMargin - markSize / 2
            if hubX + count * markSpacing > limit {
                spacing = max(markSize, (limit - hubX) / count)
            }
        }
        return CGFloat(index + 1) * spacing
    }

    // MARK: - Choreography (the Iris prototype's `openMarks`)

    /// When each part of the open happens, in seconds from the tap. The close plays the
    /// whole open backwards, `closeSpeed` times faster.
    enum Timing {
        /// All four marks drop together from under the Iris to the card's grown bottom edge,
        /// and the card grows, on easeInOutCubic.
        static let drop: Double = 0.340
        /// The marks fade in, linearly, over this first part of the drop.
        static let fadeIn: Double = 0.080
        /// Size the marks start at, under the Iris; they reach full size with the drop.
        static let startScale: CGFloat = 0.85
        /// The close plays the open backwards this much faster.
        static let closeSpeed: Double = 1.25

        /// When a mark starts sliding right to its slot: the far marks peel off first, while
        /// the drop is still running, and Note last, as the drop ends.
        static func spreadStart(_ kind: MarkKind) -> Double {
            switch kind {
            case .important: return 0.120
            case .remind: return 0.185
            case .task: return 0.250
            case .note: return 0.340
            }
        }
        /// The shortest slide.
        static let minSpread: Double = 0.280
        /// A slide lasts this long per point travelled, so far marks travel at the pace of
        /// near ones (Note 280, Task 468, Reminder 702, Important 936ms at the phone slots).
        static let spreadPerPoint: Double = 0.0039
        /// How long a mark takes to slide `travel` points to its slot.
        static func spreadDuration(travel: CGFloat) -> Double {
            max(minSpread, Double(abs(travel)) * spreadPerPoint)
        }
        /// When the open ends: the last mark lands. `slots` are the marks' x offsets from the
        /// Iris centre, in `MarkKind` order.
        static func openDuration(slots: [CGFloat]) -> Double {
            MarkKind.allCases.map { spreadStart($0) + spreadDuration(travel: slots[$0.rawValue]) }.max() ?? drop
        }
        static func closeDuration(slots: [CGFloat]) -> Double { openDuration(slots: slots) / closeSpeed }
        /// The point of the open every mark shows `elapsed` seconds into the close: the whole
        /// open backwards, so the marks retrace their paths in step and the card shrinks last.
        static func closeTime(elapsed: Double, slots: [CGFloat]) -> Double {
            openDuration(slots: slots) - elapsed * closeSpeed
        }

        /// The marks' opacity at time t of the open.
        static func markOpacity(at t: Double) -> Double { clamp(t / fadeIn) }
        /// The marks' scale at time t of the open.
        static func markScale(at t: Double) -> CGFloat {
            startScale + (1 - startScale) * CGFloat(easeInOutCubic(clamp(t / drop)))
        }
        /// How far the marks have dropped, and the card grown, at time t of the open (0 to 1).
        static func dropProgress(at t: Double) -> Double { easeInOutCubic(clamp(t / drop)) }
        /// How far a mark has slid to its slot at time t of the open (0 to 1, overshooting a little).
        static func spreadProgress(_ kind: MarkKind, at t: Double, travel: CGFloat) -> Double {
            easeOutBack(clamp((t - spreadStart(kind)) / spreadDuration(travel: travel)))
        }

        private static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    }

    /// The marks' x offsets from the Iris centre, in `MarkKind` order.
    private var slots: [CGFloat] {
        MarkKind.allCases.map { Self.slotX(for: $0.rawValue, hubX: hubCentre.x, containerWidth: containerWidth) }
    }

    // Easings — identical curves to the prototype.
    static func easeOutBack(_ p: Double) -> Double {
        let s = 1.15
        return 1 + (s + 1) * pow(p - 1, 3) + s * pow(p - 1, 2)
    }
    static func easeInOutCubic(_ p: Double) -> Double {
        p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
    }

    /// A mark takes taps only past this share of its rise, when it is visibly out from the Iris.
    private static let hitTestRise = 0.5

    /// How a mark is drawn at a point of the open.
    private struct MarkProgress {
        /// 0 under the Iris to 1 on the card's edge: the drop.
        var rise: Double
        /// 0 stacked to 1 in its slot (overshooting a little past 1).
        var spread: Double
        var opacity: Double
        var scale: CGFloat

        static let rest = MarkProgress(rise: 1, spread: 1, opacity: 1, scale: 1)
        static let hidden = MarkProgress(rise: 0, spread: 0, opacity: 0, scale: Timing.startScale)
    }

    private func openProgress(_ kind: MarkKind, at t: Double) -> MarkProgress {
        MarkProgress(rise: Timing.dropProgress(at: t),
                     spread: Timing.spreadProgress(kind, at: t, travel: slots[kind.rawValue]),
                     opacity: Timing.markOpacity(at: t),
                     scale: Timing.markScale(at: t))
    }

    /// The close plays the open backwards at `Timing.closeSpeed`.
    private func markProgress(_ kind: MarkKind, now: Date) -> MarkProgress {
        switch phase {
        case .opening(let start):
            return openProgress(kind, at: openTime(since: start, now: now))
        case .open:
            return .rest
        case .closing(let start, _):
            let elapsed = now.timeIntervalSince(start) / Self.timeScale
            return openProgress(kind, at: Timing.closeTime(elapsed: elapsed, slots: slots))
        case .dismissed:
            return .hidden
        }
    }

    /// How far the tapped card has grown, 0 to 1: on the drop's own curve and timing, and on
    /// the close with the whole open played backwards, so it shrinks as the marks lift.
    private func growProgress(now: Date) -> Double {
        let t: Double
        switch phase {
        case .opening(let start): t = openTime(since: start, now: now)
        case .open: return 1
        case .closing(let start, _):
            t = Timing.openDuration(slots: slots)
                - now.timeIntervalSince(start) / Self.timeScale * Timing.closeSpeed
        case .dismissed: return 0
        }
        return Timing.dropProgress(at: t)
    }


    /// Only the live phases drive the TimelineView; `.open` and `.dismissed` are
    /// static so it pauses (and `.dismissed` lets the overlay be removed).
    private var isAnimating: Bool {
        switch phase {
        case .opening, .closing: return true
        case .open, .dismissed:  return false
        }
    }

    /// The veil commits-and-closes only while the row is OPEN. See the `.allowsHitTesting`
    /// note on the veil — gating this prevents a lingering veil from eating taps.
    private var veilIsInteractive: Bool {
        if case .open = phase { return true }
        return false
    }

    /// The dim veil's opacity, ramped on the row's OWN clock so the veil dissolves
    /// symmetrically — fade IN over the open, fade OUT over the close, both at the
    /// same `dur` (owner 2026-06-17). The lit focus card rides it on the close.
    /// `.open` holds solid; Reduce Motion (phase jumps straight to `.open`) keeps the
    /// overlay's plain transition.
    private func veilOpacity(now: Date) -> Double {
        let dur = Timing.closeDuration(slots: slots)
        switch phase {
        case .opening(let start):
            let p = min(max(openTime(since: start, now: now) / dur, 0), 1)
            return Self.easeInOutCubic(p)
        case .open:
            return 1
        case .closing(let start, _):
            let p = min(max(now.timeIntervalSince(start) / Self.timeScale / dur, 0), 1)
            return 1 - Self.easeInOutCubic(p)
        case .dismissed:
            return 0
        }
    }

    /// The lit card copy's opacity. Solid while the row opens: it lands exactly over the real
    /// card, so only its growth shows, in step with the drop. Fading it in with the veil hid
    /// that growth for the first 340ms and then faded it in once the cards below had moved,
    /// which read as the card popping taller. Fades out with the veil on close.
    private func litCardOpacity(now: Date) -> Double {
        switch phase {
        case .opening, .open: return 1
        case .closing: return veilOpacity(now: now)
        case .dismissed: return 0
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            rowContent
            // The reminder "when" editor rides INSIDE the row's own hierarchy, NOT a
            // system `.sheet`. Presenting a sheet from within this Focus row overlay
            // (itself a conditionally-rendered `.overlay` in RootView) left the row
            // wedged after the picker dismissed — the veil's commit tap went dead and
            // the row could not be closed, stranding the user (owner-reported lockup,
            // 2026-06-18). A modal presented from inside such an overlay isn't reliably
            // torn down by UIKit, so its gesture/first-responder state never restores.
            // An in-hierarchy layer sidesteps that entirely.
            if showingReminderPicker {
                reminderPickerLayer
                    // Slide UP from the bottom like a system sheet (owner 2026-06-18).
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            }
        }
        // A smooth, minimal-bounce spring approximating the iOS sheet present/dismiss.
        .animation(.spring(response: 0.52, dampingFraction: 0.9), value: showingReminderPicker)
        .onAppear {
            frozenAt = Self.freezeForThisOpen()
            if instantMotion { phase = .open }
            else { phase = .opening(start: .now) }
            if showsFocusCard {
                onCardGrowth(true, instantMotion ? nil : Timing.drop * Self.timeScale)
            }
            // Settle into the static .open phase once the choreography ends so
            // the TimelineView stops ticking.
            // The veil takes the closing tap once the open has finished.
            DispatchQueue.main.asyncAfter(deadline: .now() + (Timing.openDuration(slots: slots) + 0.05) * Self.timeScale) {
                if case .opening = phase, frozenAt == nil { phase = .open }
            }
        }
    }

    /// The reminder "when" editor, drawn as an opaque layer over the row (see `body`
    /// for why it is NOT a system sheet). Save/Cancel hide it by clearing
    /// `showingReminderPicker`; `ReminderPickerSheet`'s own `dismiss()` is an inert
    /// no-op in this in-place context, so these closures own the hide.
    private var reminderPickerLayer: some View {
        ReminderPickerSheet(
            initialDate: reminderDate,
            initialAlarm: reminderAlarm,
            initialAllDay: reminderAllDay,
            initialRecurrence: reminderRecurrence,
            initialWeekdays: reminderWeekdays,
            initialLocation: reminderLocation,
            onSave: { date, alarm, allDay, recurrence, weekdays, location in
                reminderDate = date
                reminderAlarm = alarm
                reminderAllDay = allDay
                reminderRecurrence = recurrence
                reminderWeekdays = weekdays
                reminderLocation = location
                hasReminder = true
                showingReminderPicker = false
            },
            onCancel: {
                // Cancel = remove the JUST-ADDED reminder (the picker only opens on
                // an inactive→active mark tap, so there's no pre-existing state to
                // preserve). Clear the place too (2026-07-01) — leaving it made the
                // cancelled selection silently re-commit as a location reminder.
                hasReminder = false
                reminderLocation = nil
                showingReminderPicker = false
            }
        )
        // Background now lives inside ReminderPickerSheet itself (owner 2026-06-29).
    }

    private var rowContent: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isAnimating)) { context in
            let now = context.date
            ZStack {
                // The veil — tap to COMMIT the current selection and dismiss.
                // (Mark taps toggle but never close; the veil tap is the
                // commit gesture — see the 4.5/7.4 audit note in history.)
                Color.ckDim
                    .opacity(veilOpacity(now: now))
                    // Opened from the card being edited: that card IS the Take, so the veil
                    // leaves it lit where it stands instead of drawing a copy over it (owner
                    // 2026-11-11: the Take should stay in place and visible). Only the look
                    // has the window; a tap on the card still commits and closes, as before.
                    .mask {
                        if !showsFocusCard, cardFrame.width > 0 {
                            VeilWindow(window: cardFrame)
                                .fill(style: FillStyle(eoFill: true))
                        } else {
                            Rectangle()
                        }
                    }
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { retractAndDismiss(commit: true) }
                    // The veil only catches taps while the row is genuinely OPEN.
                    // Once it's opening/closing/dismissed, taps fall THROUGH to the
                    // editor beneath — so a veil that lingers mid-teardown can never
                    // strand the user (owner lockup 2026-06-18).
                    .allowsHitTesting(veilIsInteractive)
                    .accessibilityIdentifier("focus-row-dim")
                    .accessibilityLabel("Save and close")
                    .accessibilityHint("Double-tap to apply your selection and close.")
                    .accessibilityAddTraits(.isButton)

                // The tapped Take, lifted LIT above the veil (owner 2026-06-16). A
                // pure-visual copy of the real row's card — non-interactive, so a tap
                // here falls through to the veil (commit & close), exactly like tapping
                // any other dimmed area. Drawn at `cardFrame`, the real card's measured
                // frame, so it lands exactly over it. Drawn BEFORE the marks so they pass
                // above it.
                if showsFocusCard, cardFrame.width > 0 {
                    // Grows over the real card, which keeps its size, on the drop's curve; the
                    // cards below move down with it (`onCardGrowth`).
                    let growth = Self.cardGrowth * growProgress(now: now)
                    TakeCardSurface(take: take, extraBottomPadding: growth)
                        .frame(width: cardFrame.width, height: cardFrame.height + growth, alignment: .topLeading)
                        .offset(x: cardFrame.minX, y: cardFrame.minY)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        // Fades out with the veil on close (owner 2026-06-17) so the
                        // lit Take resolves back into the brightening timeline rather
                        // than blinking off when the overlay is removed.
                        .opacity(litCardOpacity(now: now))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                let rowY = Self.rowY(cardFrame: cardFrame, visibleBottom: visibleBottom)
                ZStack {
                    // Drawn before the hub so the marks come out from beneath the Iris.
                    // Reversed, as before the redesign, so Note is drawn last and sits on top
                    // of the gathered marks: a tap on the stack toggles Note.
                    ForEach(MarkKind.allCases.reversed(), id: \.rawValue) { kind in
                        let p = markProgress(kind, now: now)
                        let slot = Self.slotX(for: kind.rawValue, hubX: hubCentre.x,
                                              containerWidth: containerWidth)
                        mark(kind)
                            .scaleEffect(p.scale)
                            .offset(x: slot * p.spread, y: rowY * p.rise)
                            .opacity(p.opacity)
                            // A mark takes taps only once it has risen visibly out from under the
                            // Iris, on the open and again on the close: a very early tap used to
                            // toggle a mark still hidden under the Iris.
                            .allowsHitTesting(p.rise > Self.hitTestRise)
                    }

                    // Hub: the Iris itself, previewing the working selection live. It takes no
                    // taps, so a tap anywhere on it reaches the veil (save and close), as the
                    // hollow-centred Iris before the redesign let it.
                    IrisView(take: workingTake, diameter: CatchlightLayout.circleDiameter)
                        .allowsHitTesting(false)
                        .accessibilityLabel("Selected: \(IrisView.activityDescription(for: workingTake))")
                }
                .position(hubCentre)
                .accessibilityElement(children: .contain)
            }
        }
    }

    /// A synthetic Take reflecting the working selection, so the hub circle
    /// previews the result live.
    private var workingTake: Take {
        var t = take
        t.isNote = isNote
        t.setTask(isTask)
        // The row never sets Obie — leave the Take's own designation intact. An Obie
        // implies Important (model invariant), so OR it in for the live Iris preview.
        t.isImportant = isImportant || t.isObie
        // Either/or (owner 2026-06-24): a location reminder takes precedence and clears the
        // time; otherwise the time "when" applies (when present).
        if let reminderLocation {
            t.locationReminder = reminderLocation
            t.timeReminder = nil
        } else {
            t.locationReminder = nil
            t.timeReminder = hasReminder
                ? TimeReminder(scheduledDate: reminderDate,
                               notificationIdentifier: t.id.uuidString,
                               alarmEnabled: reminderAlarm,
                               isAllDay: reminderAllDay,
                               recurrence: reminderRecurrence,
                               weekdays: reminderRecurrence == .weekly ? reminderWeekdays : [])
                    .keepingSeriesDay(of: t.timeReminder)
                : nil
        }
        return t
    }

    private func isActive(_ kind: MarkKind) -> Bool {
        switch kind {
        case .note: return isNote
        case .important: return isImportant
        // A "where" reads as an active Remind exactly like a "when" (2026-07-01,
        // place/time parity — previously a place-reminder Take showed an inactive
        // Remind mark, contradicting the card's place subtext).
        case .remind: return hasReminder || reminderLocation != nil
        case .task: return isTask
        }
    }

    @ViewBuilder
    private func mark(_ kind: MarkKind) -> some View {
        let active = isActive(kind)
        let face = RoundedRectangle(cornerRadius: Self.markCornerRadius)
        Button {
            toggle(kind)
        } label: {
            ZStack {
                // Off: ground face, lit border at half strength, lit glyph. On: the
                // Scene accent fills the face and the border takes the same colour, so
                // there is no separate rim, and the glyph turns on-accent.
                // Explicit `.zIndex` pins fill < border < glyph: toggling `active`
                // recolours them together, and without a pinned order SwiftUI could
                // momentarily paint the fresh fill over the border.
                face.fill(active ? Color.ckAdd : Color.ckGround)
                    .zIndex(0)
                face.strokeBorder(active ? Color.ckAdd : Color.ckLit.opacity(0.5), lineWidth: 1.5)
                    .zIndex(1)
                MarkGlyph(kind: kind)
                    .foregroundStyle(active ? Color.ckOnAccent : Color.ckLit)
                    .zIndex(2)
            }
            .frame(width: Self.markSize, height: Self.markSize)
            // A plain rectangle: with the rounded face as the content shape the mark
            // stopped taking taps, and they fell through to the veil (measured in
            // CoreFlowsUITests Flow 2, 2026-11-09).
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("focus-row-mark-\(kind.identifierSuffix)")
        .accessibilityLabel(kind.title)
        .accessibilityValue(isActive(kind) ? "active" : "inactive")
        .accessibilityHint(kind == .important && !take.canChangeImportant
                           ? "An Obie is always Important."
                           : (isActive(kind)
                    ? "Double-tap to remove \(kind.title)."
                    : "Double-tap to add \(kind.title)."))
        .accessibilityAddTraits(isActive(kind) ? [.isSelected, .isButton] : [.isButton])
    }

    /// A mark's line icon, drawn on the redesign's 24-unit icon grid at 24pt.
    private struct MarkGlyph: View {
        let kind: MarkKind

        var body: some View {
            ZStack {
                strokes.stroke(style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
                if kind == .important {
                    Path(ellipseIn: CGRect(x: 12 - 1.3, y: 17.2 - 1.3, width: 2.6, height: 2.6))
                        .fill()
                }
            }
            .frame(width: 24, height: 24)
        }

        private var strokes: Path {
            var p = Path()
            func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
                p.move(to: CGPoint(x: x1, y: y1))
                p.addLine(to: CGPoint(x: x2, y: y2))
            }
            switch kind {
            case .note:
                line(7, 8.5, 17, 8.5)
                line(7, 12, 17, 12)
                line(7, 15.5, 13, 15.5)
            case .task:
                p.move(to: CGPoint(x: 7, y: 12.4))
                p.addLine(to: CGPoint(x: 10.4, y: 15.8))
                p.addLine(to: CGPoint(x: 17, y: 8.6))
            case .remind:
                p.addEllipse(in: CGRect(x: 12 - 7, y: 12 - 7, width: 14, height: 14))
                line(12, 12, 12, 8)
                line(12, 12, 15, 13.6)
            case .important:
                line(12, 6.5, 12, 13.5)
            }
            return p
        }
    }

    // MARK: - Toggle (Note is the floor)

    private func toggle(_ kind: MarkKind) {
        withAnimation(CatchlightMotion.press) {
            switch kind {
            case .note:   isNote.toggle()
            case .task:   isTask.toggle()
            case .remind:
                // Either/or means "active" can be a "when" OR a "where" — toggling
                // OFF must clear BOTH (2026-07-01: previously only `hasReminder`
                // flipped, so the mark could never remove a place reminder).
                if isActive(.remind) {
                    hasReminder = false
                    reminderLocation = nil
                } else {
                    hasReminder = true
                }
            // An Obie is always Important (owner 2026-10-03): the Mark stays on. Without
            // this it showed off while the hub preview and the commit kept it on.
            case .important: if take.canChangeImportant { isImportant.toggle() }
            }
            // Note is the floor: if no activity TYPE is active, Note re-asserts. Important
            // is orthogonal (an Important Take is still a Note/Task/Remind), so it never
            // stands in for the floor the way the Obie designation used to.
            if !isTask && !isActive(.remind) { isNote = true }
        }
        // Turning the Reminder Mark ON pops the date/time picker so the user sets
        // the time (or place) there and then (owner 2026-06-17). Turning it off
        // just clears it.
        if kind == .remind && hasReminder { showingReminderPicker = true }
    }

    // MARK: - Retract

    private func retractAndDismiss(commit: Bool = false) {
        guard case .open = phase else {
            // Mid-choreography taps wait for the settle (matches the prototype guard).
            return
        }
        if instantMotion {
            if showsFocusCard { onCardGrowth(false, nil) }
            finish(commit: commit)
            return
        }
        phase = .closing(start: .now, commit: commit)
        if showsFocusCard {
            // The drop opened the row, so the card shrinks back over the close's last stretch.
            let shrink = Timing.drop / Timing.closeSpeed * Self.timeScale
            let wait = (Timing.openDuration(slots: slots) - Timing.drop) / Timing.closeSpeed * Self.timeScale
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                // Only while this close is still running: a row removed another way has
                // already reset the growth, and must not leave a stale Take behind.
                guard case .closing = phase else { return }
                onCardGrowth(false, shrink)
            }
        }
        let closeDuration = (Timing.closeDuration(slots: slots) + 0.05) * Self.timeScale
        DispatchQueue.main.asyncAfter(deadline: .now() + closeDuration) {
            if case .closing(_, let c) = phase { finish(commit: c) }
        }
    }

    private func finish(commit: Bool) {
        // Go STATIC before removing the overlay so the TimelineView pauses and SwiftUI
        // can actually tear the row down — a still-animating subtree lingered as a
        // tap-eating ghost veil (owner lockup 2026-06-18). `.dismissed` matches the
        // close animation's end frame, so there's no flash.
        phase = .dismissed
        if commit {
            onCommit(isNote, isTask, hasReminder, hasReminder ? reminderDate : nil, reminderAlarm, reminderAllDay, reminderRecurrence, reminderRecurrence == .weekly ? reminderWeekdays : [], reminderLocation, isImportant)
        } else {
            onDismiss()
        }
    }
}

/// The Reminder "when" editor — model C (owner 2026-06-18). A "when" is a scheduled
/// date with two selectable properties: whether it ALSO rings (`alarm`) and whether
/// it's a date-only placement (`allDay`). Popped by the Focus row's Reminder Mark
/// (set the "when" at creation) and reusable to change it later. The caller owns what
/// Save/Cancel mean for its own state (the Focus row uses Cancel to REMOVE a
/// just-added reminder).
///
/// LAYOUT (owner 2026-06-18): quick presets → options (all-day + alarm) → calendar.
/// The actionable controls sit ABOVE the bulky calendar so they're always visible;
/// the calendar — self-evidently a calendar — is what scrolls partially off-screen,
/// never the toggles. All dates come from `Calendar`/style-based formatters, so the
/// picker follows the user's Region (DD/MM vs MM/DD) and 12/24-hour preference.
struct ReminderPickerSheet: View {
    let initialDate: Date
    let onSave: (_ date: Date, _ alarm: Bool, _ allDay: Bool, _ recurrence: TimeReminder.Recurrence, _ weekdays: Set<Int>, _ location: LocationTrigger?) -> Void
    /// Optional — the Focus row uses Cancel to REMOVE a just-added reminder; the
    /// editor leaves it nil (Cancel keeps the existing time untouched).
    var onCancel: () -> Void = {}

    @State private var date: Date
    @State private var alarm: Bool
    @State private var allDay: Bool
    @State private var recurrence: TimeReminder.Recurrence
    /// The weekdays a WEEKLY reminder fires on (owner 2026-06-23) — only surfaced/edited
    /// while the cadence is Weekly; cleared otherwise. See `weekdaySection`.
    @State private var weekdays: Set<Int>
    /// The last Quick-set preset chosen, shown in that selector (owner 2026-06-23). Nil
    /// reads as "Select"; picking one jumps `date` to the preset's instant.
    @State private var quickSet: Preset?
    /// The location ("where") for this reminder (owner 2026-06-23) — nil for a time-only
    /// reminder. Edited inline by `LocationEditor` in the Place tab.
    @State private var location: LocationTrigger?
    /// A reminder is EITHER time-based OR location-based (owner 2026-06-24) — the switch
    /// at the top picks which. Seeded to Place when the Take already has a location.
    @State private var mode: ReminderMode
    @Environment(\.dismiss) private var dismiss

    enum ReminderMode: String, CaseIterable, Identifiable {
        case time = "Time", place = "Place"
        var id: String { rawValue }
        /// What the picker shows; the raw value is an identifier only.
        var label: String {
            switch self {
            case .time:  return String(localized: "Time")
            case .place: return String(localized: "Place")
            }
        }
    }

    init(initialDate: Date,
         initialAlarm: Bool = true,
         initialAllDay: Bool = false,
         initialRecurrence: TimeReminder.Recurrence = .none,
         initialWeekdays: Set<Int> = [],
         initialLocation: LocationTrigger? = nil,
         onSave: @escaping (Date, Bool, Bool, TimeReminder.Recurrence, Set<Int>, LocationTrigger?) -> Void,
         onCancel: @escaping () -> Void = {}) {
        self.initialDate = initialDate
        self.onSave = onSave
        self.onCancel = onCancel
        _date = State(initialValue: initialDate)
        _alarm = State(initialValue: initialAlarm)
        _allDay = State(initialValue: initialAllDay)
        _recurrence = State(initialValue: initialRecurrence)
        _weekdays = State(initialValue: initialWeekdays)
        _location = State(initialValue: initialLocation)
        _mode = State(initialValue: initialLocation != nil ? .place : .time)
    }

    /// Quick "when" presets — one tap fills the calendar below. All computed from
    /// `Calendar.current` (no hardcoded formats), evening at 20:00, the rest at the
    /// scheduler's all-day fire hour so an alarm lands at a sensible time of day.
    // `internal` (not `private`) so the pure `date(now:calendar:)` maths — notably
    // the "This weekend includes the weekend you're in" edge — is unit-testable
    // via `@testable import` (2026-07-04). Not referenced outside this file.
    enum Preset: String, CaseIterable, Identifiable {
        case thisEvening = "This evening"
        case tomorrow    = "Tomorrow"
        case thisWeekend = "This weekend"
        case nextWeek    = "Next week"
        var id: String { rawValue }
        /// What the menu shows. The raw value is an identifier only, so a translation
        /// never changes it. Literal per case so the compiler extracts each one.
        var label: String {
            switch self {
            case .thisEvening: return String(localized: "This evening")
            case .tomorrow:    return String(localized: "Tomorrow")
            case .thisWeekend: return String(localized: "This weekend")
            case .nextWeek:    return String(localized: "Next week")
            }
        }

        func date(now: Date, calendar: Calendar) -> Date {
            let morning = ReminderScheduler.allDayFireHour
            switch self {
            case .thisEvening:
                // 20:00 today, or tomorrow evening if it's already past.
                let today8 = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
                return today8 > now ? today8
                    : (calendar.date(byAdding: .day, value: 1, to: today8) ?? today8)
            case .tomorrow:
                let next = calendar.date(byAdding: .day, value: 1, to: now) ?? now
                return calendar.date(bySettingHour: morning, minute: 0, second: 0, of: next) ?? next
            case .thisWeekend:
                // "THIS weekend" includes the one the user is in (2026-07-01):
                // strictly-after matching on a Saturday/Sunday skipped to NEXT
                // Saturday. On a weekend day, use today (at the morning hour if
                // still ahead, else fall through to the strict next Saturday).
                let weekday = calendar.component(.weekday, from: now)
                if weekday == 7 || weekday == 1 {
                    let today = calendar.date(bySettingHour: morning, minute: 0, second: 0, of: now) ?? now
                    if today > now { return today }
                }
                let sat = Self.nextWeekday(7, after: now, calendar: calendar)   // Saturday
                return calendar.date(bySettingHour: morning, minute: 0, second: 0, of: sat) ?? sat
            case .nextWeek:
                let mon = Self.nextWeekday(2, after: now, calendar: calendar)   // Monday
                return calendar.date(bySettingHour: morning, minute: 0, second: 0, of: mon) ?? mon
            }
        }

        /// The next occurrence of `weekday` (1 = Sunday … 7 = Saturday) strictly after
        /// `date`, ignoring the time of day.
        private static func nextWeekday(_ weekday: Int, after date: Date, calendar: Calendar) -> Date {
            var comps = DateComponents()
            comps.weekday = weekday
            return calendar.nextDate(after: date, matching: comps,
                                     matchingPolicy: .nextTime) ?? date
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    modeSwitch                  // Time | Place — either/or
                    if mode == .time {
                        quickSetSection         // 1 — jump the date to a preset
                        timeSection             // 2 — time of day (hidden when all-day)
                        optionsSection          // 3·4·5 — All-day · Notify · Repeat ▸ Interval
                        calendarSection         // 6 — the date
                    } else {
                        LocationEditor(trigger: $location)
                    }
                }
                .padding()
            }
            .scrollIndicators(.hidden)
            // Single-sourced here (owner 2026-06-29) so EVERY presentation path —
            // the in-place editor layer AND the Dailies `.sheet` — gets the app's
            // Ink/Paper background instead of the default system sheet colour.
            .background(Color.ckBackground.ignoresSafeArea())
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Either/or: Place mode saves the location (time cleared downstream); Time
                    // mode saves the time and passes nil location (clearing any prior place).
                    // Weekdays only travel with a WEEKLY cadence — empty otherwise.
                    Button("Done") {
                        onSave(date, alarm, allDay, recurrence,
                               recurrence == .weekly ? weekdays : [],
                               mode == .place ? location : nil)
                        dismiss()
                    }
                    .disabled(mode == .place && location == nil)   // no place chosen yet
                }
            }
        }
        // Open at full height so the controls + as much calendar as fits are visible.
        .presentationDetents([.large])
    }

    // MARK: - Sections

    /// Quick-set, now a Menu selector mirroring the Interval row (owner 2026-06-23):
    /// "Select" by default; choosing a preset jumps `date` to its instant.
    private var quickSetSection: some View {
        Menu {
            Picker("Quick set", selection: $quickSet) {
                ForEach(Preset.allCases) { preset in
                    Text(preset.label).tag(Optional(preset))
                }
            }
        } label: {
            // Shared selector look + 44pt height, matching the Settings pickers
            // (owner 2026-06-29). The card supplies horizontal inset + fill only —
            // SelectorRow owns the height, so it lands at the standard 44pt.
            SelectorRow(icon: "wand.and.stars", label: "Quick set",
                        value: quickSet?.label ?? String(localized: "Select"))
                .padding(.horizontal, 14)
                .flatPanel()
        }
        .tint(Color.ckEmber)
        .accessibilityIdentifier("reminder-quickset")
        .onChange(of: quickSet) { _, preset in
            if let preset { date = preset.date(now: Date(), calendar: .current) }
        }
        // A hand-edited date invalidates the preset LABEL (2026-07-01): the row
        // otherwise kept reading e.g. "Tomorrow" against a date picked weeks out.
        // Guarded so the preset's own date-jump above doesn't immediately clear it.
        .onChange(of: date) { _, newDate in
            if let preset = quickSet,
               newDate != preset.date(now: Date(), calendar: .current) {
                quickSet = nil
            }
        }
    }

    /// Time of day, split out of the calendar into its own row (owner 2026-06-23). Hidden
    /// for an all-day "when" — a date-only placement has no meaningful time.
    @ViewBuilder
    private var timeSection: some View {
        if !allDay {
            DatePicker(selection: $date, displayedComponents: [.hourAndMinute]) {
                Label("Time", systemImage: "clock")
                    .foregroundStyle(Color.ckTextPrimary)
            }
            .accessibilityIdentifier("reminder-time")
            .cardSurface()
        }
    }

    /// The Time | Place switch (owner 2026-06-24): a reminder is either time-based or
    /// location-based, never both. Switching to Time on save clears any place; switching to
    /// Place clears the time — enforced at the commit ("location wins when present").
    private var modeSwitch: some View {
        FlatSegmentedControl(label: String(localized: "Reminder type"),
                             segments: ReminderMode.allCases.map { (value: $0, title: $0.label) },
                             selection: $mode)
            .accessibilityIdentifier("reminder-mode")
    }


    private var optionsSection: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $allDay) {
                Label("All-day", systemImage: "calendar")
            }
            .accessibilityIdentifier("reminder-allday-toggle")

            Divider()

            Toggle(isOn: $alarm) {
                // "Notify" (owner 2026-06-21) — more accurate than "Alarm" to what the
                // toggle does (fire a local notification). The model field stays
                // `alarmEnabled`; only the user-facing label changes.
                Label("Notify", systemImage: alarm ? "bell.fill" : "bell.slash")
            }
            .accessibilityIdentifier("reminder-alarm-toggle")

            Divider()

            // Repeat (owner 2026-06-21): a toggle that REVEALS the cadence chooser when
            // on, mirroring the All-day / Notify row rhythm. Off = a one-shot (`.none`);
            // turning it on defaults to Daily and the revealed menu refines it. The
            // anchor date below supplies the cadence's time-of-day / weekday / day.
            Toggle(isOn: Binding(
                get: { recurrence != .none },
                set: { on in
                    if on {
                        recurrence = (recurrence == .none ? .daily : recurrence)
                    } else {
                        recurrence = .none
                        weekdays = []   // drop any day set so it can't linger for the next cadence
                    }
                }
            )) {
                Label("Repeat", systemImage: "repeat")
            }
            .accessibilityIdentifier("reminder-repeat-toggle")

            if recurrence != .none {
                Divider()
                Menu {
                    // Weekday presets ("Every weekday"/"Every weekend"/"Custom") are surfaced
                    // as first-class interval choices for discoverability (owner 2026-06-30);
                    // `cadenceBinding` maps them to `.weekly` + a weekday set.
                    Picker("Repeat", selection: cadenceBinding) {
                        ForEach(CadenceChoice.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    MenuFieldRow(title: "Interval", icon: "clock", value: cadenceBinding.wrappedValue.label)
                }
                .accessibilityIdentifier("reminder-repeat-cadence")

                // The day strip appears for the day-set weekly cadences (Every weekday / Every
                // weekend / Custom); plain "Weekly" (same weekday each week) shows no strip.
                if recurrence == .weekly && !weekdays.isEmpty {
                    Divider()
                    weekdaySection
                        .padding(.vertical, 6)
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: recurrence != .none)
        .animation(.snappy(duration: 0.2), value: recurrence == .weekly && !weekdays.isEmpty)
        .toggleStyle(FlatToggleStyle())
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .flatPanel()
    }

    /// The seven-day toggle strip for the day-set weekly cadences (owner 2026-06-23; simplified
    /// 2026-06-30 now that Every weekday / Every weekend / Custom are chosen in the Interval
    /// menu). Starts on `firstWeekday` (Sunday or Monday by language); each letter maps
    /// to a Calendar weekday number (1 = Sun … 7 = Sat), so only the display order changes.
    /// Shown only when `weekdays` is non-empty (i.e. not plain "Weekly").
    private var weekdaySection: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols          // index 0 = Sunday
        let fullNames = Calendar.current.weekdaySymbols                 // index 0 = Sunday
        let order = (0..<7).map { (Self.firstWeekday - 1 + $0) % 7 }   // symbol indices, display order
        return HStack(spacing: 6) {
            ForEach(order, id: \.self) { idx in                        // 0 = Sun … 6 = Sat
                let weekday = idx + 1                                   // Calendar weekday number
                let isOn = weekdays.contains(weekday)
                Button {
                    if isOn { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
                } label: {
                    Text(symbols[idx])
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(isOn ? Color.ckAdd : Color.ckBackground, in: CatchlightShape.control)
                        .overlay(CatchlightShape.control.strokeBorder(isOn ? Color.ckAdd : Color.ckOutline, lineWidth: 1))
                        .foregroundStyle(isOn ? Color.ckOnAccent : Color.ckTextPrimary)
                }
                .buttonStyle(.plain)
                // T6 (audit 2026-08): the drawn 38pt rounded square stays, and the hit area
                // grows to the 44pt floor (inset −3). The expansions meet at the
                // midline of the 6pt gutter, so neighbours never overlap.
                .contentShape(Rectangle().inset(by: -3))
                // T6, VO half: a single letter ("S", "T") is ambiguous spoken.
                // The full day name is the label; the letter stays the visual.
                .accessibilityLabel(fullNames[idx])
                .accessibilityIdentifier("reminder-weekday-\(weekday)")
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
    }

    /// The cadence choices shown in the Interval menu (owner 2026-06-30). The weekly family —
    /// Weekly (same weekday each week), Every weekday, Every weekend, Custom — all map to
    /// `.weekly`, differing only by the `weekdays` set; the rest map straight to `Recurrence`.
    private enum CadenceChoice: String, CaseIterable, Identifiable {
        case hourly = "Hourly"
        case daily = "Daily"
        case weekly = "Weekly"
        case everyWeekday = "Every weekday"
        case everyWeekend = "Every weekend"
        case custom = "Custom"
        case monthly = "Monthly"
        case annually = "Annually"
        var id: String { rawValue }
        /// What the menu shows; the raw value is an identifier only.
        var label: String {
            switch self {
            case .hourly:       return String(localized: "Hourly")
            case .daily:        return String(localized: "Daily")
            case .weekly:       return String(localized: "Weekly")
            case .everyWeekday: return String(localized: "Every weekday")
            case .everyWeekend: return String(localized: "Every weekend")
            case .custom:       return String(localized: "Custom")
            case .monthly:      return String(localized: "Monthly")
            case .annually:     return String(localized: "Annually")
            }
        }
    }

    /// Maps `recurrence` + `weekdays` to/from the Interval selection. Reading derives the
    /// weekly-family label from the day set (empty = Weekly, the two presets, else Custom);
    /// writing sets the cadence AND the day set together, seeding Custom with the reminder's
    /// own weekday so its strip opens non-empty.
    private var cadenceBinding: Binding<CadenceChoice> {
        Binding(
            get: {
                switch recurrence {
                case .hourly:   return .hourly
                case .daily:    return .daily
                case .monthly:  return .monthly
                case .annually: return .annually
                case .none:     return .daily   // not shown — the Repeat toggle owns on/off
                case .weekly:
                    if weekdays.isEmpty { return .weekly }
                    if weekdays == TimeReminder.weekdaySet { return .everyWeekday }
                    if weekdays == TimeReminder.weekendSet { return .everyWeekend }
                    return .custom
                }
            },
            set: { choice in
                switch choice {
                case .hourly:       recurrence = .hourly;   weekdays = []
                case .daily:        recurrence = .daily;    weekdays = []
                case .weekly:       recurrence = .weekly;   weekdays = []
                case .everyWeekday: recurrence = .weekly;   weekdays = TimeReminder.weekdaySet
                case .everyWeekend: recurrence = .weekly;   weekdays = TimeReminder.weekendSet
                case .custom:
                    recurrence = .weekly
                    // Seed a single day (the anchor's weekday) unless a bespoke set already exists.
                    if weekdays.isEmpty || weekdays == TimeReminder.weekdaySet || weekdays == TimeReminder.weekendSet {
                        weekdays = [Calendar.current.component(.weekday, from: date)]
                    }
                case .monthly:      recurrence = .monthly;  weekdays = []
                case .annually:     recurrence = .annually; weekdays = []
                }
            }
        )
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The DATE only — time of day is the separate `timeSection` row above (owner
            // 2026-06-23), so this graphical calendar is purely the day. The Sunday-first
            // calendar in the environment makes the grid start on the same day as the
            // weekly day strip (owner 2026-06-23) — display only, the model maths is
            // unaffected.
            DatePicker("When",
                       selection: $date,
                       displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.calendar, Self.pickerCalendar)
                .tint(Color.ckEmber)
        }
    }

    /// The day the reminder sheet's weeks start on, by app language: Sunday in English
    /// (owner 2026-06-23), Monday in German (owner 2026-10-04), Spanish, Italian, Dutch and
    /// French except in Canada, Sunday in Brazilian Portuguese (owner 2026-10-05), Monday
    /// in European Portuguese, Polish, Swedish, Danish, Norwegian, Finnish, Turkish and
    /// Simplified Chinese; Sunday in Japanese, Korean, Traditional Chinese and Thai
    /// (owner 2026-10-06). A new language picks its own here; anything unlisted keeps
    /// Sunday. Calendar weekday numbering (1 = Sunday).
    static var firstWeekday: Int {
        firstWeekday(language: Bundle.main.preferredLocalizations.first,
                     region: Locale.current.region?.identifier)
    }

    static func firstWeekday(language: String?, region: String?) -> Int {
        switch language {
        case "de", "es", "it", "nl", "pt-PT", "pl", "sv", "da", "nb", "fi", "tr", "zh-Hans":
            return 2                                 // Monday
        case "fr": return region == "CA" ? 1 : 2     // Sunday in Canada, else Monday
        default:   return 1                          // Sunday
        }
    }

    /// A copy of the user's calendar pinned to `firstWeekday`, for the graphical calendar,
    /// so it starts on the same day as the weekly day strip. Display only — never used for
    /// scheduling.
    static let pickerCalendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = firstWeekday
        return c
    }()

}

/// The shared rounded-surface "card" wrapper for a single picker row (owner 2026-06-23) —
/// the Quick-set and Time rows match the All-day/Notify/Repeat card's padding, fill, and
/// Ember accent so every row in the sheet reads as one family.
private extension View {
    func cardSurface() -> some View {
        self
            .tint(Color.ckEmber)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .flatPanel()
    }
}

#Preview("Focus row, Night") {
    GeometryReader { geo in
        FocusRowView(
            take: Take(blocks: [.checkItem("Shape me")]),
            cardFrame: CGRect(x: 24, y: geo.size.height / 2 - 36,
                              width: geo.size.width - 44, height: 72),
            containerWidth: geo.size.width,
            onCommit: { _, _, _, _, _, _, _, _, _, _ in },
            onDismiss: {}
        )
    }
    .background(Color.ckBackground)
    .preferredColorScheme(.dark)
}

#Preview("Focus row, Daylight") {
    GeometryReader { geo in
        FocusRowView(
            take: Take(blocks: [.textLine("Shape me")]),
            cardFrame: CGRect(x: 24, y: geo.size.height / 2 - 36,
                              width: geo.size.width - 44, height: 72),
            containerWidth: geo.size.width,
            onCommit: { _, _, _, _, _, _, _, _, _, _ in },
            onDismiss: {}
        )
    }
    .background(Color.ckBackground)
    .preferredColorScheme(.light)
}

/// The veil with a window cut where the edited card stands: the whole area, less the card's
/// own shape, filled even-odd.
private struct VeilWindow: Shape {
    let window: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addPath(CatchlightShape.surface.path(in: window))
        return path
    }
}
