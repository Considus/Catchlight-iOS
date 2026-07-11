//
//  BlockTextEditor.swift
//  Catchlight (iOS app target) — Phase 2 block editor (D-035)
//
//  One editable row of the block-stack editor, backed by UITextView because
//  SwiftUI's TextField/TextEditor cannot intercept Return / Backspace per-row
//  nor move keyboard focus between sibling rows the way Apple Notes does. This
//  representable gives the editor three hooks SwiftUI can't:
//
//    • onReturn         — for CHECK rows, Return is intercepted (no newline is
//                         inserted) so the editor can continue / exit the list.
//                         For TEXT rows, Return is a normal newline.
//    • onBackspaceEmpty — Backspace pressed while the field is empty (exit a
//                         check item / backspace-merge with the block above).
//    • focusedBlockID   — a shared binding the editor drives to move the keyboard
//                         caret between rows (become/resign first responder).
//
//  Focus and cursor management across rows is the fiddly part and only fully
//  exercises on a device; the simulator does not reproduce all keyboard timing.
//

import SwiftUI

struct BlockTextEditor: UIViewRepresentable {
    /// Stable id of the block this row edits (the focus key).
    let blockID: UUID
    @Binding var text: String
    /// Which block should hold the keyboard. When it equals `blockID` this row
    /// becomes first responder; the editor sets it to move focus.
    @Binding var focusedBlockID: UUID?
    /// CHECK rows intercept Return; TEXT rows take it as a newline.
    let isCheck: Bool
    /// Completed check items read in the muted secondary colour.
    let isComplete: Bool
    let axIdentifier: String
    let axLabel: String
    /// Return pressed in a check row. The editor decides continue-vs-exit.
    var onReturn: () -> Void = {}
    /// Backspace pressed while the field is empty.
    var onBackspaceEmpty: () -> Void = {}
    /// Show a grabber bar on top of the keyboard whose tap / downward-swipe dismisses
    /// the keyboard (owner 2026-06-17 — a discoverable "swipe the keyboard out of the
    /// way" affordance; dismissing then leaves the dimmed timeline tappable to save &
    /// close). Dismiss = clearing `focusedBlockID`, so the field resigns and won't be
    /// re-focused. Only the in-place editor sets this.
    var showsKeyboardGrabber: Bool = false

    /// When set, the keyboard shows the editing TOOLBAR (dismiss · Important · Angle ·
    /// Done) as its `inputAccessoryView` instead of the plain grabber (owner
    /// 2026-06-18; Search → Done 2026-06-19 — Search did nothing useful while inside
    /// one Take). The down-arrow takes over the grabber's dismiss role.
    var toolbar: EditorToolbarConfig? = nil

    /// Reports the caret's rect in WINDOW coordinates whenever it moves (typing,
    /// Return, selection). The host uses it to keep the caret above the keyboard as a
    /// growing TEXT block pushes it down — pressing Return adds a newline to the SAME
    /// block, so no block-change scroll fires and SwiftUI's own avoidance never
    /// follows the caret (owner device report 2026-06-19, the "caret disappears on
    /// Return" bug).
    var onCaretMoved: ((CGRect) -> Void)? = nil

