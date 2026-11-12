//
//  CatchlightMotion.swift
//  Catchlight (iOS app target)
//
//  The timings icons and controls use when they change state. The source is the art
//  director's motion direction, approved by the owner on 2026-11-11
//  (Brand_System/icon-motion.md). Add a timing here, never as a number inside a view.
//

import SwiftUI

enum CatchlightMotion {
    /// Shape changes: 0.32 s, ease-in-out cubic.
    static let shape = Animation.timingCurve(0.65, 0, 0.35, 1, duration: 0.32)
    /// Turns, with a slight overshoot.
    static let turn = Animation.spring(response: 0.35, dampingFraction: 0.62)
    /// Press squeeze: the fast spring the Focus marks use.
    static let press = Animation.spring(response: 0.3, dampingFraction: 0.7)
    /// The Reduce Motion fade.
    static let reduced = Animation.easeInOut(duration: 0.12)

    /// `base`, or nil (no movement) when Reduce Motion is on: the caller then fades with `reduced`.
    static func movement(_ base: Animation, reduceMotion: Bool) -> Animation? { reduceMotion ? nil : base }
}
