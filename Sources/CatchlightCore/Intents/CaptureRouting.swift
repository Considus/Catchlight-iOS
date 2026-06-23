//
//  CaptureRouting.swift
//  CatchlightCore — App Intents / Widgets (2026-06-23)
//
//  The capture-mode-agnostic routing contract shared by the app target, the
//  WidgetKit extension, the New Take App Intent, the Control, and the App
//  Shortcut. One enum + one URL scheme + one App-Group hand-off, so every
//  "open Catchlight and start capturing" surface funnels through the SAME
//  drain in the app (`CatchlightApp.drainPendingCapture`).
//
//  WHY this lives in Core: it is pure Foundation (no UIKit / WidgetKit), and
//  BOTH the app and the extension link CatchlightCore, so the contract can't
//  drift between processes. The widget writes a `pendingMode`, opens the app,
//  and the app reads the SAME key back out of the shared App Group.
//
//  CAPTURE-MODE-AGNOSTIC BY DESIGN (owner 2026-06-23): `text` ships now; `audio`
//  is reserved so the audio-recording widget/intent is a drop-in later (it adds
//  a case, not a new pipe). Routing never hard-codes "text".
//
//  PRIVACY: nothing here touches the encrypted store or any key material. The
//  hand-off carries only a capture MODE and, for the Siri/Shortcuts text path,
//  the text the user themselves just dictated/typed — never existing content.
//

import Foundation

public enum CaptureRouting {

    // MARK: - Capture mode

    /// What a capture surface asks the app to open into. Agnostic so new capture
    /// kinds slot in without new plumbing. `text` is live; `audio` is reserved
    /// for the audio-Take recording flow (the widget/intent exist before the
    /// recording engine does, and simply no-op until it ships).
    public enum Mode: String, Sendable, CaseIterable {
        case text
        /// Create a new Take pre-flagged as the Obie (the store's single-Obie
        /// upsert demotes the previous Obie on save). "Obie this in Catchlight".
        case obie
        case audio
    }

    // MARK: - Deep-link URL scheme (widgets use `widgetURL`)

    /// Custom URL scheme registered in the app's Info.plist (`CFBundleURLTypes`).
    /// Launcher widgets deep-link through this; the Control and Shortcuts/Siri use
    /// the App Intent directly. Both ultimately write the same pending hand-off.
    public static let urlScheme = "catchlight"

    /// Host segment identifying a "new capture" deep link: `catchlight://new?mode=text`.
    public static let captureHost = "new"

    private static let modeQueryItem = "mode"

    /// Build the deep-link a launcher widget hands to `widgetURL` / `Link`.
    public static func captureURL(_ mode: Mode) -> URL {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = captureHost
        components.queryItems = [URLQueryItem(name: modeQueryItem, value: mode.rawValue)]
        // Force-unwrap is safe: every component above is a valid literal.
        return components.url!
    }

    /// Parse an incoming `onOpenURL` URL into a capture mode, or nil if it isn't
    /// one of ours. An unknown/missing `mode` defaults to `.text` (the only mode
    /// a current build can act on) so a malformed launch still captures.
    public static func mode(from url: URL) -> Mode? {
        guard url.scheme == urlScheme, url.host == captureHost else { return nil }
        let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == modeQueryItem })?.value
        return raw.flatMap(Mode.init(rawValue:)) ?? .text
    }

    // MARK: - Cross-process hand-off (App Group)

    /// Shared suite both processes read/write. Matches the app group in
    /// `Catchlight.entitlements`.
    public static let appGroupSuite = "group.com.considus.catchlight"

    private static let pendingModeKey = "capture.pendingMode"
    private static let pendingTextKey = "capture.pendingText"

    /// A queued capture the app hasn't consumed yet. Written by an intent/widget,
    /// drained by the app once it is foregrounded AND unlocked.
    public struct Pending: Sendable, Equatable {
        public let mode: Mode
        /// Prose to pre-fill the new Take with (Siri/Shortcuts "Add a Take '…'").
        /// nil for a pure launcher (open to a blank editor).
        public let text: String?
        public init(mode: Mode, text: String? = nil) {
            self.mode = mode
            self.text = text
        }
    }

    /// Record a capture request for the app to pick up on next activation.
    /// No-op if the App Group is unavailable (the app simply opens normally).
    public static func setPending(_ pending: Pending,
                                  defaults: UserDefaults? = UserDefaults(suiteName: appGroupSuite)) {
        guard let defaults else { return }
        defaults.set(pending.mode.rawValue, forKey: pendingModeKey)
        if let text = pending.text, !text.isEmpty {
            defaults.set(text, forKey: pendingTextKey)
        } else {
            defaults.removeObject(forKey: pendingTextKey)
        }
    }

    /// Read the queued capture without consuming it.
    public static func pending(defaults: UserDefaults? = UserDefaults(suiteName: appGroupSuite)) -> Pending? {
        guard let defaults,
              let raw = defaults.string(forKey: pendingModeKey),
              let mode = Mode(rawValue: raw) else { return nil }
        return Pending(mode: mode, text: defaults.string(forKey: pendingTextKey))
    }

    /// Clear the queued capture once the app has acted on it (or chose not to).
    public static func clearPending(defaults: UserDefaults? = UserDefaults(suiteName: appGroupSuite)) {
        defaults?.removeObject(forKey: pendingModeKey)
        defaults?.removeObject(forKey: pendingTextKey)
    }
}
