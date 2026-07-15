import UIKit
import SwiftUI
import CatchlightCore

/// Callbacks the self-scrolling editor raises to its SwiftUI coordinator.
/// Milestone 1 = text edits + focus. Return (list command) / backspace-on-empty
/// / check-toggle land in M2.
protocol BlockEditorViewControllerDelegate: AnyObject {
    /// A block's text changed (user typing). Forward into the draft via `Take.updateText`.
    func blockEditor(_ vc: BlockEditorViewController, didChangeText text: String, forBlock id: UUID)
    /// Focus landed on a block (or `nil` = keyboard released).
    func blockEditor(_ vc: BlockEditorViewController, didFocusBlock id: UUID?)
    /// Return pressed in a CHECK row — a list command (continue / exit), not a newline.
    func blockEditorReturnInCheckRow(_ vc: BlockEditorViewController, blockID id: UUID)
    /// Backspace pressed on an EMPTY row — merge with the previous block / exit checklist.
    func blockEditorBackspaceOnEmpty(_ vc: BlockEditorViewController, blockID id: UUID)
    /// The checkbox was tapped.
    func blockEditorToggleCheck(_ vc: BlockEditorViewController, blockID id: UUID)
    /// A row was dragged to a new position (final block index).
    func blockEditor(_ vc: BlockEditorViewController, didMoveBlock id: UUID, toIndex index: Int)
}

/// Self-scrolling editor: a `UIScrollView` + vertical `UIStackView` of block
/// rows (Milestone 1: prose rows; M2: check rows).
///
/// The KEY property — the SCROLL VIEW scrolls, so keeping the active caret above
/// the keyboard is native: a bottom `contentInset` = keyboard overlap, plus
/// `scrollRectToVisible` on the caret rect. That is exactly the behaviour
/// `DailiesView.pinCaret` reproduced by hand (and re-broke four times) — here it
/// is deterministic because a real `UIScrollView` over a stack of intrinsic-height
/// rows has EXACT geometry (unlike SwiftUI's estimate-height lazy list).
final class BlockEditorViewController: UIViewController, UITextViewDelegate {
    weak var delegate: BlockEditorViewControllerDelegate?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    /// The stack row (a text view, or a checkbox+text HStack) per block id, kept so
    /// `apply` can reconcile INCREMENTALLY — reuse / insert / remove individual rows
    /// rather than rebuild the whole stack, which tore down the focused field and
    /// flicked the keyboard down-and-up whenever a row was added or removed.
    private var rowContainers: [UUID: UIView] = [:]
    private var textViews: [UUID: BackspaceTextView] = [:]
    private var checkButtons: [UUID: UIButton] = [:]
    private var checkRowIDs: Set<UUID> = []
    private var desiredFocus: UUID?
    private var focusInFlight = false
    /// The keyboard toolbar (Important / Angle / Reminder / Done / dismiss), hosted as
    /// the shared `inputAccessoryView` of every row — only the first responder shows it.
    private var toolbarHost: UIHostingController<EditorKeyboardBar>?
    /// Reports intrinsic content height (the stack) so a host can size to content.
    var onContentHeight: ((CGFloat) -> Void)?
    private var lastReportedHeight: CGFloat = -1
    /// The last keyboard END frame (window coords), or nil when hidden. Kept so the bottom
    /// inset can be RE-derived on every layout pass — a bottom-anchored host's view frame is
    /// still settling when the keyboard notification fires, so a one-shot overlap (computed in
    /// `keyboardChanged`) reads the wrong geometry and scrolls the content off-screen. Layout
    /// recompute corrects it once the frame settles (idempotent for fixed-frame hosts).
    private var lastKeyboardEndFrame: CGRect?

    // Drag-to-reorder (check items, via the trailing handle). The dragged row floats
    // over the scroll content while a placeholder holds the gap in the stack.
    private var reorderRowID: [UIPanGestureRecognizer: UUID] = [:]
    private var dragID: UUID?
    private var dragRow: UIView?
    private var dragPlaceholder: UIView?
    private var dragLastY: CGFloat = 0
    /// Breathing room kept below the caret — how far above the keyboard the caret
    /// rests before the content scrolls under it. The toolbar (inputAccessoryView) is
    /// already part of the reported keyboard frame, so this is a SMALL margin ABOVE the
    /// toolbar, not the whole dock-clearance (owner, device 2026-07-13: 72 stacked on
    /// top of the 62pt toolbar double-counted the space). Tunable via the readout.
    private let caretBottomGap: CGFloat = 16

