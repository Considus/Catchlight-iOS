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
        // Push the query INTO the field only when the field is NOT being edited (e.g.
        // an external clear, or the resume bar). While the user is typing, the field
        // is the source of truth — writing `query` back every SwiftUI update would race
        // the binding (which lags a keystroke behind) and WIPE the just-typed character.
        if !vc.bar.field.isFirstResponder, vc.bar.field.text != query {
            vc.bar.field.text = query
        }
        // Drive focus from SwiftUI state, but only on an actual transition — running
        // become/resignFirstResponder on every update churned focus.
        guard isActive != context.coordinator.lastActive else { return }
        context.coordinator.lastActive = isActive
        DispatchQueue.main.async {
            if isActive { vc.activate() } else { vc.deactivate() }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: KeyboardSearchBar
        weak var controller: SearchInputController?
        /// Last `isActive` seen, so focus changes fire only on a real transition.
        var lastActive = false
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

    /// Show the keyboard with the bar docked above it, and focus the field. The
    /// controller becomes first responder FIRST so its `inputAccessoryView` (the bar)
    /// is attached to the window; the field can only take focus once it's on screen,
    /// so that step is deferred to the next runloop (calling it synchronously was a
    /// no-op — the field wasn't in a window yet, so nothing focused and typing went
    /// nowhere).
    func activate() {
        guard view.window != nil else { return }
        if !isFirstResponder { _ = becomeFirstResponder() }
        guard !bar.field.isFirstResponder else { return }
        DispatchQueue.main.async { [weak self] in
            self?.bar.field.becomeFirstResponder()
        }
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

    // Dock grid (matches BottomDockView / CatchlightLayout exactly so × lands where +
    // sits at rest and the magnifier on the resting magnifier).
    private static let pad: CGFloat = 12        // dockHorizontalPadding
    private static let circle: CGFloat = 44     // minTouchTarget / circleDiameter
    private static let topPad: CGFloat = 10

    private func buildLayout() {
        // × cancel — circular Ember ring (slot 1).
        configureCircleButton(cancelButton, systemName: "xmark")
        cancelButton.accessibilityIdentifier = "search-cancel"
        cancelButton.accessibilityLabel = "Cancel search"
        cancelButton.addTarget(controller?.coordinator,
                               action: #selector(KeyboardSearchBar.Coordinator.cancelTapped),
                               for: .touchUpInside)

        // Magnifier dismiss / Return — circular Ember ring (slot 4).
        configureCircleButton(dismissButton, systemName: "magnifyingglass")
        dismissButton.accessibilityIdentifier = "search-tab"
        dismissButton.accessibilityLabel = "Search"
        dismissButton.addTarget(controller?.coordinator,
                                action: #selector(KeyboardSearchBar.Coordinator.dismissTapped),
                                for: .touchUpInside)

        // The field IS the capsule — same height (44) and end-radius (22) as the
        // buttons (owner 2026-06-20), so it reads as the dock's control family.
        field.translatesAutoresizingMaskIntoConstraints = false
        field.borderStyle = .none
        field.backgroundColor = Self.surface
        field.layer.cornerRadius = Self.circle / 2   // 22 — matches the button circles
        field.layer.cornerCurve = .continuous
        field.layer.masksToBounds = true
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
        // Insets so text/placeholder clear the rounded ends (radius 22) — fixes the
        // left cut-off; the right pad keeps the placeholder off the curve when the
        // clear button is hidden.
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 18, height: 1))
        field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.rightViewMode = .unlessEditing

        [cancelButton, dismissButton, field].forEach(addSubview)

        // Four equal slots across the padded content, exactly like the dock's
        // `geo.size.width / 4` grid. Buttons centre in slots 1 & 4; the field spans
        // from slot 2's leading to slot 3's trailing — the owner's "outer limit".
        let slots = (0..<4).map { _ -> UILayoutGuide in
            let g = UILayoutGuide(); addLayoutGuide(g); return g
        }
        var cons: [NSLayoutConstraint] = []
        for (i, slot) in slots.enumerated() {
            cons.append(slot.topAnchor.constraint(equalTo: topAnchor, constant: Self.topPad))
            cons.append(slot.heightAnchor.constraint(equalToConstant: Self.circle))
            cons.append(i == 0
                ? slot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.pad)
                : slot.leadingAnchor.constraint(equalTo: slots[i - 1].trailingAnchor))
            if i == 3 { cons.append(slot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.pad)) }
            if i > 0 { cons.append(slot.widthAnchor.constraint(equalTo: slots[0].widthAnchor)) }
        }
        cons += [
            cancelButton.centerXAnchor.constraint(equalTo: slots[0].centerXAnchor),
            cancelButton.topAnchor.constraint(equalTo: topAnchor, constant: Self.topPad),
            dismissButton.centerXAnchor.constraint(equalTo: slots[3].centerXAnchor),
            dismissButton.topAnchor.constraint(equalTo: topAnchor, constant: Self.topPad),
            field.leadingAnchor.constraint(equalTo: slots[1].leadingAnchor),
            field.trailingAnchor.constraint(equalTo: slots[2].trailingAnchor),
            field.topAnchor.constraint(equalTo: topAnchor, constant: Self.topPad),
            field.heightAnchor.constraint(equalToConstant: Self.circle),
        ]
        NSLayoutConstraint.activate(cons)
    }

    private func configureCircleButton(_ button: UIButton, systemName: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName,
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .light)),
                        for: .normal)
        button.tintColor = Self.ember
        button.layer.cornerRadius = Self.circle / 2
        button.layer.borderWidth = 1.5
        button.layer.borderColor = Self.ember.withAlphaComponent(0.55).cgColor
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.circle),
            button.heightAnchor.constraint(equalToConstant: Self.circle),
        ])
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
