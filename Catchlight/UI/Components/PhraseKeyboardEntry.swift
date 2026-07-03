//
//  PhraseKeyboardEntry.swift
//  Catchlight (iOS app target) — restore-phrase entry, UIKit-backed (D-103)
//
//  The 12 phrase fields are UIKit `UITextField`s so they can vend a keyboard-docked
//  `inputAccessoryView` — the SAME mechanism the editor toolbar and search bar use to
//  sit PERFECTLY on the keyboard (owner 2026-07-02). The pure-SwiftUI attempt
//  (safeAreaInset dock, then a `.keyboard` toolbar) fought the ScrollView and left the
//  Restore/Back pills floating over the fields; UIKit positions the accessory itself,
//  with no manual frame math, exactly like `KeyboardSearchBar`.
//
//  All 12 fields share ONE accessory instance (only one field is first responder at a
//  time, so UIKit re-parents it). The SwiftUI grid keeps the tokenising / paste-spread
//  / focus-advance logic; these fields just report raw text changes and focus.
//

import SwiftUI
import UIKit

// MARK: - Bridge (owns the shared accessory + its live actions/enabled state)

/// Owns the single shared accessory bar. The SwiftUI side keeps `onRestore`/`onBack`
/// pointing at the latest closures (so `Restore` submits the CURRENT words) and toggles
/// `setReady` as the fields fill. The `accessory` UIView is created lazily — on first
/// access from `body`, i.e. on the main actor.
final class RestoreBarBridge {
    var onRestore: () -> Void = {}
    var onBack: () -> Void = {}

    lazy var accessory: RestoreKeyboardAccessory = RestoreKeyboardAccessory(
        onRestore: { [weak self] in self?.onRestore() },
        onBack: { [weak self] in self?.onBack() })

    func setReady(_ ready: Bool) { accessory.setReady(ready) }
}

// MARK: - The keyboard-docked accessory bar (pure UIKit, mirrors SearchBarAccessory)

/// [ — Restore — ] [ — Back — ] on the dock's soft fade, sitting flush on the keyboard.
final class RestoreKeyboardAccessory: UIView {
    private let restoreButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let onRestore: () -> Void
    private let onBack: () -> Void
    private let fade = CAGradientLayer()

    // Colours read from the single source (`UITheme`, in CatchlightTheme.swift).
    // UIKit can't see the SwiftUI `ck*` tokens, so it shares the UIColor layer those
    // are built on — no brand hex is re-declared here.
    private static let ember = UITheme.add               // Restore fill (raw Ember, both modes)
    private static let ink = UITheme.onAccent            // Restore text (Ink on Ember)
    private static let textPrimary = UITheme.textPrimary // Back button
    private static let pageBackground = UITheme.background

    private static let pad: CGFloat = 12       // dockHorizontalPadding
    private static let circle: CGFloat = 44    // minTouchTarget
    private static let topPad: CGFloat = 10
    private static let barHeight: CGFloat = 62 // 10 + 44 + 8, matches the editor bar

