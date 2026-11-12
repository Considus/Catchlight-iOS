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
    static let titleSize: CGFloat = 34
    /// The date's point size at the default text size: 14, the website's 0.8 of its Take text
    /// (art director 2026-11-11). With the cards at the toolbar's 17pt margin the longest date in
    /// any language ("segunda-feira, 28 de dezembro") still fits beside the title on the iPhone SE.
    static let dateSize: CGFloat = 14
    /// The website's letter-spacing for the heading, -0.025 em.
    static let titleKerning: CGFloat = -0.025 * titleSize
    /// In from each screen edge: the Take cards' margin (`CatchlightLayout.cardMargin`), so the
    /// title and the date line up with the cards' edges below (art director 2026-11-11).
    var horizontalInset: CGFloat

    /// The date in each language's own order and words, cut around the day number so the
    /// ordinal letters can be raised: "Thursday 12th November" in the UK, "Thursday, November
    /// 12th" in the US, "dimanche 1er novembre" in French on the 1st (owner 2026-11-12: "12th
    /// with month"). Every other language is unchanged, with no suffix.
    struct DateParts: Equatable {
        var beforeDay: String
        var day: String
        var suffix: String
        var afterDay: String
        /// The whole date as one line of text, which VoiceOver reads ("twelfth").
        var plain: String { beforeDay + day + suffix + afterDay }
    }

    static func dateParts(for date: Date, locale: Locale = .current) -> DateParts {
        let style = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).locale(locale)
        let attributed = date.formatted(style.attributed)
        guard let dayRun = attributed.runs.first(where: { $0.foundation.dateField == .day }) else {
            return DateParts(beforeDay: String(attributed.characters), day: "", suffix: "", afterDay: "")
        }
        let day = String(attributed[dayRun.range].characters)
        return DateParts(beforeDay: String(attributed[..<dayRun.range.lowerBound].characters),
                         day: day,
                         suffix: Int(day).map { ordinalSuffix(day: $0, locale: locale) } ?? "",
                         afterDay: String(attributed[dayRun.range.upperBound...].characters))
    }

    /// The letters after the day number: English "st", "nd", "rd" or "th" (11th to 13th
    /// included); French "er" on the 1st only; nothing in any other language.
    static func ordinalSuffix(day: Int, locale: Locale) -> String {
        switch locale.language.languageCode?.identifier {
        case "en":
            if (11...13).contains(day % 100) { return "th" }
            switch day % 10 {
            case 1: return "st"
            case 2: return "nd"
            case 3: return "rd"
            default: return "th"
            }
        case "fr":
            return day == 1 ? "er" : ""
        default:
            return ""
        }
    }

    /// The raised letters' size and lift, as fractions of the date's own size.
    static let suffixScale: CGFloat = 0.7
    static let suffixLift: CGFloat = 0.35

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
        DateLine(parts: Self.dateParts(for: now))
            .foregroundStyle(Color.ckTextSecondary)
            .lineLimit(1)
            .minimumScaleFactor(stacked ? 0.7 : 1)
            .fixedSize(horizontal: !stacked, vertical: true)
            .accessibilityIdentifier("dailies-date")
    }
}

/// The date as one Text, with the ordinal letters smaller and raised. Its own view so it reads
/// the text size inside the heading's cap, not the one outside it.
private struct DateLine: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let parts: DailiesHeading.DateParts

    var body: some View {
        let traits = UITraitCollection(preferredContentSizeCategory: CatchlightFont.contentSizeCategory(dynamicTypeSize))
        let size = CatchlightFont.scaledPoints(DailiesHeading.dateSize, relativeTo: .caption, compatibleWith: traits)
        let raised = Text(parts.suffix)
            .font(.system(size: size * DailiesHeading.suffixScale))
            .baselineOffset(size * DailiesHeading.suffixLift)
        return (Text(parts.beforeDay + parts.day) + raised + Text(parts.afterDay))
            .font(.system(size: size))
            .accessibilityLabel(parts.plain)
    }
}

#Preview("Dailies heading") {
    VStack(spacing: 24) {
        DailiesHeading(horizontalInset: 25)
        DailiesHeading(horizontalInset: 25).environment(\.dynamicTypeSize, .accessibility5)
    }
    .background(Color.ckBackground)
}
