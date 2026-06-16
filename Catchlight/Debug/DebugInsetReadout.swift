//
//  DebugInsetReadout.swift
//  Catchlight (iOS app target) — DEBUG-only developer aid
//
//  Section 2b: a tiny on-device readout so the owner can verify the safe-area
//  fix (section 4) on the physical iPhone 17 / iOS 26.5.1 — the fault does NOT
//  reproduce on the iOS 18 simulator. Pinned bottom-trailing, monospaced caption.
//  It prints, live:
//    • the captured `deviceTopInset` / `deviceBottomInset` ENV values (what the
//      layout code actually applies),
//    • the RAW `safeAreaInsets.top` / `.bottom` from the window-root
//      GeometryReader (what the device reports),
//    • the COMPUTED timeline top padding + dock bottom padding.
//  If the iPhone 17 reports insets the code isn't applying, env vs raw diverge.
//
//  Visibility is gated behind a DEBUG-only Settings toggle (off by default) so it
//  never covers the UI unless the owner asks for it. The whole file is `#if DEBUG`.
//

#if DEBUG
import SwiftUI

enum DebugInsetReadoutSettings {
    /// Standard-defaults key backing the Settings → DEBUG "Inset readout" toggle.
    static let defaultsKey = "catchlight.debug.showInsetReadout"
}

/// Bottom-trailing monospaced overlay. Takes the RAW root insets as parameters
/// (read from the window-root GeometryReader where they're non-zero) and reads
/// the captured ENV values itself, so the two can be compared on-device.
struct DebugInsetReadout: View {
    let rawTop: CGFloat
    let rawBottom: CGFloat

    @Environment(\.deviceTopInset) private var envTop
    @Environment(\.deviceBottomInset) private var envBottom
    @AppStorage(DebugInsetReadoutSettings.defaultsKey) private var enabled = false

    private func f(_ v: CGFloat) -> String { String(format: "%.1f", v) }

    var body: some View {
        if enabled {
            VStack(alignment: .leading, spacing: 1) {
                Text("INSETS (DEBUG)")
                Text("env  T \(f(envTop))  B \(f(envBottom))")
                Text("raw  T \(f(rawTop))  B \(f(rawBottom))")
                Text("tl.top  \(f(envTop + CatchlightLayout.headingClearance))")
                Text("dock.bot \(f(envBottom + CatchlightLayout.dockBottomPadding))")
            }
            .font(.system(size: 9, weight: .regular, design: .monospaced))
            .foregroundStyle(Color.white)
            .padding(6)
            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 6)
            .padding(.bottom, 90)   // ride above the dock so both stay readable
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
#endif