    /// The editing toolbar's state + actions — the Take-level context a per-block
    /// editor doesn't otherwise hold. Dismiss is handled internally (clears focus).
    struct EditorToolbarConfig {
        var isImportant: Bool
        /// The Angle (shopping-bag) button is enabled only when an Angle applies
        /// (a checklist Take); greyed out otherwise.
        var angleEnabled: Bool
        /// Whether the Take currently reads as done (drives the Done button's
        /// filled/active look).
        var isDone: Bool
        /// The Done (tick) button is enabled only for a task or reminder Take —
        /// a pure note can't be "done"; greyed otherwise.
        var doneEnabled: Bool
        /// Whether the Take already carries a reminder — drives the reminder button's
        /// "Edit reminder" vs "Add reminder" affordance (owner 2026-06-21).
        var hasReminder: Bool = false
        var onToggleImportant: () -> Void
        var onOpenAngle: () -> Void
        /// Open the reminder picker for THIS Take (owner 2026-06-21). When supplied,
        /// slot 2 becomes a Reminder button wherever the Angle would be greyed (a note or
        /// reminder-only Take) — editing the time/cadence in place, no Focus-ring detour.
        /// nil where the host can't present the picker (e.g. Storyboard), leaving the
        /// previous greyed-Angle behaviour.
        var onReminder: (() -> Void)? = nil
        /// Mark the whole Take done / not-done (all checklist items + the reminder).
        var onToggleDone: () -> Void
        /// The keyboard ⌄/× — commit the edit and EXIT (owner 2026-06-19): the host
        /// saves and drops the focused-edit overlay in one step, back to the timeline
        /// (or Storyboard), rather than just lowering the keyboard onto a still-focused
        /// Take. Default no-op (the keyboard still resigns).
        var onDismiss: () -> Void = {}
    }

    func makeUIView(context: Context) -> BackspaceTextView {
        let tv = BackspaceTextView()
        tv.delegate = context.coordinator
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.font = CatchlightFont.uiBody(size: 14)   // DM Sans (.tt) — D-042; was Cormorant uiDisplay 19
        tv.returnKeyType = .default
        tv.keyboardType = .default
        tv.autocorrectionType = .default
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        tv.accessibilityIdentifier = axIdentifier
        tv.accessibilityLabel = axLabel
        tv.onBackspaceEmpty = { [weak tv] in
            guard tv != nil else { return }
            context.coordinator.parent.onBackspaceEmpty()
        }
        if toolbar != nil {
            tv.inputAccessoryView = context.coordinator.makeEditingToolbar()
        } else if showsKeyboardGrabber {
            tv.inputAccessoryView = context.coordinator.makeGrabberBar()
        }
        tv.text = text
        applyStyle(to: tv)
        context.coordinator.observeKeyboardForCaret(tv)
        return tv
    }

    func updateUIView(_ tv: BackspaceTextView, context: Context) {
        context.coordinator.parent = self
        if tv.text != text { tv.text = text }
        tv.accessibilityLabel = axLabel
        applyStyle(to: tv)
        if toolbar != nil { context.coordinator.refreshToolbar() }

        // Programmatic focus: become first responder when the editor points
        // `focusedBlockID` at us; resign only when focus is cleared entirely
        // (another row becoming first responder resigns us automatically). The
        // `focusRequested` latch dedupes so repeated updateUIView passes can't pile up
        // parallel retry chains (a render loop).
        //
        // A NEW Take is created off-screen / blooming, so the row often isn't in the
        // window yet on the first pass — a single becomeFirstResponder attempt then
        // silently fails and never retries, so the Take opens with no caret/keyboard
        // (worst on a cold launch, fine on warm runs → the "inconsistent" report).
        // `requestFocus` RETRIES on a short timer until the view is in the window and
        // focus takes, so it's deterministic regardless of launch/scroll timing.
        if focusedBlockID == blockID {
            if !tv.isFirstResponder, !context.coordinator.focusRequested {
                context.coordinator.focusRequested = true
                // Defer out of the view-update cycle (becomeFirstResponder mid-update
                // is unsafe), then retry on a timer until it takes.
                DispatchQueue.main.async {
                    context.coordinator.requestFocus(tv, attemptsLeft: 16)
                }
            }
        } else if focusedBlockID == nil, tv.isFirstResponder {
            DispatchQueue.main.async { tv.resignFirstResponder() }
        }
    }

