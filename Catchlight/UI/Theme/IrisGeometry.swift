//
//  IrisGeometry.swift
//  Catchlight (shared with the widget extension)
//
//  The Iris's shapes in its 44 x 44 unit space, scaled by `s`: the outline cut into six
//  lights, the inner shapes and the Obie's inner square. `IrisView` draws the Take's
//  Iris from these, and the widgets draw the brand Iris from the same ones, so the two
//  cannot drift. Pure geometry: no colour, no Take.
//

import SwiftUI

/// The six lights round the Iris outline, in clockwise order from the top.
enum IrisLight: CaseIterable {
    case important, task, audio, note, image, reminder
}

/// The shape drawn inside the Iris.
enum IrisInnerShape {
    case note, task, reminder, audio, image, fourDots
}

enum IrisGeometry {

    /// Stroke widths in 44 units: a lit light is twice an unlit one (R9).
    static let litWidth: CGFloat = 3
    static let unlitWidth: CGFloat = 1.5
    static let obieSquareWidth: CGFloat = 1.5
    static func innerWidth(_ shape: IrisInnerShape) -> CGFloat { shape == .fourDots ? 3.4 : 1.9 }

    /// The outline: a rounded square from (1.5, 1.5) to (42.5, 42.5), corner radius 11,
    /// traced clockwise from the top centre so the trims below land on the right edges.
    static func outline(scale s: CGFloat) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        let lo: CGFloat = 1.5, hi: CGFloat = 42.5, r: CGFloat = 11 * s
        var path = Path()
        path.move(to: p(22, lo))
        path.addArc(tangent1End: p(hi, lo), tangent2End: p(hi, hi), radius: r)
        path.addArc(tangent1End: p(hi, hi), tangent2End: p(lo, hi), radius: r)
        path.addArc(tangent1End: p(lo, hi), tangent2End: p(lo, lo), radius: r)
        path.addArc(tangent1End: p(lo, lo), tangent2End: p(hi, lo), radius: r)
        path.closeSubpath()
        return path
    }

    /// Light `index`, from (index*100 - 39)/600 to (index*100 + 39)/600 of the outline.
    /// Light 0 straddles the start of the path, so it is two trims.
    static func light(_ index: Int, of outline: Path) -> Path {
        let from = CGFloat(index * 100 - 39) / 600
        let to = CGFloat(index * 100 + 39) / 600
        guard from < 0 else { return outline.trimmedPath(from: from, to: to) }
        var path = outline.trimmedPath(from: 1 + from, to: 1)
        path.addPath(outline.trimmedPath(from: 0, to: to))
        return path
    }

    /// The lights in `lights`, as one path.
    static func lights(_ lights: Set<IrisLight>, scale s: CGFloat) -> Path {
        let outline = outline(scale: s)
        var path = Path()
        for (index, kind) in IrisLight.allCases.enumerated() where lights.contains(kind) {
            path.addPath(light(index, of: outline))
        }
        return path
    }

    /// The Obie's inner rounded square, concentric with the outline (R11).
    static func obieSquare(scale s: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: 5.2 * s, y: 5.2 * s, width: 33.6 * s, height: 33.6 * s),
             cornerRadius: 7.3 * s)
    }

    /// Inner shape segments as [x1, y1, x2, y2] in a 24-unit grid.
    private static func segments(_ shape: IrisInnerShape) -> [[CGFloat]] {
        switch shape {
        case .note:     return [[7.5, 9, 16.5, 9], [7.5, 12, 16.5, 12], [7.5, 15, 13, 15]]
        case .task:     return [[7.2, 12.4, 10.4, 15.6], [10.4, 15.6, 16.8, 8.6]]
        case .reminder: return [[12, 12.6, 12, 6.2], [12, 12.6, 16.6, 15]]
        case .audio:    return [[7, 10.6, 7, 13.4], [9.5, 8.2, 9.5, 15.8], [12, 6.2, 12, 17.8],
                                [14.5, 8.6, 14.5, 15.4], [17, 10.6, 17, 13.4]]
        case .image:    return [[5.6, 17, 10, 12], [10, 12, 13.2, 15.6], [12.2, 14.6, 14.8, 11.6],
                                [14.8, 11.6, 18.4, 17], [16.2, 7.2, 17.4, 7.2]]
        case .fourDots: return [[9, 9, 9, 9], [15, 9, 15, 9], [9, 15, 9, 15], [15, 15, 15, 15]]
        }
    }

    /// The inner shape's path: the 24 grid mapped by translate(22,22) scale(1.3)
    /// translate(-12,-12) into 44 space, then by `s`.
    static func innerPath(_ shape: IrisInnerShape, scale s: CGFloat) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: (22 + (x - 12) * 1.3) * s, y: (22 + (y - 12) * 1.3) * s)
        }
        var path = Path()
        for seg in segments(shape) {
            path.move(to: p(seg[0], seg[1]))
            path.addLine(to: p(seg[2], seg[3]))
        }
        return path
    }
}
