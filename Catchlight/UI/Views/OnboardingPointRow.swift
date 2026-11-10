//
//  OnboardingPointRow.swift
//  Catchlight (iOS app target)
//
//  One point on the "A few things worth knowing" pages, as drawn: a small drawing of the control
//  it names beside its title and sentence, under a hairline. This is the whole of that layout,
//  so going back to centred text is a change to the one call in `BasicsStep`. The accessibility
//  of a point (one element, its spoken label) is set by `BasicsStep`, not here.
//

import SwiftUI
import CatchlightCore

struct OnboardingPointRow: View {
    typealias Mark = PointMark.Kind
    let mark: Mark
    let title: String
    let shown: String

    @Environment(\.dynamicTypeSize) private var dynamicSize

    /// The drawing beside its text, or above it at the accessibility sizes, where a text column
    /// narrowed by the drawing would wrap a few words to a line.
    private var layout: AnyLayout {
        dynamicSize >= .accessibility1
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.ckLine).frame(height: 1)
            layout {
                PointMark(kind: mark)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .ckBody(.semibold, size: 16, relativeTo: .body)
                        .foregroundStyle(Color.ckTextPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(shown)
                        .ckBody(.light, size: 15, relativeTo: .body)
                        .foregroundStyle(Color.ckTextSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
        }
    }
}

/// The small drawing beside a point: the control it names, drawn with the app's own shapes. The
/// Iris and the Obie are the real `IrisView`, so they can never drift from the timeline's.
struct PointMark: View {
    enum Kind { case add, iris, obie, swipeUp }
    let kind: Kind

    /// A Task, so the Iris tile shows its tick.
    private static let taskTake = Take(blocks: [.checkItem("")], isNote: false)
    /// The Obie, so its tile shows the inner square and the lit top light.
    private static let obieTake = Take(blocks: [.textLine("")], isObie: true, isImportant: true)

    var body: some View {
        ZStack {
            CatchlightShape.control.fill(Color.ckSurfaceRole)
            switch kind {
            case .add:
                ZStack {
                    CatchlightShape.control.fill(Color.ckAdd)
                    PlusStroke()
                        .stroke(Color.ckOnAccent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .frame(width: 16, height: 16)
                }
                .frame(width: 34, height: 34)
            case .iris, .obie:
                // A Take card in miniature, with the real Iris at its corner.
                IrisView(take: kind == .obie ? Self.obieTake : Self.taskTake, diameter: 28)
                    .padding(5)
                    .frame(width: 60, height: 48, alignment: .topLeading)
                    .flatTile(fill: kind == .obie ? Color.ckCardObieSurface : Color.ckSurface)
            case .swipeUp:
                ArrowUpStroke()
                    .stroke(Color.ckTextPrimary,
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .frame(width: 26, height: 26)
            }
        }
        .frame(width: 72, height: 62)
    }
}

/// The plus of the Add button, as one stroke scaled to the frame it is given.
private struct PlusStroke: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        }
    }
}

/// An arrow up, for the swipe from the toolbar, as one stroke scaled to the frame it is given.
private struct ArrowUpStroke: Shape {
    func path(in r: CGRect) -> Path {
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        return Path { p in
            p.move(to: at(0.5, 0.77)); p.addLine(to: at(0.5, 0.23))
            p.move(to: at(0.29, 0.44)); p.addLine(to: at(0.5, 0.23)); p.addLine(to: at(0.71, 0.44))
        }
    }
}

