//
//  SheetType.swift
//  Catchlight
//
//  The type scale for text on sheets (Settings, Sync Conflicts and the Settings sub-screens),
//  one token per role, so the same role reads the same on every sheet (owner 2026-11-12: "I
//  don't mind if sizes of text are adjusted, as long as there's consistency across screens";
//  the Art Director set the sizes). Every size scales with the text size. The heading itself
//  is `PageHeading` (34), and filled buttons keep `DockPill` (15 medium).
//
//  Colour and alignment stay with each use: a role keeps its size and weight wherever it is.
//

import SwiftUI

enum SheetType {
    /// The lead line under a heading ("Choose a cloud folder you own"): Archivo 22.
    static let leadSize: CGFloat = 22
    /// Rows and text actions: row titles, Clear, Sync Now, Remove, About's link rows.
    static let rowSize: CGFloat = 17
    /// Guidance and explanation paragraphs.
    static let bodySize: CGFloat = 15
    /// Captions, footers, timestamps, the version line, fine print, paths.
    static let smallSize: CGFloat = 13
    /// The uppercase label above a group of rows.
    static let labelSize: CGFloat = 13
}

extension View {
    /// The lead line under a sheet's heading: Archivo 22, scaling as Title 2 up to the second
    /// accessibility size, so it never outgrows the heading (which stops at the first).
    func sheetLead() -> some View {
        ckDisplay(size: SheetType.leadSize, relativeTo: .title2)
            .lineSpacing(CatchlightFont.tightLeading(size: SheetType.leadSize))
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    /// A row title or a text action: 17 regular, scaling as Body.
    func sheetRow() -> some View {
        ckBody(.regular, size: SheetType.rowSize, relativeTo: .body)
    }

    /// A paragraph of guidance or explanation: 15 regular, scaling as Body.
    func sheetBody() -> some View {
        ckBody(.regular, size: SheetType.bodySize, relativeTo: .body)
    }

    /// Small print: 13 regular, scaling as Footnote.
    func sheetSmall() -> some View {
        ckBody(.regular, size: SheetType.smallSize, relativeTo: .footnote)
    }

    /// The label above a group of rows: 13 medium, upper case, secondary.
    func sheetSectionLabel() -> some View {
        ckBody(.medium, size: SheetType.labelSize, relativeTo: .caption)
            .foregroundStyle(Color.ckTextSecondary)
            .textCase(.uppercase)
    }
}
