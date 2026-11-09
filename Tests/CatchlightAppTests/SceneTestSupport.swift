//
//  SceneTestSupport.swift
//  CatchlightTests (app module)
//
//  The trait collection a Scene token resolves against: one Scene, one appearance.
//

import UIKit
@testable import Catchlight

func sceneTraits(_ scene: CatchlightScene, _ style: UIUserInterfaceStyle) -> UITraitCollection {
    UITraitCollection { traits in
        traits.userInterfaceStyle = style
        traits[SceneTrait.self] = scene
    }
}
