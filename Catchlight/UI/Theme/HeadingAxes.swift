//
//  HeadingAxes.swift
//  Catchlight
//
//  The two numbers that set the heading face, and the axis tags they are set through.
//  One file, compiled into the app, the share sheet and the widget, so changing the
//  width or the weight is a one-line change that reaches every target.
//

import CoreGraphics

enum HeadingAxes {
    /// Archivo's weight axis for headings, inside the 500 to 600 the design allows.
    static let weight: CGFloat = 560
    /// Archivo's width axis for headings, inside the 112 to 125 the design allows.
    static let width: CGFloat = 120
    /// The four-character axis tags `kCTFontVariationAttribute` is keyed by.
    static let weightTag = 0x77676874   // 'wght'
    static let widthTag = 0x77647468    // 'wdth'
}
