//
//  StoryboardView.swift
//  Catchlight (iOS app target) — the Storyboard (owner spec 2026-06-19)
//
//  A full-screen, chrome-light list of every Take that carries a TASK (a checkbox
//  block). Reminders alone do NOT qualify; a Take that is both task + reminder is
//  in, because it has a task (owner 2026-06-19).
//
//  The Storyboard is NOT the timeline: there is no spine, no Iris, and no dock. It is
//  just the real Take cards — `TakeCardSurface`, so they carry the SAME colour /
//  border markings and the SAME left-edge label lane (the vertical ruby "OVERDUE"
//  shows here too; the future user-label chip lane is structurally present but
//  renders nothing yet) — laid out in the user's chosen Order, capped by Preview,
//  spaced by View (the same three Settings the timeline honours). An X in the
//  top-right (the Shot List's chrome) is the only way out.
//
//  Editing: tapping a card focuses it for editing through the standard inline
//  editor (`InlineTakeEditCard`) — background masked, the keyboard editing toolbar
//  kept — but with NO Iris (owner 2026-06-19). It commits on a tap off the focused
//  card, exactly like the timeline (DailiesView's masked-background catcher). The
//  edit state is LOCAL to the Storyboard so the timeline underneath never thinks it is
//  editing.
//
//  Opened from the main dock's Angle button (∠, slot 2 — owner 2026-06-19);
//  leaving is the X, top-right (owner: "same as the shopping list").
//

import SwiftUI
import CatchlightCore

struct StoryboardView: View {
    @Environment(DailiesViewModel.self) private var vm
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Dismiss the Storyboard (the X).
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
    /// the 44pt circle) sits up in the gap. The Storyboard has no Iris, so we reclaim
    /// exactly that radius from every gap (owner 2026-06-19), keeping the perceived
    /// rhythm identical to Dailies. Floored at 0 so Compact can't go negative.
    private var storyboardGap: CGFloat {
        max(0, takeSpacing.gap - CatchlightLayout.circleDiameter / 2)
    }

    // MARK: - Edit-in-place state (LOCAL to the Storyboard)

    @State private var editDraft: Take?
    @State private var editFocusedBlockID: UUID?
    /// Whether the full-screen Shot List is presented over the editor (the
    /// keyboard toolbar's bag button), bound to the live draft so its ticks ride
    /// the same save.
    @State private var anglePresented = false

    private var isEditing: Bool { editDraft != nil }
    private var editingID: UUID? { editDraft?.id }

    /// Card-column geometry, matched to Dailies (owner 2026-06-19) so the Storyboard
    /// cards — and the heading above them — sit in the SAME column as the timeline.
    /// Dailies insets each row leading by `spineX − cardSpineInset` and trailing by
    /// 20 (DailiesView), and the card's own `cardTextLeadingPad` then lands the text
    /// at the heading's column. Full-screen, so the screen width is the container
    /// width (matches DailiesView's spineX fallback).
    private var cardLeading: CGFloat {
        CatchlightLayout.spineX(containerWidth: UIScreen.main.bounds.width)
            - CatchlightLayout.cardSpineInset
    }
    private let cardTrailing: CGFloat = 20

    // MARK: - The planned Takes

