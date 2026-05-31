//
//  CatchlightApp.swift
//  Catchlight (iOS app target)
//
//  Application entry point. Wires the architecture-level concerns:
//    • background-sync task registration (brief §7.8)
//    • scene-phase memory security + privacy overlay (brief §5.9, §12)
//    • jailbreak warning surface (brief §5.11)
//
//  Phase 6 adds the product UI: the AppModel (built by Wiring) is injected into the
//  environment and `RootView` renders onboarding or the Dailies/Search/Sequence app.
//

import SwiftUI

@main
struct CatchlightApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = SessionController()

    /// The Phase 6 application-scope model (UI state + feature view models),
    /// composed in the single composition root.
    @State private var app = Wiring.makeAppModel()

    private let backgroundSync = BackgroundSyncCoordinator { Wiring.makeSyncEngine() }

    init() {
        // Must register before the app finishes launching.
        backgroundSync.registerLaunchHandler()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(app)
                    .environment(app.ui)
                    .environmentObject(session)

                if session.jailbreakWarning {
                    JailbreakBanner()
                }

                if session.isObscured {
                    PrivacyOverlay()   // branded blur before the app-switcher snapshot
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            session.handleScenePhase(newPhase)
            if newPhase == .background {
                backgroundSync.scheduleNext()
            }
        }
    }
}

/// Non-blocking jailbreak advisory, surfaced over the UI (brief §5.11). Kept minimal
/// and dismissible-by-ignoring; the security posture is enforced elsewhere.
struct JailbreakBanner: View {
    var body: some View {
        VStack {
            Text(JailbreakDetector.warningMessage)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.top, 8)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(JailbreakDetector.warningMessage)
    }
}

/// Branded blur shown over content when the app is inactive/backgrounded so the
/// system snapshot never captures decrypted Take content (Encryption Architecture §12.2).
struct PrivacyOverlay: View {
    var body: some View {
        ZStack {
            Color(red: 0x0F/255, green: 0x0E/255, blue: 0x0C/255)   // Ink
                .ignoresSafeArea()
            Text("catchlight")
                .font(.system(size: 28, weight: .light, design: .serif))   // Cormorant in prod
                .italic()
                .foregroundColor(Color(red: 0xF5/255, green: 0xED/255, blue: 0xD8/255))   // Catchlight
        }
    }
}

