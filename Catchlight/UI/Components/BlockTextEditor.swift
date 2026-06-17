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
        if showsKeyboardGrabber {
            tv.inputAccessoryView = context.coordinator.makeGrabberBar()
        }
        tv.text = text
        applyStyle(to: tv)
        return tv
    }

    func updateUIView(_ tv: BackspaceTextView, context: Context) {
        context.coordinator.parent = self
        if tv.text != text { tv.text = text }
        tv.accessibilityLabel = axLabel
        applyStyle(to: tv)

        // Programmatic focus: become first responder when the editor points
        // `focusedBlockID` at us; resign only when focus is cleared entirely
        // (another row becoming first responder resigns us automatically). The
        // `focusRequested` latch dedupes the async hop so repeated updateUIView
        // passes can't pile up becomeFirstResponder calls (a render loop).
        if focusedBlockID == blockID {
            if !tv.isFirstResponder, !context.coordinator.focusRequested {
                context.coordinator.focusRequested = true
                DispatchQueue.main.async {
                    context.coordinator.focusRequested = false
                    guard !tv.isFirstResponder, tv.window != nil else { return }
                    tv.becomeFirstResponder()
                    let end = tv.endOfDocument
                    tv.selectedTextRange = tv.textRange(from: end, to: end)
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
        tv.textColor = UIColor(isComplete ? Color.ckTextSecondary : Color.ckTextPrimary)
        tv.tintColor = UIColor(Color.ckAccent)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockTextEditor
        /// Latch so a queued becomeFirstResponder isn't scheduled again before it
        /// runs (prevents a focus/render loop).
        var focusRequested = false
        init(_ parent: BlockTextEditor) { self.parent = parent }

        /// A slim bar with a centred grabber, hosted as the keyboard's
        /// `inputAccessoryView`. A tap or a downward swipe dismisses the keyboard by
        /// clearing `focusedBlockID` (which makes the field resign and stay resigned).
        func makeGrabberBar() -> UIView {
            let bar = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 28))
            bar.backgroundColor = .clear
            bar.autoresizingMask = [.flexibleWidth]
            let grab = UIView()
            grab.backgroundColor = UIColor(Color.ckTextSecondary).withAlphaComponent(0.4)
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

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            if parent.focusedBlockID != parent.blockID {
                parent.focusedBlockID = parent.blockID
            }
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
