//
//  SheetPageHeading.swift
//  Catchlight
//
//  The page heading on a Settings sub-screen sheet (owner 2026-11-12: "the various page
//  headings need to be changed to match Dailies"). The sheet's bar goes: it held only a
//  small title, since each sheet closes with a swipe down. The heading is pinned at the
//  top, 14pt below the sheet's top edge as on Settings, with Dailies' fade hanging below it
//  so content scrolling under it dissolves. The fade sits over the content rather than in
//  the inset, so at rest it adds no gap.
//

import SwiftUI
import UIKit

/// A text button on the heading's first line, at the right (Notice History's Clear).
struct SheetHeadingAction {
    let label: LocalizedStringResource
    let identifier: String
    let perform: () -> Void
}

extension View {
    /// Pins `title` as the sheet's page heading, with `action` on its first line if given,
    /// and hides the navigation bar.
    func sheetPageHeading(_ title: LocalizedStringResource, centred: Bool = true,
                          action: SheetHeadingAction? = nil) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            SheetPageHeading(title: title, centred: centred, action: action)
                .padding(.top, CatchlightLayout.pageHeadingTopGap)
                .background(Color.ckBackground)
                .overlay(alignment: .bottom) {
                    DailiesView.headingFade()
                        .offset(y: DailiesView.headingFadeHeight)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The heading, and an action's text button on its first line: in the body font and the
/// Scene's accent text colour, on the heading's first baseline, its right edge on
/// the same inset as the heading's left, with a 44pt tap area and 16pt clear of the title.
/// Without an action the heading takes the full width (Art Director, 2026-11-12).
struct SheetPageHeading: View {
    let title: LocalizedStringResource
    var centred = true
    let action: SheetHeadingAction?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var width: CGFloat = 0

    /// The room kept clear for an action labelled `label`: its width, at least the tap area,
    /// and the gap to the title.
    static func reserve(for label: String, category: UIContentSizeCategory) -> CGFloat {
        let font = UIFont.preferredFont(forTextStyle: .body,
                                        compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
        let labelWidth = (label as NSString).size(withAttributes: [.font: font]).width
        return max(labelWidth, CatchlightLayout.minTouchTarget) + 16
    }

    var body: some View {
        let category = CatchlightFont.contentSizeCategory(min(dynamicTypeSize, .accessibility1))
        let reserve = action.map { Self.reserve(for: String(localized: $0.label), category: category) } ?? 0
        PageHeading(title, trailingReserve: reserve, centred: centred)
            .accessibilityAddTraits(.isHeader)
            .overlay(alignment: .topTrailing) {
                if let action {
                    actionButton(action, category: category, reserve: reserve)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func actionButton(_ action: SheetHeadingAction, category: UIContentSizeCategory,
                              reserve: CGFloat) -> some View {
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let body = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
        let inset = CatchlightLayout.dailiesHeadingInset(containerWidth: width)
        let fit = PageHeading.fit(String(localized: title), width: width - 2 * inset - (centred ? 2 : 1) * reserve,
                                  category: category)
        let heading = CatchlightFont.uiDisplay(size: fit.points, relativeTo: nil)
        // The label sits centred in a 44pt-tall tap area; move it so its baseline meets the
        // heading's first baseline.
        let tap = max(CatchlightLayout.minTouchTarget, body.lineHeight)
        let labelBaseline = (tap - body.lineHeight) / 2 + body.ascender
        return Button(action: action.perform) {
            Text(action.label)
                .font(.body)
                // The Scene's accent text colour, as the app's other text buttons use: 4.5:1 or
                // more on the page in every Scene, daylight and night.
                .foregroundStyle(Color.ckAccent)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: CatchlightLayout.minTouchTarget, minHeight: tap, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(action.identifier)
        .offset(y: heading.ascender - labelBaseline)
        .padding(.trailing, inset)
    }
}
