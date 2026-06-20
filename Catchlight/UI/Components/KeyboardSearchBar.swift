//
//  KeyboardSearchBar.swift
//  Catchlight (iOS app target) — search bar 2026-06-20
//
//  The search field rides the keyboard as a UIKit `inputAccessoryView`, the SAME
//  mechanism that makes the editor's `EditorKeyboardBar` sit perfectly on the
//  keyboard on device (owner 2026-06-20). The earlier approach positioned a SwiftUI
//  dock by hand from the keyboard frame — it passed in the simulator and drifted on
//  device (too high, no fade). An `inputAccessoryView` is positioned by UIKit, so it
//  is correct on every device with NO manual math, and — unlike the hand-math — it
//  behaves identically in the simulator.
//
//  Shape: [× cancel]  [— capsule field —]  [magnifier dismiss], matching the dock's
//  four-slot grid and Ember styling. The editable field lives INSIDE the accessory
//  (it must, to ride the keyboard), so it is a real UIKit `UITextField` here for
//  deterministic focus rather than a SwiftUI `TextField` nested in the accessory.
//
//  Accessibility identifiers are kept stable for the UI tests: `search-field`,
//  `search-cancel`, `search-tab` (the dismiss/Return button).
//

import SwiftUI

/// Hosts a first-responder controller whose `inputAccessoryView` is the search bar.
/// Zero-size in the SwiftUI layout — all it does is own the keyboard accessory.
struct KeyboardSearchBar: UIViewControllerRepresentable {
    @Binding var query: String
    /// Drives the keyboard up/down: true while `dockMode == .searching`.
    var isActive: Bool
    /// × — leave search entirely (back to the resting dock).
    var onCancel: () -> Void
    /// Magnifier / Return — lower the keyboard but keep the query + results.
    var onSubmitDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> SearchInputController {
        let vc = SearchInputController()
        vc.coordinator = context.coordinator
        context.coordinator.controller = vc
        return vc
    }

    func updateUIViewController(_ vc: SearchInputController, context: Context) {
        context.coordinator.parent = self
        vc.bar.field.text = query
        // Drive focus from SwiftUI state. Defer to the next runloop so the controller
        // is in a window before becoming first responder on first activation.
        DispatchQueue.main.async {
            if isActive { vc.activate() } else { vc.deactivate() }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: KeyboardSearchBar
        weak var controller: SearchInputController?
        init(_ parent: KeyboardSearchBar) { self.parent = parent }

        @objc func textChanged(_ field: UITextField) {
            parent.query = field.text ?? ""
        }
        @objc func cancelTapped() { parent.onCancel() }
        @objc func dismissTapped() { parent.onSubmitDismiss() }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmitDismiss()
            return true
        }
    }
}

/// The view controller that vends the search bar as its `inputAccessoryView`. Its own
/// view is empty; the bar is the only thing it contributes.
final class SearchInputController: UIViewController {
    weak var coordinator: KeyboardSearchBar.Coordinator?
    lazy var bar = SearchBarAccessory(controller: self)

    override var canBecomeFirstResponder: Bool { true }
    override var inputAccessoryView: UIView? { bar }

    /// Show the keyboard with the bar docked above it, and focus the field.
    func activate() {
        guard view.window != nil else { return }
        if !isFirstResponder { _ = becomeFirstResponder() }
        if !bar.field.isFirstResponder { bar.field.becomeFirstResponder() }
    }

    /// Lower the keyboard and the bar.
    func deactivate() {
        if bar.field.isFirstResponder { bar.field.resignFirstResponder() }
        if isFirstResponder { resignFirstResponder() }
    }
}

/// The keyboard-docked search bar: × · capsule field · magnifier, on the dock's faded
/// background. Pure UIKit so the embedded field focuses deterministically.
final class SearchBarAccessory: UIView {
    let field = UITextField()
    private let cancelButton = UIButton(type: .system)
    private let dismissButton = UIButton(type: .system)
    private weak var controller: SearchInputController?

