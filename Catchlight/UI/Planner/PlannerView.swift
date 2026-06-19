//
//  PlannerView.swift
//  Catchlight (iOS app target) — the Planner (owner spec 2026-06-19)
//
//  A full-screen, chrome-light list of every Take that carries a TASK (a checkbox
//  block). Reminders alone do NOT qualify; a Take that is both task + reminder is
//  in, because it has a task (owner 2026-06-19).
//
//  The Planner is NOT the timeline: there is no spine, no Iris, and no dock. It is
//  just the real Take cards — `TakeCardSurface`, so they carry the SAME colour /
//  border markings and the SAME left-edge label lane (the vertical ruby "OVERDUE"
//  shows here too; the future user-label chip lane is structurally present but
//  renders nothing yet) — laid out in the user's chosen Order, capped by Preview,
//  spaced by View (the same three Settings the timeline honours). An X in the
//  top-right (the List Angle's chrome) is the only way out.
//
//  Editing: tapping a card focuses it for editing through the standard inline
//  editor (`InlineTakeEditCard`) — background masked, the keyboard editing toolbar
//  kept — but with NO Iris (owner 2026-06-19). It commits on a tap off the focused
//  card, exactly like the timeline (DailiesView's masked-background catcher). The
//  edit state is LOCAL to the Planner so the timeline underneath never thinks it is
//  editing.
//
//  Entry point is still being decided by the owner; this view is reachable for
//  review via a DEBUG-only Settings row. Leaving is the X (owner: "same as the
//  shopping list").
//

import SwiftUI
import CatchlightCore

struct PlannerView: View {
    @Environment(DailiesViewModel.self) private var vm
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Dismiss the Planner (the X).
    let onClose: () -> Void

    // MARK: - View / Order / Preview (the same three settings the timeline reads)

    /// "View" — card density. Drives the inter-card spacing.
    @AppStorage(SettingsViewModel.TakeSpacing.defaultsKey)
    private var takeSpacingRaw: String = SettingsViewModel.TakeSpacing.default.rawValue
    private var takeSpacing: SettingsViewModel.TakeSpacing {
        SettingsViewModel.TakeSpacing(rawValue: takeSpacingRaw) ?? .default
    }
    /// "Order" — oldest- vs newest-first. (Preview is read inside `TakeCardSurface`.)
    @AppStorage(SettingsViewModel.TakeSort.defaultsKey)
    private var takeSortRaw: String = SettingsViewModel.TakeSort.default.rawValue
    private var takeSort: SettingsViewModel.TakeSort {
        SettingsViewModel.TakeSort(rawValue: takeSortRaw) ?? .default
    }

    /// The inter-card gap. The "View" setting's gap is tuned for Dailies, where each
    /// card's Iris straddles its top edge — the Iris's top HALF (its radius, 22pt of
    /// the 44pt circle) sits up in the gap. The Planner has no Iris, so we reclaim
    /// exactly that radius from every gap (owner 2026-06-19), keeping the perceived
    /// rhythm identical to Dailies. Floored at 0 so Compact can't go negative.
    private var plannerGap: CGFloat {
        max(0, takeSpacing.gap - CatchlightLayout.circleDiameter / 2)
    }

    /// Leading inset for the heading — the SAME column the DAILIES / SEQUENCE
    /// headings use (owner 2026-06-19), so PLANNER ANGLE lines up with the timeline
    /// headings rather than floating at a different margin. Full-screen, so the
    /// screen width is the container width (matches DailiesView's spineX fallback).
    private var headingLeading: CGFloat {
        CatchlightLayout.spineX(containerWidth: UIScreen.main.bounds.width)
            - CatchlightLayout.cardSpineInset + CatchlightLayout.cardTextLeadingPad
    }

    // MARK: - Edit-in-place state (LOCAL to the Planner)

    @State private var editDraft: Take?
    @State private var editFocusedBlockID: UUID?
    /// Whether the full-screen List Angle is presented over the editor (the
    /// keyboard toolbar's bag button), bound to the live draft so its ticks ride
    /// the same save.
    @State private var anglePresented = false

    private var isEditing: Bool { editDraft != nil }
    private var editingID: UUID? { editDraft?.id }

    private let cardHInset: CGFloat = 16

    // MARK: - The planned Takes

    /// Every task-bearing Take (the Obie included when it has a task), in the user's
    /// chosen Order. We sort newest-first with an id tie-break — matching the VM's
    /// deterministic order — then reverse for Oldest-first. The Obie is folded in by
    /// the same order (the Planner is a flat list — no pinning, owner 2026-06-19).
    private var plannedTakes: [Take] {
        var all = vm.takes
        if let obie = vm.obie { all.append(obie) }
        let tasks = all.filter { $0.isTask }
        let newestFirst = tasks.sorted {
            $0.createdAt != $1.createdAt
                ? $0.createdAt > $1.createdAt
                : $0.id.uuidString > $1.id.uuidString
        }
        return takeSort == .oldestFirst ? newestFirst.reversed() : newestFirst
    }

