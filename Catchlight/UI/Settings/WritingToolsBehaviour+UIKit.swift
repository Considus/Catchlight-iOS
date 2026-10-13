//
//  WritingToolsBehaviour+UIKit.swift
//  Catchlight (iOS app target)
//
//  Maps the user's Writing Tools choice onto UIKit. Lives in the app target so
//  `CatchlightCore` stays free of UIKit and the model stays unit-testable.
//

import UIKit
import CatchlightCore

extension WritingToolsBehaviour {
    /// The UIKit value this choice maps to.
    ///
    /// 🚨 `.off` must map to `.none`, never to "leave it unset". An unset
    /// `writingToolsBehavior` INHERITS `.complete` from the trait environment,
    /// which is the whole reason the setting exists — the editor had Writing Tools
    /// nobody added and nobody chose.
    var uiBehavior: UIWritingToolsBehavior {
        switch self {
        case .off:    return .none
        case .panel:  return .limited
        case .inline: return .complete
        }
    }
}
