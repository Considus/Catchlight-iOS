//
//  AppIconChoice.swift
//  Catchlight
//
//  Settings → Appearance → App icon: one icon per Scene, picked by name, apart from the
//  Scene itself (redesign spec R16b). Cobalt is the main icon, and the App Store always
//  shows it. The icons are the Icon Composer files in Catchlight/Resources, listed as
//  alternates by `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in project.yml.
//
//  iOS keeps the choice (`alternateIconName`), so nothing is stored here, and iOS shows
//  its own alert when the icon changes.
//

import UIKit

enum AppIconChoice {

    /// The bundle's alternate icon name for `scene`, or nil for Cobalt, the main icon.
    static func iconName(for scene: CatchlightScene) -> String? {
        switch scene {
        case .cobalt: return nil
        case .graphite: return "AppIcon-Graphite"
        case .onyx: return "AppIcon-Onyx"
        case .jade: return "AppIcon-Jade"
        case .tanzanite: return "AppIcon-Tanzanite"
        }
    }

    /// The Scene whose icon is `iconName`. An unknown name reads as Cobalt.
    static func scene(forIconName iconName: String?) -> CatchlightScene {
        CatchlightScene.allCases.first { self.iconName(for: $0) == iconName } ?? .default
    }

    /// The icon on the Home Screen now.
    @MainActor static var current: CatchlightScene {
        scene(forIconName: UIApplication.shared.alternateIconName)
    }

    /// Ask iOS to switch to `scene`'s icon. Returns whether that icon is now in use;
    /// on failure the Home Screen keeps the icon it had.
    @MainActor static func select(_ scene: CatchlightScene) async -> Bool {
        let app = UIApplication.shared
        let name = iconName(for: scene)
        guard app.alternateIconName != name else { return true }
        guard app.supportsAlternateIcons else { return false }
        do {
            try await app.setAlternateIconName(name)
            return true
        } catch {
            return false
        }
    }
}
