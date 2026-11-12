//
//  TakeStateWordStrip.swift
//  Catchlight
//
//  An overdue or snoozed Take's state word, "OVERDUE" or "SNOOZED", in capitals in the
//  strip between the card's left edge and the Iris, rotated to read bottom to top, as it was
//  originally (owner 2026-11-12). It goes in the strip only when it fits at 80% of its size
//  or more, along the card's height less 8pt at each end and across the strip's width.
//  Otherwise it stays at the start of the time line, at full size. VoiceOver reads the
//  state from the row's label either way.
//

import SwiftUI
import UIKit

enum TakeStateWordStrip {
    /// The word's size at the default text size: the time line's 11pt, scaled as a caption.
    static let pointSize: CGFloat = 11
    /// Clear space at each end of the word along the card's height.
    static let endGap: CGFloat = 8
    /// The smallest the word may shrink to and still go in the strip.
    static let minimumScale: CGFloat = 0.8

    /// The word in capitals, by the language's own rules (Turkish "SÜRESİ GEÇTİ").
    static func capitals(_ word: String) -> String { word.localizedUppercase }

    /// The word's length and thickness at full size, in the time line's font.
    static func size(of word: String, dynamicTypeSize: DynamicTypeSize) -> CGSize {
        let traits = UITraitCollection(preferredContentSizeCategory: CatchlightFont.contentSizeCategory(dynamicTypeSize))
        let points = CatchlightFont.scaledPoints(pointSize, relativeTo: .caption, compatibleWith: traits)
        let font = UIFont.systemFont(ofSize: points, weight: .medium)
        return (capitals(word) as NSString).size(withAttributes: [.font: font])
    }

    /// The scale the word is drawn at in the strip, or nil when it doesn't fit at
    /// `minimumScale` or more and belongs on the time line instead.
    static func scale(wordSize: CGSize, cardHeight: CGFloat, stripWidth: CGFloat) -> CGFloat? {
        guard wordSize.width > 0, wordSize.height > 0, cardHeight > 0, stripWidth > 0 else { return nil }
        let scale = min(1, (cardHeight - 2 * endGap) / wordSize.width, stripWidth / wordSize.height)
        return scale >= minimumScale ? scale : nil
    }
}

/// The word itself, centred in the strip both ways. Decorative: the row's label speaks it.
struct TakeStateWordLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let word: String
    let scale: CGFloat
    let stripWidth: CGFloat

    var body: some View {
        let traits = UITraitCollection(preferredContentSizeCategory: CatchlightFont.contentSizeCategory(dynamicTypeSize))
        let points = CatchlightFont.scaledPoints(TakeStateWordStrip.pointSize, relativeTo: .caption, compatibleWith: traits)
        Text(TakeStateWordStrip.capitals(word))
            .font(.system(size: points * scale, weight: .medium))
            .foregroundStyle(Color.ckTextOverdue)
            .lineLimit(1)
            .fixedSize()
            .rotationEffect(.degrees(-90))
            .frame(width: stripWidth)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}
