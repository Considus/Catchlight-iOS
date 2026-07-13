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

    /// Current block order, so `apply` can tell a structural change (rebuild)
    /// from a text-only change (sync in place).
    private var blockOrder: [UUID] = []
    private var textViews: [UUID: UITextView] = [:]
    private var desiredFocus: UUID?
    private var focusInFlight = false
    /// Breathing room kept below the caret — how far above the keyboard the caret
    /// rests before the content scrolls under it. Tunable (old editor used 72).
    private let caretBottomGap: CGFloat = 28

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
        let ids = blocks.map(\.id)
        if ids != blockOrder {
            rebuild(blocks: blocks)
            blockOrder = ids
        } else {
            // Same structure — sync text into any field NOT currently being typed
            // in (typing the active field must never be stomped by the echo back).
            for block in blocks {
                guard let tv = textViews[block.id] else { continue }
                if !tv.isFirstResponder, tv.text != block.text { tv.text = block.text }
            }
        }
        desiredFocus = focusedBlockID
        applyFocus()
    }

    private func rebuild(blocks: [TakeBlock]) {
        for v in stack.arrangedSubviews {
            stack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        textViews.removeAll()
        for block in blocks {
            // M1: every block renders as a text row. Check-row chrome (checkbox +
            // drag handle) and list semantics arrive in M2; showing the text keeps
            // a mixed Take intact meanwhile.
            let tv = makeTextView(id: block.id, text: block.text)
            textViews[block.id] = tv
            stack.addArrangedSubview(tv)
        }
    }

    /// Matches the current `BlockTextEditor` styling exactly (D-042 DM Sans).
    private func makeTextView(id: UUID, text: String) -> UITextView {
        let tv = UITextView()
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.font = CatchlightFont.uiBody(size: 14)
        tv.textColor = UIColor(Color.ckTextPrimary)
        tv.tintColor = UIColor(Color.ckAccent)
        tv.delegate = self
        tv.text = text
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        return tv
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
}