    // Brand palette (mirrors CatchlightTheme; UIKit can't read the SwiftUI tokens).
    private static let ember = adaptive(dark: 0xC9A96E, light: 0x856539)   // ckAccent
    private static let surface = adaptive(dark: 0x1C1A16, light: 0xFFFFFF) // ckSurface
    private static let textPrimary = adaptive(dark: 0xF5EDD8, light: 0x0F0E0C)
    private static let textSecondary = adaptive(dark: 0xB8B0A3, light: 0x5C5650)
    private static let pageBackground = adaptive(dark: 0x0F0E0C, light: 0xF7F4EF)

    init(controller: SearchInputController) {
        self.controller = controller
        // A generous height for the 44pt circle + dock-matching padding.
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 64))
        autoresizingMask = [.flexibleWidth]
        backgroundColor = Self.pageBackground.withAlphaComponent(0.98)
        buildLayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 64) }

    private func buildLayout() {
        // × cancel — circular Ember ring.
        configureCircleButton(cancelButton, systemName: "xmark")
        cancelButton.accessibilityIdentifier = "search-cancel"
        cancelButton.accessibilityLabel = "Cancel search"
        cancelButton.addTarget(controller?.coordinator,
                               action: #selector(KeyboardSearchBar.Coordinator.cancelTapped),
                               for: .touchUpInside)

        // Magnifier dismiss / Return — circular Ember ring.
        configureCircleButton(dismissButton, systemName: "magnifyingglass")
        dismissButton.accessibilityIdentifier = "search-tab"
        dismissButton.accessibilityLabel = "Search"
        dismissButton.addTarget(controller?.coordinator,
                                action: #selector(KeyboardSearchBar.Coordinator.dismissTapped),
                                for: .touchUpInside)

        // Capsule field.
        field.borderStyle = .none
        field.backgroundColor = Self.surface
        field.textColor = Self.textPrimary
        field.tintColor = UIColor(red: 0xC9/255, green: 0xA9/255, blue: 0x6E/255, alpha: 1) // Ember caret
        field.font = .systemFont(ofSize: 14)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .search
        field.clearButtonMode = .whileEditing
        field.attributedPlaceholder = NSAttributedString(
            string: "Search your Takes",
            attributes: [.foregroundColor: Self.textSecondary])
        field.accessibilityIdentifier = "search-field"
        field.accessibilityLabel = "Search Takes"
        field.delegate = controller?.coordinator
        field.addTarget(controller?.coordinator,
                        action: #selector(KeyboardSearchBar.Coordinator.textChanged),
                        for: .editingChanged)
        // Inset the text from the capsule edge.
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        field.leftViewMode = .always

        let fieldContainer = UIView()
        fieldContainer.backgroundColor = Self.surface
        fieldContainer.layer.cornerRadius = 22
        fieldContainer.layer.cornerCurve = .continuous
        fieldContainer.addSubview(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor, constant: -8),
            field.topAnchor.constraint(equalTo: fieldContainer.topAnchor),
            field.bottomAnchor.constraint(equalTo: fieldContainer.bottomAnchor),
        ])

        // Four-slot grid like the dock: × | field (2 slots) | magnifier.
        let stack = UIStackView(arrangedSubviews: [cancelButton, fieldContainer, dismissButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            fieldContainer.heightAnchor.constraint(equalToConstant: 44),
            cancelButton.widthAnchor.constraint(equalToConstant: 44),
            dismissButton.widthAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func configureCircleButton(_ button: UIButton, systemName: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName,
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .light)),
                        for: .normal)
        button.tintColor = Self.ember
        button.layer.cornerRadius = 22
        button.layer.borderWidth = 1.5
        button.layer.borderColor = Self.ember.withAlphaComponent(0.55).cgColor
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        // Re-resolve the dynamic border colour for the new Scene (CGColor doesn't adapt).
        cancelButton.layer.borderColor = Self.ember.withAlphaComponent(0.55).cgColor
        dismissButton.layer.borderColor = Self.ember.withAlphaComponent(0.55).cgColor
    }

    /// Dynamic UIColor from a dark/light hex pair (Night / Daylight).
    private static func adaptive(dark: Int, light: Int) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }
}

private extension UIColor {
    convenience init(hex: Int) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