    /// Every task-bearing Take that still has work to do, in plain timeline Order — NO
    /// reordering (owner 2026-06-19: "they sit in timeline order"). Excluded: the Obie
    /// (its own pinned home is Dailies; `vm.takes` already omits it) and any Take whose
    /// tasks are ALL complete (`isComplete` — nothing left to plan, owner 2026-06-19).
    /// Sort newest-first with an id tie-break (matching the VM's deterministic order),
    /// reversed for Oldest-first.
    private var storyboardTakes: [Take] {
        let open = vm.takes.filter { $0.isTask && !$0.isComplete }
        let newestFirst = open.sorted {
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
            // under it (same as the Shot List — owner 2026-06-19).
            .safeAreaInset(edge: .top, spacing: 0) { topChrome }
            // The keyboard toolbar's bag → the full-screen Shot List on the draft.
            .fullScreenCover(isPresented: $anglePresented) { angleCover }
    }

    // MARK: - Chrome (X top-right)

    private var topChrome: some View {
        VStack(spacing: 0) {
            ZStack {
                // Explicit view heading, in the DAILIES house style (Cormorant Roman,
                // kerned caps) — owner 2026-06-19: name it as an Angle so the ∠ glyph,
                // the heading, and the concept all read the same. CENTRED at 24pt
                // (owner 2026-06-29) to match the timeline page heading; spans full
                // width so it centres on screen, with the × floated at the right edge.
                Text("STORYBOARD")
                    .font(CatchlightFont.displayRoman(size: 24, relativeTo: .title3))
                    .kerning(1.6)
                    .foregroundStyle(Color.ckTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .center)
                HStack {
                    Spacer()
                    Button(action: closeStoryboard) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.ckTextSecondary)
                            .frame(width: CatchlightLayout.minTouchTarget,
                                   height: CatchlightLayout.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("storyboard-close")
                    .accessibilityLabel("Close Storyboard")
                }
                .padding(.trailing, 12)
            }
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
            LazyVStack(spacing: storyboardGap) {
                if storyboardTakes.isEmpty {
                    emptyState
                } else {
                    ForEach(storyboardTakes) { take in
                        row(for: take)
                    }
                }
            }
            .padding(.leading, cardLeading)
            .padding(.trailing, cardTrailing)
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
                },
                onCommit: { commitEdit() }
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
                .contextMenu { rowMenu(for: take) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(TakeRowView.statusDescription(for: take))
                .accessibilityHint("Double-tap to edit this Take.")
                .accessibilityActions { rowMenu(for: take) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Nothing planned yet")
                .font(CatchlightFont.displayFixed(size: 28))
                .foregroundStyle(Color.ckTextPrimary)
                .multilineTextAlignment(.center)
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
            // Closing the Angle commits and EXITS the edit (owner 2026-06-19), so it
            // returns to the Storyboard list, not the keyboard-less focused Take.
            angle.makePresentation(editDraftBinding) {
                anglePresented = false
                commitEdit()
            }
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
    /// uses, then clear focus. Every Storyboard Take already has content (it carries a
    /// task), so there is no blank-discard case to handle.
    private func commitEdit() {
        editFocusedBlockID = nil
        guard var t = editDraft else { return }
        withAnimation(reduceMotion ? nil : UIState.fanFade) { editDraft = nil }
        guard app.ensureEntitled() else { return }
        t.removeEmptyTextBlocks()
        vm.save(t)
    }

    private func closeStoryboard() {
        if isEditing { commitEdit() }
        onClose()
    }

    // MARK: - Long-press / VoiceOver menu

    /// The Storyboard card menu — mirrors the timeline's global menu in order and
    /// wording (owner 2026-06-19): Mark done · Set as Important · Delete. ("Discard"
    /// is omitted — it only applies mid-edit.) Every Storyboard card carries a task, so
    /// "Mark done" always applies. Used for both the long-press menu and the
    /// VoiceOver actions.
    @ViewBuilder
    private func rowMenu(for take: Take) -> some View {
        Button {
            guard app.ensureEntitled() else { return }
            vm.toggleDone(take)
        } label: {
            Label(take.isMarkedDone ? "Mark Not Done" : "Mark Done",
                  systemImage: take.isMarkedDone ? "circle" : "checkmark.circle")
        }
        Button {
            guard app.ensureEntitled() else { return }
            var t = take
            t.isImportant.toggle()
            vm.save(t)
        } label: {
            // Standard Important mark, matching the Dailies long-press menu (owner 2026-06-29).
            if take.isImportant {
                Label { Text("Remove Important") } icon: { MenuGlyph.removeImportant }
            } else {
                Label { Text("Make Important") } icon: { MenuGlyph.makeImportant }
            }
        }
        Button(role: .destructive) {
            guard app.ensureEntitled() else { return }
            vm.delete(take)
        } label: {
            Label("Delete Take", systemImage: "trash")
        }
    }
}
