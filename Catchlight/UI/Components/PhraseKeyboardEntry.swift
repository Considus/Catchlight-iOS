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

    // Brand palette (UIKit can't read the SwiftUI tokens; mirrors CatchlightTheme).
    private static let ember = ckHex(0xC9A96E)                       // ckAdd — Restore fill
    private static let ink = ckHex(0x0F0E0C)                         // ckOnAccent — Restore text
    private static let textPrimary = ckAdaptive(dark: 0xF5EDD8, light: 0x0F0E0C)  // ckTextPrimary — Back
    private static let pageBackground = ckAdaptive(dark: 0x0F0E0C, light: 0xF7F4EF)

    private static let pad: CGFloat = 12       // dockHorizontalPadding
    private static let circle: CGFloat = 44    // minTouchTarget
    private static let topPad: CGFloat = 10
    private static let gap: CGFloat = 10
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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.barHeight) }
    override func layoutSubviews() { super.layoutSubviews(); fade.frame = bounds }

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

        [restoreButton, backButton].forEach(addSubview)
        NSLayoutConstraint.activate([
            restoreButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.pad),
            restoreButton.topAnchor.constraint(equalTo: topAnchor, constant: Self.topPad),
            restoreButton.heightAnchor.constraint(equalToConstant: Self.circle),

            backButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.pad),
            backButton.topAnchor.constraint(equalTo: topAnchor, constant: Self.topPad),
            backButton.heightAnchor.constraint(equalToConstant: Self.circle),

            restoreButton.trailingAnchor.constraint(equalTo: backButton.leadingAnchor, constant: -Self.gap),
            restoreButton.widthAnchor.constraint(equalTo: backButton.widthAnchor),
        ])
    }

    private func configurePill(_ button: UIButton, title: String, filled: Bool) {
        button.translatesAutoresizingMaskIntoConstraints = false
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

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        // CGColors don't auto-resolve for the Scene — refresh the adaptive ones.
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

// MARK: - File-local UIKit colour helpers (mirror CatchlightTheme's private ones)

private func ckHex(_ hex: UInt32) -> UIColor {
    UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

private func ckAdaptive(dark: UInt32, light: UInt32) -> UIColor {
    UIColor { $0.userInterfaceStyle == .dark ? ckHex(dark) : ckHex(light) }
}
