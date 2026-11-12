//
//  DailiesHeading.swift
//  Catchlight
//
//  The Dailies page heading as drawn in the redesign (owner 2026-11-10): "Dailies" on the
//  left in the display face, today's date small and grey on the right of the same line. When
//  the two don't fit side by side (the largest text sizes, a long date in some languages),
//  the date drops under the title. SEQUENCE and SEARCH keep the shared `PageHeading`.
//

import SwiftUI

struct DailiesHeading: View {
    /// The title's point size at the default text size. 34, Apple's Large Title size: the
    /// website's phone draws "Dailies" at twice its Take text, and the app's Take text is 17
    /// (owner 2026-11-11: "Dailies looks too small, compared with what is on the website";
    /// art director: 34, scaled as a Large Title).
    static let titleSize: CGFloat = CatchlightLayout.pageHeadingSize
    /// The date's point size at the default text size: 14, the website's 0.8 of its Take text
    /// (art director 2026-11-11). With the cards at the toolbar's 17pt margin the longest date in
    /// any language ("segunda-feira, 28 de dezembro") still fits beside the title on the iPhone SE.
    static let dateSize: CGFloat = 14
    /// The website's letter-spacing for the heading, -0.025 em.
    static let titleKerning: CGFloat = CatchlightLayout.pageHeadingKerning
    /// In from each screen edge: the Take cards' margin (`CatchlightLayout.cardMargin`), so the
    /// title and the date line up with the cards' edges below (art director 2026-11-11).
    var horizontalInset: CGFloat

    /// "Monday 9 November" in English; each language's own order and words elsewhere.
    static func dateText(for date: Date, locale: Locale = .current) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }

    var body: some View {
        // Redraws each minute, so the date turns over at midnight while the app is open.
        TimelineView(.everyMinute) { context in
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    title
                    Spacer(minLength: 0)
                    date(context.date)
                }
                VStack(alignment: .leading, spacing: 4) {
                    title
                    date(context.date, stacked: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontalInset)
            // The heading stops growing at the first accessibility size, so at the largest
            // sizes it doesn't take the room a Take being edited needs.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
    }

    private var title: some View {
        Text("Dailies")
            .ckDisplay(size: Self.titleSize, relativeTo: .largeTitle)
            .kerning(Self.titleKerning)
            .foregroundStyle(Color.ckTextPrimary)
            .lineLimit(1)
            // Never wraps inside the word; at the very largest sizes it shrinks a little.
            .minimumScaleFactor(0.6)
            .accessibilityAddTraits(.isHeader)
    }

    /// Always one line. Stacked under the title it may shrink a little to fit the width.
    private func date(_ now: Date, stacked: Bool = false) -> some View {
        Text(Self.dateText(for: now))
            .ckBody(.regular, size: Self.dateSize, relativeTo: .caption)
            .foregroundStyle(Color.ckTextSecondary)
            .lineLimit(1)
            .minimumScaleFactor(stacked ? 0.7 : 1)
            .fixedSize(horizontal: !stacked, vertical: true)
            .accessibilityIdentifier("dailies-date")
    }
}

#Preview("Dailies heading") {
    VStack(spacing: 24) {
        DailiesHeading(horizontalInset: 25)
        DailiesHeading(horizontalInset: 25).environment(\.dynamicTypeSize, .accessibility5)
    }
    .background(Color.ckBackground)
}
