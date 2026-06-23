//
//  CatchlightWidgetsBundle.swift
//  CatchlightWidgets (2026-06-23)
//
//  Extension entry point. Bundles the capture surfaces: the home/lock launcher,
//  the medium blank-Take card, and the iOS-18 Control. (iOS 18 floor, so the
//  Control is always available — no #available guard needed.)
//

import WidgetKit
import SwiftUI

@main
struct CatchlightWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NewTakeLauncherWidget()
        NewObieLauncherWidget()
        NewTakeCardWidget()
        NewObieCardWidget()
        NewTakeControl()
        NewObieControl()
    }
}