    private var editDraftBinding: Binding<Take> {
        Binding(get: { editDraft ?? Take() }, set: { editDraft = $0 })
    }

    // MARK: - Body

    var body: some View {
        list
            .background(Color.ckBackground.ignoresSafeArea())
            // Dailies-style chrome: an opaque X-row + a 12pt fade, content scrolling
            // under it (same as the List Angle — owner 2026-06-19).
            .safeAreaInset(edge: .top, spacing: 0) { topChrome }
            // The keyboard toolbar's bag → the full-screen List Angle on the draft.
            .fullScreenCover(isPresented: $anglePresented) { angleCover }
    }

    // MARK: - Chrome (X top-right)

    private var topChrome: some View {
        VStack(spacing: 0) {
            HStack {
                // Explicit view heading, in the DAILIES house style (Cormorant Roman,
                // kerned caps) — owner 2026-06-19: name it as an Angle so the ∠ glyph,
                // the heading, and the concept all read the same.
                Text("PLANNER ANGLE")
                    .font(CatchlightFont.displayRoman(size: 20, relativeTo: .title3))
                    .kerning(1.6)
                    .foregroundStyle(Color.ckTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: closePlanner) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.ckTextSecondary)
                        .frame(width: CatchlightLayout.minTouchTarget,
                               height: CatchlightLayout.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("planner-close")
                .accessibilityLabel("Close planner")
            }
            .padding(.leading, headingLeading)
            .padding(.trailing, 12)
            .padding(.top, 4)
            .background(Color.ckBackground)
            LinearGradient(
                colors: [Color.ckBackground, Color.ckBackground.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 12)
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: plannerGap) {
                if plannedTakes.isEmpty {
                    emptyState
                } else {
                    ForEach(plannedTakes) { take in
                        row(for: take)
                    }
                }
            }
            .padding(.horizontal, cardHInset)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Commit catcher: a tap in the empty gaps off the focused Take commits
            // (masked cards commit via their own tap handler). A `.background` (not
            // an overlay) so the focused editor and the masked rows still win
            // hit-testing — mirrors DailiesView's masked-background catcher.
            .background {
                if isEditing {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { commitEdit() }
                        .accessibilityLabel("Save and close")
                        .accessibilityHint("Double-tap to save this Take and stop editing.")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func row(for take: Take) -> some View {
        if editingID == take.id {
            // The focused editor — no Iris, keyboard toolbar kept.
            InlineTakeEditCard(
                draft: editDraftBinding,
                focusedBlockID: $editFocusedBlockID,
                onOpenAngle: {
                    editFocusedBlockID = nil   // drop the keyboard before the cover
                    anglePresented = true
                }
            )
        } else {
            // A read-only card. Tapping it begins editing; tapping it while ANOTHER
            // Take is focused commits that edit (matches the timeline).
            TakeCardSurface(take: take)
                .opacity(isEditing ? 0.12 : 1)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isEditing { commitEdit() } else { beginEdit(take) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(TakeRowView.statusDescription(for: take))
                .accessibilityHint("Double-tap to edit this Take.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Nothing to plan yet")
                .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                .foregroundStyle(Color.ckTextPrimary)
            Text("Takes with a task appear here.")
                .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .callout))
                .foregroundStyle(Color.ckTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Angle cover (the keyboard bag button)

    @ViewBuilder
    private var angleCover: some View {
        if let angle = AngleRegistry.applicable(to: editDraft ?? Take()).first {
            angle.makePresentation(editDraftBinding) { anglePresented = false }
        } else {
            Color.ckBackground.ignoresSafeArea().onAppear { anglePresented = false }
        }
    }

    // MARK: - Edit lifecycle

    private func beginEdit(_ take: Take) {
        guard app.ensureEntitled() else { return }
        var t = take
        if t.blocks.isEmpty { t.blocks = [.text(TextBlock(text: ""))] }
        editFocusedBlockID = t.blocks.last?.id
        withAnimation(reduceMotion ? nil : UIState.fanFade) { editDraft = t }
    }

    /// Commit the focused edit through the same `vm.save` chokepoint the timeline
    /// uses, then clear focus. Every Planner Take already has content (it carries a
    /// task), so there is no blank-discard case to handle.
    private func commitEdit() {
        editFocusedBlockID = nil
        guard var t = editDraft else { return }
        withAnimation(reduceMotion ? nil : UIState.fanFade) { editDraft = nil }
        guard app.ensureEntitled() else { return }
        t.removeEmptyTextBlocks()
        vm.save(t)
    }

    private func closePlanner() {
        if isEditing { commitEdit() }
        onClose()
    }
}
