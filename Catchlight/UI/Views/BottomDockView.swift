//
//  BottomDockView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  The persistent navigation dock: four evenly-spaced circular icon buttons —
//  Add (+), Dailies, Search, Sequence. The dock background is identical to the
//  screen background (no elevation, border, or separator). The Add button is the
//  leftmost so the timeline spine can terminate at its horizontal centre (RootView
//  positions the spine to match `addButtonCentreX`).
//
//  Add expansion: tapping Add blooms two secondary circles — "New Take" (left) and
//  "New Sequence" (right) — the three nav buttons fade to 0, and the + rotates to ×.
//  A dim overlay (owned by RootView) also dismisses the bloom.
//

import SwiftUI
import CatchlightCore

struct BottomDockView: View {
    @Environment(UIState.self) private var ui

    var onNewTake: () -> Void
    var onNewSequence: () -> Void

    private let buttonSize: CGFloat = CatchlightLayout.minTouchTarget

    var body: some View {
        @Bindable var ui = ui
        ZStack {
            // The four primary buttons.
            HStack(spacing: 0) {
                addButton
                    .frame(maxWidth: .infinity)
                navButton(.dailies, system: "list.bullet", label: "Dailies")
                    .frame(maxWidth: .infinity)
                    .opacity(ui.isAddExpanded ? 0 : 1)
                navButton(.search, system: "magnifyingglass", label: "Search")
                    .frame(maxWidth: .infinity)
                    .opacity(ui.isAddExpanded ? 0 : 1)
                navButton(.sequence, system: "square.stack.3d.up", label: "Sequence")
                    .frame(maxWidth: .infinity)
                    .opacity(ui.isAddExpanded ? 0 : 1)
            }
            .animation(.easeInOut(duration: 0.2), value: ui.isAddExpanded)

            // Bloom options over the Add button when expanded.
            if ui.isAddExpanded {
                bloom
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.ckBackground)   // identical to screen — no elevation
    }

    // MARK: - Add button

    private var addButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                ui.isAddExpanded.toggle()
            }
        } label: {
            ZStack {
                Circle().fill(Color.ckAdd)
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.ckBackground)
                    .rotationEffect(.degrees(ui.isAddExpanded ? 45 : 0))   // + → ×
            }
            .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ui.isAddExpanded ? "Cancel" : "Add")
        .accessibilityHint(ui.isAddExpanded
                           ? "Double-tap to close the add menu."
                           : "Double-tap to create a new take or sequence.")
    }

    private var bloom: some View {
        HStack(spacing: 18) {
            bloomOption(title: "New Take", system: "square.and.pencil") {
                collapseThen(onNewTake)
            }
            bloomOption(title: "New Sequence", system: "square.stack.3d.up.badge.plus") {
                collapseThen(onNewSequence)
            }
            Spacer()
        }
        .transition(.scale(scale: 0.5, anchor: .leading).combined(with: .opacity))
        .padding(.leading, buttonSize + 24)
    }

    private func bloomOption(title: String, system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(Color.ckSurface)
                    Image(systemName: system)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color.ckAdd)
                }
                .frame(width: buttonSize, height: buttonSize)
                Text(title)
                    .font(CatchlightFont.ui(.regular, size: 11, relativeTo: .caption2))
                    .foregroundStyle(Color.ckTextSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("Double-tap to create.")
    }

    private func collapseThen(_ action: @escaping () -> Void) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            ui.isAddExpanded = false
        }
        action()
    }

    // MARK: - Nav buttons

    private func navButton(_ tab: UIState.Tab, system: String, label: String) -> some View {
        let active = ui.tab == tab
        return Button {
            ui.tab = tab
        } label: {
            Image(systemName: system)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(active ? Color.ckNavActive : Color.ckNavInactive)
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(active ? "selected" : "")
        .accessibilityHint("Double-tap to open \(label).")
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    /// The x of the Add button's centre within the dock's coordinate space, so the
    /// caller can terminate the spine there. With four equal columns + 12pt h-pad,
    /// the Add column centre is at one-eighth of the dock width (plus pad).
    static func addButtonCentreX(dockWidth: CGFloat) -> CGFloat {
        let usable = dockWidth - 24   // 12pt padding each side
        return 12 + usable / 8
    }
}

#Preview("Dock — Night") {
    VStack {
        Spacer()
        BottomDockView(onNewTake: {}, onNewSequence: {})
            .environment(UIState())
    }
    .background(Color.ckBackground)
    .preferredColorScheme(.dark)
}

#Preview("Dock — expanded") {
    let ui = UIState()
    ui.isAddExpanded = true
    return VStack {
        Spacer()
        BottomDockView(onNewTake: {}, onNewSequence: {})
            .environment(ui)
    }
    .background(Color.ckBackground)
    .preferredColorScheme(.dark)
}

#Preview("Dock — Daylight") {
    VStack {
        Spacer()
        BottomDockView(onNewTake: {}, onNewSequence: {})
            .environment(UIState())
    }
    .background(Color.ckBackground)
    .preferredColorScheme(.light)
}