    #if DEBUG
    /// Set by the test harness to surface the scroll maths on device (this is the
    /// device-only zone the sim doesn't reproduce). Removed when M1 is wired into
    /// the real hosts.
    var showsDiagnostics = false { didSet { diagLabel.isHidden = !showsDiagnostics } }
    private lazy var diagLabel: UILabel = {
        let l = UILabel()
        l.numberOfLines = 0
        l.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        l.textColor = .systemRed
        l.backgroundColor = UIColor.white.withAlphaComponent(0.85)
        l.isHidden = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    #endif

    // MARK: - Setup

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        // We manage the bottom inset ourselves from the keyboard frame; letting the
        // scroll view ALSO add safe-area insets stacked a phantom gap at the top and
        // fought the keyboard reservation. Own it fully.
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        let content = scrollView.contentLayoutGuide
        let frame = scrollView.frameLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: frame.widthAnchor),
        ])

        #if DEBUG
        view.addSubview(diagLabel)
        NSLayoutConstraint.activate([
            diagLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            diagLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
        ])
        #endif

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(keyboardChanged(_:)),
                       name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        nc.addObserver(self, selector: #selector(keyboardChanged(_:)),
                       name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        recomputeKeyboardInset()   // re-derive overlap once the (bottom-anchored) frame settles
        let h = stack.frame.height
        if abs(h - lastReportedHeight) > 0.5 { lastReportedHeight = h; onContentHeight?(h) }
        settleScrollWhenContentFits()
    }

    /// When the content fits the visible area, pin it to the TOP and report `true`. A caret-follow
    /// that ran against a momentarily-too-small frame or keyboard inset — before the card's height
    /// / the inset had settled — otherwise strands the content scrolled UP, hiding the top lines and
    /// pushing the caret off the top (device 2026-07-15: "caret appears then scrolls up out of
    /// view"). This can't rely on a later `viewDidLayoutSubviews`: the bottom-anchored card RISES
    /// (a position change) without its bounds changing, so no further layout pass fires — hence the
    /// deferred re-settle in `keyboardChanged`. Returns `false` when the content genuinely overflows
    /// (then the caret-follow governs).
    @discardableResult
    private func settleScrollWhenContentFits(animated: Bool = false) -> Bool {
        let inset = scrollView.adjustedContentInset
        let visibleH = scrollView.bounds.height - inset.top - inset.bottom
        guard scrollView.contentSize.height <= visibleH + 0.5 else { return false }
        let topOffset = -inset.top
        if abs(scrollView.contentOffset.y - topOffset) > 0.5 {
            scrollView.setContentOffset(CGPoint(x: 0, y: topOffset), animated: animated)
        }
        return true
    }

    /// Derive the bottom inset from the last keyboard frame against the CURRENT view geometry.
    /// Called both on the keyboard notification and on every layout pass, so a host whose frame
    /// settles AFTER the notification (bottom-anchored new-Take) ends up with the right overlap.
    /// Guarded so it only writes on a real change — no layout feedback loop.
    private func recomputeKeyboardInset() {
        let overlap: CGFloat
        if let end = lastKeyboardEndFrame {
            let kbInView = view.convert(end, from: nil)
            overlap = max(0, scrollView.frame.maxY - kbInView.minY)
        } else {
            overlap = 0
        }
        guard abs(scrollView.contentInset.bottom - overlap) > 0.5 else { return }
        scrollView.contentInset.bottom = overlap
        scrollView.verticalScrollIndicatorInsets.bottom = overlap
        // The inset just changed (e.g. a bottom-anchored card finished rising) — re-settle the
        // caret against the corrected geometry so content over-scrolled under a stale inset
        // springs back into view instead of staying hidden.
        scrollActiveCaretToVisible(animated: false)
    }

    // MARK: - Data

    /// Reconcile the block list into the stack INCREMENTALLY: reuse existing rows,
    /// insert only new ones, rewrap kind changes (keeping the same text view), and
    /// remove only vanished ones. Focus moves to the target BEFORE the old row is
    /// removed — both deferred together — so adding/removing a row transfers the
    /// keyboard between live fields instead of flicking it down and up.
    func apply(blocks: [TakeBlock], focusedBlockID: UUID?) {
        guard dragID == nil else { return }   // never reconcile mid-drag (row is floating)
        for block in blocks {
            if textViews[block.id] == nil {
                createRow(block)
            } else if checkRowIDs.contains(block.id) != block.isCheck {
                rewrapRow(block)                       // text <-> check, same text view
            } else if let tv = textViews[block.id], !tv.isFirstResponder, tv.text != block.text {
                tv.text = block.text
            }
        }
        // Order the stack to match the block order.
        for (index, block) in blocks.enumerated() {
            if let row = rowContainers[block.id] { stack.insertArrangedSubview(row, at: index) }
        }
        updateCheckVisuals(blocks)

        desiredFocus = focusedBlockID
        let liveIDs = Set(blocks.map(\.id))
        // Defer focus + removal together, out of the SwiftUI update cycle: focus the
        // target first, THEN drop any vanished row — so the keyboard is never yanked
        // off a focused field that's about to be removed.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyFocusNow()
            for id in Array(self.rowContainers.keys) where !liveIDs.contains(id) {
                self.removeRow(id)
            }
        }
    }

    private func createRow(_ block: TakeBlock) {
        let tv = makeTextView(id: block.id, text: block.text, isComplete: isComplete(block))
        textViews[block.id] = tv
        // Every row is an HStack that ALWAYS holds the text view; a check row just adds
        // the checkbox + handle around it. Keeping the tv permanently inside its HStack
        // means a check<->text conversion only adds/removes chrome — the tv never changes
        // superview, so it never resigns first responder and the keyboard never flicks
        // (owner device report 2026-07-13).
        let row = UIStackView(arrangedSubviews: [tv])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        rowContainers[block.id] = row
        if block.isCheck {
            checkRowIDs.insert(block.id)
            addCheckChrome(to: row, id: block.id)
        }
        stack.addArrangedSubview(row)
    }

    private func removeRow(_ id: UUID) {
        if let row = rowContainers[id] {
            stack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        rowContainers[id] = nil
        textViews[id] = nil
        checkButtons[id] = nil
        checkRowIDs.remove(id)
        reorderRowID = reorderRowID.filter { $0.value != id }
    }

    /// Kind change (text <-> check) reusing the SAME row + text view — only the chrome
    /// (checkbox + handle) is added or removed. The tv never leaves the window, so it
    /// keeps first responder and the keyboard stays put.
    private func rewrapRow(_ block: TakeBlock) {
        guard let row = rowContainers[block.id] as? UIStackView else { return }
        if block.isCheck {
            checkRowIDs.insert(block.id)
            addCheckChrome(to: row, id: block.id)
        } else {
            checkRowIDs.remove(block.id)
            removeCheckChrome(from: row, id: block.id)
        }
    }

    private func isComplete(_ block: TakeBlock) -> Bool {
        if case .check(let item) = block { return item.isComplete }
        return false
    }

    /// Matches the current `BlockTextEditor` styling exactly (D-042 DM Sans). A
    /// `BackspaceTextView` so an empty-backspace merges with the block above.
    private func makeTextView(id: UUID, text: String, isComplete: Bool) -> BackspaceTextView {
        let tv = BackspaceTextView()
        tv.countsTrailingLine = true   // grow the row for a trailing-newline's empty last line
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.font = CatchlightFont.uiBody(size: 14)
        tv.textColor = UIColor(isComplete ? Color.ckTextComplete : Color.ckTextPrimary)
        tv.tintColor = UIColor(Color.ckAccent)
        tv.delegate = self
        tv.text = text
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        tv.onBackspaceEmpty = { [weak self] in
            guard let self else { return }
            self.delegate?.blockEditorBackspaceOnEmpty(self, blockID: id)
        }
        tv.inputAccessoryView = toolbarHost?.view
        return tv
    }

    /// Install / refresh the keyboard toolbar from the current draft-derived config.
    /// Called before `apply` on every SwiftUI update, so the bar reflects live state
    /// (Important tint, Angle enablement, Done). The reported keyboard frame includes
    /// this accessory, so the caret-follow already rests the caret above the toolbar.
    func setToolbar(_ config: BlockTextEditor.EditorToolbarConfig) {
        let bar = EditorKeyboardBar(config: config, onDismiss: { [weak self] in
            self?.view.endEditing(true)
            config.onDismiss()
        })
        if let host = toolbarHost {
            host.rootView = bar
        } else {
            let host = UIHostingController(rootView: bar)
            host.view.backgroundColor = .clear
            host.view.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 62)
            host.view.autoresizingMask = [.flexibleWidth]
            addChild(host)
            host.didMove(toParent: self)
            toolbarHost = host
            for tv in textViews.values {
                tv.inputAccessoryView = host.view
                if tv.isFirstResponder { tv.reloadInputViews() }
            }
        }
    }

    /// Add the check chrome (leading checkbox + trailing drag handle) around the row's
    /// existing text view, without touching the text view itself.
    private func addCheckChrome(to row: UIStackView, id: UUID) {
        let button = UIButton(type: .system)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.accessibilityIdentifier = "uikit-check-box"
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.blockEditorToggleCheck(self, blockID: id)
        }, for: .touchUpInside)
        checkButtons[id] = button

        let handle = UIImageView(image: UIImage(systemName: "line.3.horizontal",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)))
        handle.tintColor = UIColor(Color.ckTextSecondary).withAlphaComponent(0.55)
        handle.contentMode = .center
        handle.isUserInteractionEnabled = true
        handle.setContentHuggingPriority(.required, for: .horizontal)
        handle.accessibilityIdentifier = "uikit-reorder-handle"
        let pan = UIPanGestureRecognizer(target: self, action: #selector(reorderPan(_:)))
        handle.addGestureRecognizer(pan)
        reorderRowID[pan] = id

        row.insertArrangedSubview(button, at: 0)   // leading
        row.addArrangedSubview(handle)             // trailing
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
            handle.widthAnchor.constraint(equalToConstant: 36),
        ])
    }

    /// Remove the check chrome, leaving just the text view in the row.
    private func removeCheckChrome(from row: UIStackView, id: UUID) {
        for v in row.arrangedSubviews where v !== textViews[id] {
            row.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        checkButtons[id] = nil
        reorderRowID = reorderRowID.filter { $0.value != id }
    }

    // MARK: - Drag-to-reorder

    @objc private func reorderPan(_ g: UIPanGestureRecognizer) {
        guard let id = reorderRowID[g], let row = rowContainers[id] else { return }
        switch g.state {
        case .began:   beginDrag(id: id, row: row, gesture: g)
        case .changed: updateDrag(g)
        default:       endDrag()
        }
    }

    /// Lift the row out of the stack to float over the content, leaving a placeholder
    /// of equal height to hold the gap.
    private func beginDrag(id: UUID, row: UIView, gesture: UIPanGestureRecognizer) {
        guard let index = stack.arrangedSubviews.firstIndex(of: row) else { return }
        scrollView.isScrollEnabled = false
        let frame = row.frame
        let placeholder = UIView()
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.heightAnchor.constraint(equalToConstant: frame.height).isActive = true
        stack.insertArrangedSubview(placeholder, at: index)
        stack.removeArrangedSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = true
        scrollView.addSubview(row)
        row.frame = frame
        // Just a subtle scale on lift — owner prefers this to a surface+shadow chip
        // (device 2026-07-13).
        UIView.animate(withDuration: 0.15) { row.transform = CGAffineTransform(scaleX: 1.02, y: 1.02) }
        dragID = id; dragRow = row; dragPlaceholder = placeholder
        dragLastY = gesture.location(in: scrollView).y
    }

    /// Follow the finger and slide the placeholder to the slot under the row's centre.
    private func updateDrag(_ gesture: UIPanGestureRecognizer) {
        guard let row = dragRow, let placeholder = dragPlaceholder else { return }
        let y = gesture.location(in: scrollView).y
        row.frame.origin.y += (y - dragLastY)
        dragLastY = y
        let centerY = row.frame.midY
        let others = stack.arrangedSubviews.filter { $0 !== placeholder }
        let target = min(others.prefix { $0.frame.midY < centerY }.count, others.count)
        if stack.arrangedSubviews.firstIndex(of: placeholder) != target {
            UIView.animate(withDuration: 0.16) {
                self.stack.insertArrangedSubview(placeholder, at: target)
                self.stack.layoutIfNeeded()
            }
        }
    }

    /// Drop the row into the placeholder's slot and commit the new order to the model.
    private func endDrag() {
        guard let id = dragID, let row = dragRow, let placeholder = dragPlaceholder else { return }
        dragID = nil; dragRow = nil; dragPlaceholder = nil
        scrollView.isScrollEnabled = true
        let finalIndex = stack.arrangedSubviews.firstIndex(of: placeholder) ?? 0
        row.removeFromSuperview()
        row.transform = .identity
        row.translatesAutoresizingMaskIntoConstraints = false
        stack.insertArrangedSubview(row, at: finalIndex)
        stack.removeArrangedSubview(placeholder)
        placeholder.removeFromSuperview()
        UIView.animate(withDuration: 0.15) { self.stack.layoutIfNeeded() }
        delegate?.blockEditor(self, didMoveBlock: id, toIndex: finalIndex)
    }

    private func checkboxImage(isComplete: Bool) -> UIImage? {
        let cfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        return UIImage(systemName: isComplete ? "checkmark.circle.fill" : "square",
                       withConfiguration: cfg)
    }

    /// Update checkbox glyphs + completed-item dimming IN PLACE (no rebuild), so a
    /// toggle never tears down the row being edited and drops the keyboard.
    private func updateCheckVisuals(_ blocks: [TakeBlock]) {
        for block in blocks where block.isCheck {
            let done = isComplete(block)
            if let b = checkButtons[block.id] {
                b.setImage(checkboxImage(isComplete: done), for: .normal)
                b.tintColor = UIColor(done ? Color.ckAccent : Color.ckTextSecondary)
            }
            if let tv = textViews[block.id], !tv.isFirstResponder {
                tv.textColor = UIColor(done ? Color.ckTextComplete : Color.ckTextPrimary)
            }
        }
    }

    private func blockID(for tv: UITextView) -> UUID? {
        textViews.first(where: { $0.value === tv })?.key
    }

    private func activeTextView() -> UITextView? {
        textViews.values.first(where: { $0.isFirstResponder })
    }

    // MARK: - Focus

    /// Move focus to `desiredFocus`. Called from the deferred block in `apply`, so a
    /// same-window sibling can take focus synchronously (transferring the keyboard with
    /// no flicker). Falls back to the retry loop only when the target isn't in a window
    /// yet (a freshly opened Take on a cold launch).
    private func applyFocusNow() {
        guard let id = desiredFocus, let tv = textViews[id], !tv.isFirstResponder else { return }
        if tv.window != nil, tv.becomeFirstResponder() {
            let end = tv.endOfDocument
            tv.selectedTextRange = tv.textRange(from: end, to: end)
            scrollActiveCaretToVisible(animated: false)
        } else if !focusInFlight {
            focusInFlight = true
            requestFocus(tv, attemptsLeft: 8)
        }
    }

    /// Retry become-first-responder until the field is in a window (mirrors the
    /// old editor: a freshly built row may not be realised on the first pass).
    private func requestFocus(_ tv: UITextView, attemptsLeft: Int) {
        DispatchQueue.main.async { [weak self, weak tv] in
            guard let self, let tv else { return }
            if tv.window != nil, tv.becomeFirstResponder() {
                let end = tv.endOfDocument
                tv.selectedTextRange = tv.textRange(from: end, to: end)
                self.focusInFlight = false
                self.scrollActiveCaretToVisible(animated: false)
                return
            }
            guard attemptsLeft > 0 else { self.focusInFlight = false; return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.requestFocus(tv, attemptsLeft: attemptsLeft - 1)
            }
        }
    }

    // MARK: - Keyboard + caret follow (the native replacement for pinCaret)

    @objc private func keyboardChanged(_ note: Notification) {
        guard let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        else { return }
        let hiding = note.name == UIResponder.keyboardWillHideNotification
        lastKeyboardEndFrame = hiding ? nil : end
        recomputeKeyboardInset()
        scrollActiveCaretToVisible(animated: true)
        // The bottom-anchored card is still RISING into place (a SwiftUI position animation that
        // fires no further layout pass here), so the geometry `recomputeKeyboardInset` just used
        // is stale. Re-derive the inset + re-settle once the animation has completed, against the
        // FINAL geometry — this is what deterministically clears the "caret scrolled up" race that
        // only the diagnostics label's extra layout pass was accidentally fixing.
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) { [weak self] in
            guard let self else { return }
            self.recomputeKeyboardInset()
            self.scrollActiveCaretToVisible(animated: false)
        }
    }

    /// Scroll the active caret into the visible area. `scrollRectToVisible`
    /// respects `adjustedContentInset` (which includes the keyboard overlap), so
    /// the caret is held above the keyboard — natively, against exact geometry.
    private func scrollActiveCaretToVisible(animated: Bool) {
        // Content fits → pin to the top; never follow the caret (following it against a
        // not-yet-settled frame/inset is exactly what strands the top off-screen).
        if settleScrollWhenContentFits(animated: animated) {
            #if DEBUG
            updateDiag(nil)
            #endif
            return
        }
        guard let tv = activeTextView(), let sel = tv.selectedTextRange else {
            #if DEBUG
            updateDiag(nil)
            #endif
            return
        }
        let caret = tv.caretRect(for: sel.end)
        guard caret.origin.y.isFinite, caret.size.height.isFinite else { return }
        let inScroll = scrollView.convert(caret, from: tv)
        scrollView.scrollRectToVisible(inScroll.insetBy(dx: 0, dy: -caretBottomGap), animated: animated)
        #if DEBUG
        updateDiag(inScroll)
        #endif
    }

    #if DEBUG
    private func updateDiag(_ caretInScroll: CGRect?) {
        guard showsDiagnostics else { return }
        diagLabel.text = String(format: "fH=%.0f  ins.b=%.0f  off=%.0f\ncs=%.0f  caretY=%@",
                                scrollView.frame.height, scrollView.adjustedContentInset.bottom,
                                scrollView.contentOffset.y, scrollView.contentSize.height,
                                caretInScroll.map { String(format: "%.0f", $0.maxY) } ?? "-")
        view.bringSubviewToFront(diagLabel)
    }
    #endif

    // MARK: - UITextViewDelegate

    func textViewDidBeginEditing(_ tv: UITextView) {
        guard let id = blockID(for: tv) else { return }
        delegate?.blockEditor(self, didFocusBlock: id)
        scrollActiveCaretToVisible(animated: true)
    }

    func textViewDidChange(_ tv: UITextView) {
        guard let id = blockID(for: tv) else { return }
        delegate?.blockEditor(self, didChangeText: tv.text, forBlock: id)
        // The row's intrinsic height changed (incl. a trailing newline's empty line) — re-measure,
        // settle layout, then keep the caret up.
        tv.invalidateIntrinsicContentSize()
        view.layoutIfNeeded()
        scrollActiveCaretToVisible(animated: false)
    }

    func textViewDidChangeSelection(_ tv: UITextView) {
        scrollActiveCaretToVisible(animated: false)
    }

    /// CHECK rows: a Return is a list command (continue / exit), never a newline.
    /// Text rows fall through and take a literal newline within the same block.
    func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange,
                  replacementText text: String) -> Bool {
        if text == "\n", let id = blockID(for: tv), checkRowIDs.contains(id) {
            delegate?.blockEditorReturnInCheckRow(self, blockID: id)
            return false
        }
        return true
    }
}