    /// Report a concrete height for the proposed width. Without this, a non
    /// scrolling UITextView inside a plain VStack/ScrollView can resolve to ~0
    /// height on some runtimes (notably iOS 17) — collapsing the row so it isn't
    /// laid out or hittable. (A List sized it for us; a VStack does not.)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BackspaceTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fitted.height, 34))
    }

    private func applyStyle(to tv: BackspaceTextView) {
        // Completed check items recede via the shared `ckTextComplete` (owner 2026-06-18
        // — was `ckTextSecondary`, so the editor didn't match the Angle / timeline).
        tv.textColor = UIColor(isComplete ? Color.ckTextComplete : Color.ckTextPrimary)
        tv.tintColor = UIColor(Color.ckAccent)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockTextEditor
        /// Latch so a queued becomeFirstResponder isn't scheduled again before it
        /// runs (prevents a focus/render loop).
        var focusRequested = false
        private weak var observedTextView: BackspaceTextView?
        private var keyboardShowObserver: NSObjectProtocol?
        init(_ parent: BlockTextEditor) { self.parent = parent }
        deinit {
            if let keyboardShowObserver { NotificationCenter.default.removeObserver(keyboardShowObserver) }
        }

        /// Re-report the caret once the keyboard has FULLY shown. The host pins the
        /// caret above the keyboard, but on ENTRY there's no keystroke to trigger a
        /// report and the keyboard's frame isn't known until it's up — so a freshly
        /// opened Take could sit with its card tucked under the dock until the first
        /// keypress jolted the pin awake (owner device report 2026-06-19). Firing on
        /// keyboardDidShow positions it correctly on appear. Only the focused row's
        /// observer passes the guard, so the others are no-ops.
        func observeKeyboardForCaret(_ tv: BackspaceTextView) {
            observedTextView = tv
            guard keyboardShowObserver == nil else { return }
            keyboardShowObserver = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, let tv = self.observedTextView, tv.isFirstResponder else { return }
                self.reportCaret(tv)
            }
        }

        /// Retry becomeFirstResponder until the view is actually in a window and focus
        /// takes (or we run out of attempts) — a new Take's row may not be realised /
        /// on-screen on the first pass, and a single attempt loses the keyboard. Each
        /// attempt is ~50ms apart; bails early if focus drifted elsewhere or already
        /// landed. Clears `focusRequested` when it finishes so a later focus can re-arm.
        func requestFocus(_ tv: BackspaceTextView, attemptsLeft: Int) {
            // Focus moved away (or already there) — stop, don't steal it back.
            guard parent.focusedBlockID == parent.blockID, !tv.isFirstResponder else {
                focusRequested = false
                return
            }
            if tv.window != nil, tv.becomeFirstResponder() {
                let end = tv.endOfDocument
                tv.selectedTextRange = tv.textRange(from: end, to: end)
                focusRequested = false
                return
            }
            guard attemptsLeft > 0 else { focusRequested = false; return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak tv] in
                guard let self, let tv else { return }
                self.requestFocus(tv, attemptsLeft: attemptsLeft - 1)
            }
        }

        /// A slim bar with a centred grabber, hosted as the keyboard's
        /// `inputAccessoryView`. A tap or a downward swipe dismisses the keyboard by
        /// clearing `focusedBlockID` (which makes the field resign and stay resigned).
        func makeGrabberBar() -> UIView {
            let bar = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 28))
            bar.backgroundColor = .clear
            bar.autoresizingMask = [.flexibleWidth]
            let grab = UIView()
            // Dynamic so it re-resolves on a Night/Daylight change (a plain
            // `.withAlphaComponent` on a dynamic colour would flatten it). Single
            // source: `UITheme.textSecondary` (= `ckTextSecondary`).
            grab.backgroundColor = UIColor { UITheme.textSecondary.resolvedColor(with: $0).withAlphaComponent(0.4) }
            grab.layer.cornerRadius = 2.5
            grab.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(grab)
            NSLayoutConstraint.activate([
                grab.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
                grab.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
                grab.widthAnchor.constraint(equalToConstant: 40),
                grab.heightAnchor.constraint(equalToConstant: 5),
            ])
            bar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard)))
            bar.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(grabberPanned(_:))))
            return bar
        }

        @objc func grabberPanned(_ g: UIPanGestureRecognizer) {
            // Only a downward swipe dismisses (mirrors "pull the keyboard down").
            guard g.state == .ended, g.translation(in: g.view).y > 8 else { return }
            dismissKeyboard()
        }

        @objc func dismissKeyboard() { parent.focusedBlockID = nil }

        // MARK: - Editing toolbar (inputAccessoryView)

        /// Hosts the SwiftUI `EditorKeyboardBar` so the toolbar matches the dock's
        /// styling (Ember-ringed buttons + faded background) rather than a plain UIKit
        /// toolbar (owner 2026-06-19). Retained here for the keyboard's lifetime.
        var toolbarHost: UIHostingController<EditorKeyboardBar>?

        /// Build the dock-styled bar as the keyboard's `inputAccessoryView`. Height =
        /// 44pt circle + 10/8 padding.
        func makeEditingToolbar() -> UIView {
            let host = UIHostingController(rootView: editorBar())
            host.view.backgroundColor = .clear
            host.view.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 62)
            host.view.autoresizingMask = [.flexibleWidth]
            toolbarHost = host
            return host.view
        }

        /// Re-render the bar from the live config (Important tint, Angle enablement).
        func refreshToolbar() {
            toolbarHost?.rootView = editorBar()
        }

        private func editorBar() -> EditorKeyboardBar {
            EditorKeyboardBar(
                config: parent.toolbar ?? .init(isImportant: false, angleEnabled: false,
                                                isDone: false, doneEnabled: false,
                                                onToggleImportant: {}, onOpenAngle: {}, onToggleDone: {}),
                onDismiss: { [weak self] in
                    // Lower the keyboard AND commit-and-exit the edit (owner
                    // 2026-06-19) — one step back to the timeline / Storyboard, not a
                    // keyboard-down-but-still-focused intermediate.
                    self?.dismissKeyboard()
                    self?.parent.toolbar?.onDismiss()
                }
            )
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            reportCaret(tv)
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            reportCaret(tv)
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            if parent.focusedBlockID != parent.blockID {
                parent.focusedBlockID = parent.blockID
            }
            // Report the caret the moment focus lands on this block, so the caret pin
            // follows a block→block move (owner 2026-07-11). Adding a checklist item /
            // pressing Return moves focus to a NEW block whose selection is set
            // programmatically — which fires neither `textViewDidChange` (check-row Return
            // returns false, inserting no text) nor `textViewDidChangeSelection` — and the
            // keyboard is already up, so `keyboardDidShow` never re-fires. Without this the
            // pin stayed on the previous block and the caret marched below the keyboard.
            reportCaret(tv)
        }

        /// Caret rect in WINDOW coordinates → host (see `onCaretMoved`). Guards the
        /// not-yet-in-window / non-finite rects UIKit hands back mid-setup. The
        /// textview's top in the window stays put as a block grows downward, so the
        /// caret's window Y is accurate even before SwiftUI re-lays-out the taller row.
        private func reportCaret(_ tv: UITextView) {
            guard let report = parent.onCaretMoved, tv.window != nil,
                  let sel = tv.selectedTextRange else { return }
            let caret = tv.caretRect(for: sel.end)
            guard caret.origin.y.isFinite, caret.size.height.isFinite else { return }
            report(tv.convert(caret, to: nil))
        }

        func textView(_ tv: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            // CHECK rows: a single Return is a list command, never a newline.
            if parent.isCheck, text == "\n" {
                parent.onReturn()
                return false
            }
            return true
        }
    }
}

/// UITextView that reports a Backspace pressed while empty — the signal the
/// editor uses to exit a check item / merge with the block above. UIKit gives
/// no delegate callback for "delete on empty", so we override `deleteBackward`.
final class BackspaceTextView: UITextView {
    var onBackspaceEmpty: (() -> Void)?

    override func deleteBackward() {
        if text.isEmpty {
            onBackspaceEmpty?()
            return
        }
        super.deleteBackward()
    }
}