    init(onRestore: @escaping () -> Void, onBack: @escaping () -> Void) {
        self.onRestore = onRestore
        self.onBack = onBack
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: Self.barHeight))
        autoresizingMask = [.flexibleWidth]
        backgroundColor = .clear
        fade.startPoint = CGPoint(x: 0.5, y: 0)
        fade.endPoint = CGPoint(x: 0.5, y: 1)
        fade.locations = [0, 0.28, 0.55]
        layer.insertSublayer(fade, at: 0)
        applyFadeColors()
        buildLayout()
        setReady(false)
        // Re-resolve the CGColor-backed border/fade on a Night/Daylight change
        // (iOS 17+ trait-change registration; replaces the deprecated
        // `traitCollectionDidChange` override).
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (bar: RestoreKeyboardAccessory, _) in
            bar.refreshDynamicColors()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.barHeight) }

    /// Position the two pills on the EXACT dock grid `DockPillRow` uses (owner
    /// 2026-07-02): four equal slots inside the 12pt horizontal padding, the leading
    /// pill covering slots 1+2 and the trailing pill slots 3+4 — so if the bottom dock
    /// were slid up under this bar, the pills would obscure it precisely.
    override func layoutSubviews() {
        super.layoutSubviews()
        fade.frame = bounds
        let slotW = (bounds.width - 2 * Self.pad) / 4
        let d = Self.circle                       // 44 — the dock button diameter
        let pillW = slotW + d                     // a pill spans two slots
        let gap = slotW - d                       // the dock's inter-button gap
        let restoreX = Self.pad + (slotW / 2 - d / 2)
        restoreButton.frame = CGRect(x: restoreX, y: Self.topPad, width: pillW, height: d)
        backButton.frame = CGRect(x: restoreX + pillW + gap, y: Self.topPad, width: pillW, height: d)
    }

    func setReady(_ ready: Bool) {
        restoreButton.isEnabled = ready
        restoreButton.alpha = ready ? 1 : 0.5
    }

    private func applyFadeColors() {
        fade.colors = [
            Self.pageBackground.withAlphaComponent(0).cgColor,
            Self.pageBackground.withAlphaComponent(0.85).cgColor,
            Self.pageBackground.cgColor,
        ]
    }

    private func buildLayout() {
        configurePill(restoreButton, title: "Restore", filled: true)
        restoreButton.accessibilityIdentifier = "restore-submit"
        restoreButton.addAction(UIAction { [weak self] _ in self?.onRestore() }, for: .touchUpInside)

        configurePill(backButton, title: "Back", filled: false)
        backButton.accessibilityIdentifier = "restore-back"
        backButton.addAction(UIAction { [weak self] _ in self?.onBack() }, for: .touchUpInside)

        [restoreButton, backButton].forEach(addSubview)   // positioned in layoutSubviews
    }

    private func configurePill(_ button: UIButton, title: String, filled: Bool) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = CatchlightFont.uiBody(size: 15, weight: .medium)
        button.layer.cornerRadius = Self.circle / 2
        button.layer.cornerCurve = .continuous
        button.layer.masksToBounds = true
        if filled {
            button.backgroundColor = Self.ember
            button.setTitleColor(Self.ink, for: .normal)
        } else {
            button.backgroundColor = .clear
            button.layer.borderWidth = 1
            button.layer.borderColor = Self.textPrimary.withAlphaComponent(0.4).cgColor
            button.setTitleColor(Self.textPrimary, for: .normal)
        }
    }

    /// CGColors don't auto-resolve for the Scene — refresh the adaptive ones.
    /// Called by the trait-change registration in `init`.
    private func refreshDynamicColors() {
        backButton.layer.borderColor = Self.textPrimary.withAlphaComponent(0.4).cgColor
        backButton.setTitleColor(Self.textPrimary, for: .normal)
        applyFadeColors()
    }
}

// MARK: - One UIKit phrase field

/// A single UITextField bound to `fields[index]`, sharing the keyboard accessory. The
/// grid's `onTextChange` runs the tokenise / paste-spread / advance logic; this view
/// keeps the binding, the focus, and the accessory.
struct PhraseTextField: UIViewRepresentable {
    @Binding var text: String
    let index: Int
    @Binding var focusedIndex: Int?
    let isLast: Bool
    let accessory: UIView?
    /// Called on every raw change with the field's text — the grid handles the rest.
    var onTextChange: (String) -> Void

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.delegate = context.coordinator
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.keyboardType = .asciiCapable
        tf.returnKeyType = isLast ? .done : .next
        tf.inputAccessoryView = accessory
        tf.font = CatchlightFont.uiBody(size: 16, weight: .light)
        tf.textColor = UIColor(Color.ckTextPrimary)
        tf.tintColor = UIColor(Color.ckTextObie)          // accent caret
        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        tf.accessibilityIdentifier = "restore-word-\(index + 1)"
        return tf
    }

    func updateUIView(_ tf: UITextField, context: Context) {
        context.coordinator.parent = self
        if tf.text != text { tf.text = text }
        tf.returnKeyType = isLast ? .done : .next
        // Drive focus from the grid's `focusedIndex` (advance / paste-spread set it).
        if focusedIndex == index, !tf.isFirstResponder {
            DispatchQueue.main.async { if !tf.isFirstResponder { tf.becomeFirstResponder() } }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PhraseTextField
        init(_ parent: PhraseTextField) { self.parent = parent }

        @objc func editingChanged(_ tf: UITextField) {
            let value = tf.text ?? ""
            parent.text = value              // keep fields[index] in sync every keystroke
            parent.onTextChange(value)       // grid runs advance / paste-spread
        }

        func textFieldDidBeginEditing(_ tf: UITextField) {
            if parent.focusedIndex != parent.index { parent.focusedIndex = parent.index }
        }

        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            parent.focusedIndex = parent.isLast ? nil : parent.index + 1
            return false
        }
    }
}
