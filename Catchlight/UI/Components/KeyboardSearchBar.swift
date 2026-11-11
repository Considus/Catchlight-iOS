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
//  Shape, as drawn in the redesign: [magnifier + field] [Cancel]. Return lowers the
//  keyboard and keeps the query. The editable field lives INSIDE the accessory (it
//  must, to ride the keyboard), so it is a real UIKit `UITextField` here for
//  deterministic focus rather than a SwiftUI `TextField` nested in the accessory.
//
//  Accessibility identifiers are kept stable for the UI tests: `search-field` and
//  `search-cancel`.
//

import SwiftUI

/// Hosts a first-responder controller whose `inputAccessoryView` is the search bar.
/// Zero-size in the SwiftUI layout — all it does is own the keyboard accessory.
struct KeyboardSearchBar: UIViewControllerRepresentable {
    @Binding var query: String
    /// Drives the keyboard up/down: true while searching with the keyboard raised.
    var isActive: Bool
    /// Cancel: leave search entirely (back to the resting toolbar).
    var onCancel: () -> Void
    /// Return: lower the keyboard but keep the query and results.
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

/// The keyboard-docked search row, as drawn in the redesign: an outlined field with a
/// magnifier, then Cancel in the action colour, on a solid ground strip. Pure UIKit so
/// the embedded field focuses deterministically. Return lowers the keyboard and keeps
/// the query; Cancel leaves search.
final class SearchBarAccessory: UIView {
    let field = UITextField()
    private let cancelButton = UIButton(type: .system)
    private let magnifier = UIImageView()
    private weak var controller: SearchInputController?

    // Colours read from the single source (`UITheme`, in CatchlightTheme.swift).
    // UIKit can't see the SwiftUI `ck*` tokens, so it shares the UIColor layer those
    // are built on: no brand hex is re-declared here.
    private static let accent = UITheme.accent            // ckAccent (accentText)
    private static let surface = UITheme.surface          // ckSurface (card)
    private static let textPrimary = UITheme.textPrimary
    private static let textSecondary = UITheme.textSecondary
    private static let pageBackground = UITheme.background
    /// The placeholder tone, 4.5:1 on the field and receded next to the typed query.
    private static let placeholderGrey = UITheme.placeholder

    /// The Dailies toolbar's side inset: the search row stands in for the toolbar's panel while
    /// the keyboard is up, so it keeps the panel's sides.
    private static let pad: CGFloat = CatchlightLayout.dockInset
    private static let rowHeight: CGFloat = CatchlightLayout.minTouchTarget
    private static let topPad: CGFloat = 10
    private static let bottomPad: CGFloat = 8

    init(controller: SearchInputController) {
        self.controller = controller
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width,
                                 height: Self.topPad + Self.rowHeight + Self.bottomPad))
        autoresizingMask = [.flexibleWidth]
        // Solid and flat: the timeline stops at the row instead of fading under it.
        backgroundColor = Self.pageBackground
        buildLayout()
        // Re-resolve the CGColor-backed outline on a Light/Dark or Scene change,
        // including when the bar first joins a window. The bar lives for the app's
        // lifetime, so a Scene chosen after it was built must still reach it.
        registerForTraitChanges([UITraitUserInterfaceStyle.self, SceneTrait.self]) { (bar: SearchBarAccessory, _) in
            bar.refreshDynamicColors()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.topPad + Self.rowHeight + Self.bottomPad)
    }

    /// The field's outline for the bar's current traits: the `outline` token, 3:1 on the surface.
    private var fieldOutline: CGColor {
        SceneToken.outline.resolvedColor(with: traitCollection).cgColor
    }

    private func buildLayout() {
        // Cancel: text in the action colour, as drawn. It leaves search and clears it.
        var config = UIButton.Configuration.plain()
        config.title = String(localized: "Cancel")
        config.baseForegroundColor = Self.accent
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFontMetrics(forTextStyle: .body)
                .scaledFont(for: .systemFont(ofSize: 15, weight: .medium))
            return a
        }
        cancelButton.configuration = config
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)
        cancelButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        cancelButton.accessibilityIdentifier = "search-cancel"
        cancelButton.accessibilityLabel = String(localized: "Cancel search")
        cancelButton.addTarget(controller?.coordinator,
                               action: #selector(KeyboardSearchBar.Coordinator.cancelTapped),
                               for: .touchUpInside)

        // The field: a flat rounded rectangle at the surface radius, outlined with the
        // `outline` token, a magnifier leading the text.
        field.translatesAutoresizingMaskIntoConstraints = false
        field.borderStyle = .none
        field.backgroundColor = Self.surface
        field.layer.cornerRadius = CatchlightLayout.surfaceRadius
        field.layer.cornerCurve = .continuous
        field.layer.masksToBounds = true
        field.layer.borderWidth = 1
        field.layer.borderColor = fieldOutline
        field.textColor = Self.textPrimary
        field.tintColor = Self.accent
        field.font = CatchlightFont.uiBody(size: 15)
        field.adjustsFontForContentSizeCategory = true
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .search
        field.clearButtonMode = .whileEditing
        field.attributedPlaceholder = NSAttributedString(
            string: String(localized: "Search your Takes"),
            attributes: [.foregroundColor: Self.placeholderGrey])
        field.accessibilityIdentifier = "search-field"
        field.accessibilityLabel = String(localized: "Search Takes")
        field.delegate = controller?.coordinator
        field.addTarget(controller?.coordinator,
                        action: #selector(KeyboardSearchBar.Coordinator.textChanged),
                        for: .editingChanged)
        magnifier.image = UIImage(systemName: "magnifyingglass",
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .regular))
        magnifier.tintColor = Self.textSecondary
        magnifier.contentMode = .center
        let lead = UIView(frame: CGRect(x: 0, y: 0, width: 38, height: Self.rowHeight))
        magnifier.frame = CGRect(x: 12, y: 0, width: 18, height: Self.rowHeight)
        lead.addSubview(magnifier)
        field.leftView = lead
        field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.rightViewMode = .unlessEditing

        [field, cancelButton].forEach(addSubview)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.pad),
            field.topAnchor.constraint(equalTo: topAnchor, constant: Self.topPad),
            field.heightAnchor.constraint(equalToConstant: Self.rowHeight),
            cancelButton.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 10),
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.pad),
            cancelButton.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.rowHeight),
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.rowHeight),
        ])
    }

    /// Re-resolve the CGColors for the new appearance or Scene.
    /// Called by the trait-change registration in `init`.
    private func refreshDynamicColors() {
        field.layer.borderColor = fieldOutline
    }
}
