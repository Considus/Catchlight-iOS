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
        // Reconcile the keyboard/bar against the field's ACTUAL first-responder state,
        // not a one-shot "did isActive flip" flag. The flag approach left a stuck state:
        // if the app was backgrounded / re-locked WHILE searching, iOS tore down the
        // keyboard + bar, but `isActive` (still searching) never changed — so on return
        // nothing re-showed them, leaving the search screen with no keyboard and no
        // toolbar (owner 2026-06-20; only escapable by opening an editor). Re-activating
        // when active-but-not-focused restores them. The `!isFirstResponder` gate means a
        // focused field (normal typing) never re-triggers focus, so there's no churn.
        DispatchQueue.main.async {
            if isActive {
                if !vc.bar.field.isFirstResponder { vc.activate() }
            } else if vc.bar.field.isFirstResponder {
                vc.deactivate()
            }
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

    /// Show the keyboard with the bar above it, and focus the field. The controller
    /// becomes first responder so its `inputAccessoryView` (the bar) attaches; the field
    /// can only focus once it's in the window, so force a layout pass first.
    /// (Entrance fade removed 2026-06-20 — owner wants to test the raw entry.)
    func activate() {
        guard view.window != nil, !bar.field.isFirstResponder else { return }
        if !isFirstResponder { _ = becomeFirstResponder() }
        bar.layoutIfNeeded()
        bar.field.becomeFirstResponder()
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

    // Colours read from the single source (`UITheme`, in CatchlightTheme.swift).
    // UIKit can't see the SwiftUI `ck*` tokens, so it shares the UIColor layer those
    // are built on — no brand hex is re-declared here.
    private static let ember = UITheme.accent            // ckAccent (amber foreground)
    private static let surface = UITheme.surface         // ckSurface
    private static let textPrimary = UITheme.textPrimary
    private static let pageBackground = UITheme.background
    /// The completed-Take grey — the placeholder uses this receded "done" tone
    /// (owner 2026-06-20). Shared with `ckTextComplete`.
    private static let placeholderGrey = UITheme.textComplete

    /// The dock's soft fade (HiFi v1.11.5 / `dockFadeBackground`): scrolling content
    /// dissolves UNDER the bar instead of meeting a hard edge. A solid fill here
    /// blocked too much of the timeline and left a hard line where it crossed the Iris
    /// below (owner 2026-06-20). Same stops as the SwiftUI gradient so the search bar
    /// mirrors the dock + editor bar exactly: clear → 0.85 @ 28% → solid @ 55%.
    private let fade = CAGradientLayer()

    init(controller: SearchInputController) {
        self.controller = controller
        // Height matches the editor keyboard bar: 10 top + 44 circle + 8 bottom.
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 62))
        autoresizingMask = [.flexibleWidth]
        backgroundColor = .clear
        fade.startPoint = CGPoint(x: 0.5, y: 0)
        fade.endPoint = CGPoint(x: 0.5, y: 1)
        fade.locations = [0, 0.28, 0.55]
        layer.insertSublayer(fade, at: 0)
        applyFadeColors()
        buildLayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 62) }

    override func layoutSubviews() {
        super.layoutSubviews()
        fade.frame = bounds
    }

    /// CGColors don't auto-resolve for the Scene, so set them explicitly (and refresh
    /// in `traitCollectionDidChange`).
    private func applyFadeColors() {
        fade.colors = [
            Self.pageBackground.withAlphaComponent(0).cgColor,
            Self.pageBackground.withAlphaComponent(0.85).cgColor,
            Self.pageBackground.cgColor,
        ]
    }

    // Dock grid (matches BottomDockView / CatchlightLayout exactly so × lands where +
    // sits at rest and the magnifier on the resting magnifier).
    private static let pad: CGFloat = 12        // dockHorizontalPadding
    private static let circle: CGFloat = 44     // minTouchTarget / circleDiameter
    private static let topPad: CGFloat = 10

    private func buildLayout() {
        // × cancel — circular Ember ring (slot 1). The × is a `plus` rotated 45°,
        // identical to the editor-bar dismiss (owner 2026-06-29): the app's close
        // affordance is the Add "+" turned to ×. The real `xmark` glyph read larger
        // than the rotated plus at the same 24pt, so they're unified to one glyph.
        configureCircleButton(cancelButton, systemName: "plus")
        cancelButton.transform = CGAffineTransform(rotationAngle: .pi / 4)
        cancelButton.accessibilityIdentifier = "search-cancel"
        cancelButton.accessibilityLabel = "Cancel search"
        cancelButton.addTarget(controller?.coordinator,
                               action: #selector(KeyboardSearchBar.Coordinator.cancelTapped),
                               for: .touchUpInside)

        // Magnifier dismiss / Return — circular Ember ring (slot 4). Kept at its
        // original 18pt (owner 2026-06-29): the real `magnifyingglass` reads larger
        // than the rotated-plus cancel at 24, so it's sized down to match optically.
        configureCircleButton(dismissButton, systemName: "magnifyingglass", pointSize: 18)
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
        // Same ring as the buttons (owner 2026-06-20: makes the bar feel sturdier) —
        // Ember @ 0.55, 1.5pt, matching `configureCircleButton` / the dock's `dockRing`.
        field.layer.borderWidth = 1.5
        field.layer.borderColor = Self.ember.withAlphaComponent(0.55).cgColor
        field.textColor = Self.textPrimary
        // Adaptive accent caret (2026-07-01): the fixed #C9A96E was the raw Night
        // Ember — the exact low-contrast-on-Paper case ckAccent exists to avoid;
        // `Self.ember` already carries the Daylight-accessible pair.
        field.tintColor = Self.ember
        field.font = .systemFont(ofSize: 14)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .search
        field.clearButtonMode = .whileEditing
        field.attributedPlaceholder = NSAttributedString(
            string: "Search your Takes",
            attributes: [.foregroundColor: Self.placeholderGrey])
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

    private func configureCircleButton(_ button: UIButton, systemName: String, pointSize: CGFloat = 24) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName,
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .light)),
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
        // Re-resolve the dynamic colours for the new Scene (CGColor doesn't adapt).
        cancelButton.layer.borderColor = Self.ember.withAlphaComponent(0.55).cgColor
        dismissButton.layer.borderColor = Self.ember.withAlphaComponent(0.55).cgColor
        field.layer.borderColor = Self.ember.withAlphaComponent(0.55).cgColor
        applyFadeColors()
    }
}
