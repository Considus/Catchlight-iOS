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

extension View {
    /// Pins `title` as the sheet's page heading, centred as on every sheet, and hides the
    /// navigation bar.
    func sheetPageHeading(_ title: LocalizedStringResource, centred: Bool = true) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            PageHeading(title, centred: centred)
                .accessibilityAddTraits(.isHeader)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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
