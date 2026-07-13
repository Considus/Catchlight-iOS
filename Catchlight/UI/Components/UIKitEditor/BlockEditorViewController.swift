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

    /// Structure signature (block id + kind) so `apply` rebuilds on a structural
    /// change but only syncs text otherwise. `isComplete` is deliberately NOT in the
    /// signature — toggling a checkbox updates visuals in place and never rebuilds, so
    /// a tap can't drop the keyboard from the row being edited.
    private var blockSig: [String] = []
    private var textViews: [UUID: BackspaceTextView] = [:]
    private var checkButtons: [UUID: UIButton] = [:]
    private var checkRowIDs: Set<UUID> = []
    private var desiredFocus: UUID?
    private var focusInFlight = false
    /// Breathing room kept below the caret — how far above the keyboard the caret
    /// rests before the content scrolls under it. 72 matches the old editor's tuned
    /// `caretPinGap` and leaves room for the dock toolbar (owner, device 2026-07-13:
    /// measured 69pt as the target via the on-device readout). In the real editor the
    /// dock is part of the reported keyboard frame, so this gap sits above the dock.
    private let caretBottomGap: CGFloat = 72

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

    // MARK: - Data

    /// Diff the block list into the stack (reuse text views by id) and apply focus.
    func apply(blocks: [TakeBlock], focusedBlockID: UUID?) {
        let sig = blocks.map { "\($0.id.uuidString):\($0.isCheck)" }
        if sig != blockSig {
            rebuild(blocks: blocks)
            blockSig = sig
        } else {
            // Same structure — sync text into any field NOT currently being typed
            // in (typing the active field must never be stomped by the echo back).
            for block in blocks {
                guard let tv = textViews[block.id] else { continue }
                if !tv.isFirstResponder, tv.text != block.text { tv.text = block.text }
            }
        }
        updateCheckVisuals(blocks)
        desiredFocus = focusedBlockID
        applyFocus()
    }

    private func rebuild(blocks: [TakeBlock]) {
        for v in stack.arrangedSubviews {
            stack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        textViews.removeAll()
        checkButtons.removeAll()
        checkRowIDs.removeAll()
        for block in blocks {
            let tv = makeTextView(id: block.id, text: block.text, isComplete: isComplete(block))
            textViews[block.id] = tv
            switch block {
            case .text:
                stack.addArrangedSubview(tv)
            case .check:
                checkRowIDs.insert(block.id)
                stack.addArrangedSubview(makeCheckRow(id: block.id, textView: tv))
            }
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
        return tv
    }

    /// A check row: checkbox (44pt touch target) + the item's text view. Matches
    /// the current editor's centre-aligned layout. Drag-to-reorder arrives in M4.
    private func makeCheckRow(id: UUID, textView: UITextView) -> UIView {
        let button = UIButton(type: .system)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.accessibilityIdentifier = "uikit-check-box"
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.blockEditorToggleCheck(self, blockID: id)
        }, for: .touchUpInside)
        checkButtons[id] = button

        let row = UIStackView(arrangedSubviews: [button, textView])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])
        return row
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

    private func applyFocus() {
        guard let id = desiredFocus, let tv = textViews[id], !tv.isFirstResponder,
              !focusInFlight else { return }
        focusInFlight = true
        requestFocus(tv, attemptsLeft: 8)
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
        let kbInView = view.convert(end, from: nil)
        let overlap = hiding ? 0 : max(0, scrollView.frame.maxY - kbInView.minY)
        scrollView.contentInset.bottom = overlap
        scrollView.verticalScrollIndicatorInsets.bottom = overlap
        scrollActiveCaretToVisible(animated: true)
    }

    /// Scroll the active caret into the visible area. `scrollRectToVisible`
    /// respects `adjustedContentInset` (which includes the keyboard overlap), so
    /// the caret is held above the keyboard — natively, against exact geometry.
    private func scrollActiveCaretToVisible(animated: Bool) {
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
        // The row's intrinsic height changed — settle layout, then keep the caret up.
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
