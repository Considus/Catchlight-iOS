//
//  VerticalReorderGesture.swift
//  Catchlight (iOS app target)
//
//  Rescued from `InlineTakeEditCard.swift` at M7 (2026-07-16). The editor it lived in is gone
//  (the UIKit editor does its own drag-reorder), but `ShotListView` still drives its checklist
//  reorder with this — a LIVE screen. Deleting its old file would have broken the Shot List.
//

import SwiftUI
import UIKit

/// An immediate "drag the handle to reorder" gesture bridged from UIKit (iOS 18
/// `UIGestureRecognizerRepresentable`) — the same approach as `HorizontalSwipePan`,
/// and for the same reason: a SwiftUI gesture can't coordinate with the enclosing
/// ScrollView's own pan. Reorder is VERTICAL (same axis as scroll), so a velocity
/// test can't separate it — instead the delegate makes the ScrollView's pan REQUIRE
/// THIS ONE TO FAIL, so a vertical drag that starts on the handle wins outright and
/// reorders with no press-delay, while drags anywhere else scroll normally.
/// (Reused by the Shot List's reorder in Phase 4.)
struct VerticalReorderGesture: UIGestureRecognizerRepresentable {
    var onBegan: () -> Void
    /// Cumulative vertical translation (pt) since the drag began.
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let ty = recognizer.translation(in: recognizer.view).y
        switch recognizer.state {
        case .began:
            onBegan()
        case .changed:
            onChanged(ty)
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        // Begin only on a VERTICAL-led drag, so a horizontal swipe on the handle still
        // reaches the row's swipe action (orthogonal axis).
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.y) > abs(v.x)
        }

        // Make the enclosing ScrollView's pan WAIT for ours to fail — so a vertical
        // drag starting on the handle reorders instead of scrolling, with no delay.
        // Only touches on the handle involve our recognizer, so normal scrolling
        // (drags on the card body / elsewhere) is untouched.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            if let scroll = other.view as? UIScrollView, other === scroll.panGestureRecognizer {
                return true
            }
            return false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            false
        }
    }
}

/// Collects each block row's measured height (keyed by block id) so the reorder maths
/// use real geometry. Last writer wins per id; the dict merges across all rows.
