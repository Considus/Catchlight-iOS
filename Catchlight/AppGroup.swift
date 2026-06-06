//
//  AppGroup.swift
//  Catchlight (iOS app target)
//
//  Shared App Group container (Phase 5 brief §10.3, Strategic Roadmap §4). The
//  SQLite database lives here — NOT in the main app's default container — so the
//  v1.1 Share Extension, WidgetKit extension, and App Intents can reach the
//  database without a later migration. Configured at project creation; costs
//  nothing now, painful to retrofit.
//

import Foundation

public enum AppGroup {
    public static let identifier = "group.com.considus.catchlight"

    public static func containerURL() -> URL {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            // A missing App Group entitlement is a build/provisioning error, not a
            // runtime condition to handle gracefully. If you hit this, open the
            // Catchlight target in Xcode → Signing & Capabilities and confirm the
            // App Groups capability includes `group.com.considus.catchlight`.
            fatalError("App Group \(identifier) is not configured — check entitlements.")
        }
        return url
    }
}
