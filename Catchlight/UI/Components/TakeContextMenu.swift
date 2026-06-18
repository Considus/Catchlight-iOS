//
//  TakeContextMenu.swift
//  Catchlight (iOS app target) — long-press menu 2026-06-18
//
//  SwiftUI's `.contextMenu(preview:)` wraps any custom preview in iOS's opaque rounded
//  "platter" (background + shadow) that the SwiftUI API can't clear or reshape — so a
//  custom card+Iris preview rose on a visible panel (owner G.jpg). We want the
//  long-press to lift ONLY the Take card (its own shadow) and its Iris, no panel.
//
//  So the RESTING row's long-press is bridged to UIKit: a `UIContextMenuInteraction`
//  whose preview is a CLEAR-background hosting controller of the card+Iris composite,
//  with `UIPreviewParameters.backgroundColor = .clear` + a `visiblePath` that hugs the
//  card's rounded rect (so the lift highlight/shadow follows the card, not a box).
//  Tap-to-edit moves onto the same overlay, so the SwiftUI card beneath stays purely
//  visual; VoiceOver keeps using the row's SwiftUI accessibility actions (this overlay
//  is hidden from it). The inline editor keeps SwiftUI's default menu — long-press
//  there is rare and must not blanket the live text fields.
//

import SwiftUI
import UIKit

/// One action in the row's long-press menu (plain data so the UIKit menu can build
/// `UIAction`s — SwiftUI `Button`s can't cross into a `UIMenu`).
struct RowMenuAction {
    let title: String
    let systemImage: String
    var isDestructive: Bool = false
    let handler: () -> Void
}

struct TakeContextMenu<PreviewContent: View>: UIViewRepresentable {
    /// Menu entries, top to bottom.
    var actions: [RowMenuAction]
    /// Tap (not long-press) on the card — opens the inline editor.
    var onTap: () -> Void
    /// Width the preview composite should be laid out at (the card's measured width).
    var previewWidth: CGFloat
    /// The card's corner radius, for the lift's shadow path.
    var cardCornerRadius: CGFloat = 12
    /// The lifted composite: card + Iris, built by the caller.
    @ViewBuilder var preview: () -> PreviewContent

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        var parent: TakeContextMenu
        init(_ parent: TakeContextMenu) { self.parent = parent }

        @objc func handleTap() { parent.onTap() }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            UIContextMenuConfiguration(
                identifier: nil,
                previewProvider: { [parent] in
                    let host = UIHostingController(rootView: parent.preview())
                    host.view.backgroundColor = .clear
                    let w = parent.previewWidth > 0 ? parent.previewWidth : 320
                    host.preferredContentSize = host.sizeThatFits(
                        in: CGSize(width: w, height: .greatestFiniteMagnitude))
                    return host
                },
                actionProvider: { [parent] _ in
                    UIMenu(title: "", children: parent.actions.map { action in
                        UIAction(title: action.title,
                                 image: UIImage(systemName: action.systemImage),
                                 attributes: action.isDestructive ? .destructive : []) { _ in
                            action.handler()
                        }
                    })
                }
            )
        }

        /// Clear the platter for BOTH the lift and the dismiss: a transparent
        /// background with a shadow path hugging the card's rounded rect, so only the
        /// card (and the Iris floating above it) lift — no panel.
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
            targetedPreview(interaction)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
            targetedPreview(interaction)
        }

        private func targetedPreview(_ interaction: UIContextMenuInteraction) -> UITargetedPreview? {
            guard let view = interaction.view else { return nil }
            let params = UIPreviewParameters()
            params.backgroundColor = .clear
            // The overlay matches the card frame; hug its rounded rect so the lift's
            // shadow follows the card and nothing boxes the overhanging Iris.
            params.visiblePath = UIBezierPath(roundedRect: view.bounds,
                                              cornerRadius: parent.cardCornerRadius)
            return UITargetedPreview(view: view, parameters: params)
        }
    }
}
