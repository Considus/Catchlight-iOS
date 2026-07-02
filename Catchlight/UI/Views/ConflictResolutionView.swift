//
//  ConflictResolutionView.swift
//  Catchlight (iOS app target) — Phase 6 UI, Task 6.15
//
//  Sheet for resolving sync conflicts surfaced by `BackgroundSync`. The list comes
//  from `ConflictQueue.pending`; for each pair the user picks "Local" or "Cloud"
//  and confirms with "Keep this version", or sidesteps it with "Skip for now".
//
//  Selection is two-step on purpose: a single tap could resolve the wrong side
//  irreversibly. The user picks a panel (visible amber border + nudged scale),
//  THEN confirms.
//

import SwiftUI
import CatchlightCore

struct ConflictResolutionView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(ConflictQueue.self) private var queue
    @Environment(DailiesViewModel.self) private var dailies
    @Environment(\.horizontalSizeClass) private var hSize

    /// Local-vs-remote selection per conflict (keyed by the pair's local.id).
    /// `true` = keep local ("Local"); `false` = keep remote ("Cloud"); missing = no choice yet.
    @State private var selection: [UUID: Bool] = [:]

    /// When the queue empties, the empty state auto-dismisses after this delay so
    /// the user briefly sees "All caught up." rather than the sheet snapping shut.
    private let autoDismissDelay: TimeInterval = 0.6

    var body: some View {
        Group {
            if queue.pending.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Color.ckBackground)
        .presentationDragIndicator(.visible)
        .onChange(of: queue.pending.isEmpty) { _, isEmpty in
            if isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissDelay) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("All caught up.")
                .font(CatchlightFont.ui(.light, size: 17, relativeTo: .body))
                .foregroundStyle(Color.ckTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("All conflicts resolved.")
    }

    // MARK: - Conflict list

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ForEach(queue.pending, id: \.local.id) { pair in
                    conflictCard(pair)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    /// Brand heading + guidance: the shared page-heading treatment (upright
    /// Cormorant Roman, kerned, UPPER-CASE — §2.3, matching DAILIES/SETTINGS) over
    /// DM Sans Light subtext — owner 2026-07-02.
    private var header: some View {
        VStack(spacing: 16) {
            Text("SYNC CONFLICTS")
                .pageHeadingStyle()
                .accessibilityAddTraits(.isHeader)
            Text("These Takes may have been edited on different devices, so we can't resolve which to keep. Tap on the version you'd like to remain. The other will be removed.")
                .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                .foregroundStyle(Color.ckTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func conflictCard(_ pair: (local: Take, remote: Take)) -> some View {
        let chosenLocal = selection[pair.local.id]
        let stacked = shouldStack(pair: pair)

        VStack(spacing: 12) {
            if stacked {
                versionPanel(.mine, take: pair.local,
                             selected: chosenLocal == true,
                             tap: { selection[pair.local.id] = true })
                versionPanel(.theirs, take: pair.remote,
                             selected: chosenLocal == false,
                             tap: { selection[pair.local.id] = false })
            } else {
                HStack(alignment: .top, spacing: 12) {
                    versionPanel(.mine, take: pair.local,
                                 selected: chosenLocal == true,
                                 tap: { selection[pair.local.id] = true })
                    versionPanel(.theirs, take: pair.remote,
                                 selected: chosenLocal == false,
                                 tap: { selection[pair.local.id] = false })
                }
            }

            actionRow(for: pair, chosenLocal: chosenLocal)
        }
        .padding(14)
    }

    private func shouldStack(pair: (local: Take, remote: Take)) -> Bool {
        // Compact width AND both bodies long enough to need real estate.
        hSize == .compact && pair.local.plainText.count > 80 && pair.remote.plainText.count > 80
    }

    // MARK: - Version panel

    private enum Side { case mine, theirs
        var label: String { self == .mine ? "Local" : "Cloud" }
    }

    private func versionPanel(_ side: Side,
                              take: Take,
                              selected: Bool,
                              tap: @escaping () -> Void) -> some View {
        let body = take.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayBody = body.isEmpty ? "Untitled Take" : body
        return Button(action: tap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(side.label)
                        .font(CatchlightFont.ui(.medium, size: 11, relativeTo: .caption2))
                        .foregroundStyle(Color.ckTextSecondary)
                        .textCase(.uppercase)
                    Spacer()
                    TakeCircleView(take: take, diameter: 20)
                }
                Text(relativeDate(take.modifiedAt))
                    .font(CatchlightFont.ui(.regular, size: 11, relativeTo: .caption2))
                    .foregroundStyle(Color.ckTextSecondary)
                Text(displayBody)
                    .font(CatchlightFont.ui(.regular, size: 15, relativeTo: .body))
                    .foregroundStyle(Color.ckTextPrimary)
                    .lineLimit(4)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.ckSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    // Adaptive accent (ember Night / #856539 Daylight) so the 2pt
                    // selection border clears 3:1 contrast on the near-white Daylight
                    // panel — raw ckEmber failed it (owner 2026-06-29, D-027).
                    .strokeBorder(selected ? Color.ckAccent : Color.ckSpine,
                                  lineWidth: selected ? 2 : 1)
            )
            .daylightCardShadow()   // DS §4.1 — same lift as Take cards (owner 2026-07-02)
            .scaleEffect(selected ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(side.label). \(displayBody). Modified \(relativeDate(take.modifiedAt)).")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Action row

    private func actionRow(for pair: (local: Take, remote: Take),
                           chosenLocal: Bool?) -> some View {
        // The onboarding pill pair (owner 2026-07-02): primary Ember capsule +
        // secondary outline capsule, same slot as before. "Keep this version"
        // stays disabled until the user taps a card.
        HStack(spacing: 12) {
            DockPill(title: "Keep this version") {
                guard let keepLocal = chosenLocal else { return }
                do {
                    try queue.resolve(id: pair.local.id, keepLocal: keepLocal, store: dailies.store)
                    selection.removeValue(forKey: pair.local.id)
                    dailies.reload()
                } catch {
                    // ConflictQueue writes through the store directly, bypassing
                    // DailiesViewModel — route the failure through the timeline's
                    // storage-error strip; the pair stays queued so the user can retry.
                    dailies.reportStorageError("Couldn't save that resolution. Please try again.")
                }
            }
            .disabled(chosenLocal == nil)
            .opacity(chosenLocal == nil ? 0.38 : 1)

            DockPill(title: "Skip for now", secondary: true) {
                queue.skip(id: pair.local.id)
                selection.removeValue(forKey: pair.local.id)
            }
        }
        // Match the onboarding pill size/shape (44pt capsules) — the pills fill
        // this height; kept inline, NOT docked at the toolbar (owner 2026-07-02).
        .frame(height: CatchlightLayout.minTouchTarget)
    }

    // MARK: - Formatting

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private func relativeDate(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Previews

#Preview("Resolution — 2 conflicts (Night)") {
    let queue = ConflictQueue()
    let pair1 = (
        local: Take(blocks: [.textLine("Pick up groceries on the way home.")]),
        remote: Take(blocks: [.textLine("Pick up groceries and dry cleaning.")])
    )
    let pair2 = (
        local: Take(blocks: [.checkItem("Ship the Catchlight TestFlight build by Friday so the first cohort can start kicking the tyres before the long weekend.")]),
        remote: Take(blocks: [.checkItem("Ship TestFlight to the first cohort by Friday, then schedule the retro for the following Tuesday.")])
    )
    queue.enqueue([pair1, pair2])
    let store = InMemoryTakeStore()
    let dailies = DailiesViewModel(store: store)
    return Color.ckBackground.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ConflictResolutionView()
                .environment(queue)
                .environment(dailies)
        }
        .preferredColorScheme(.dark)
}

#Preview("Resolution — empty (Daylight)") {
    let queue = ConflictQueue()
    let dailies = DailiesViewModel(store: InMemoryTakeStore())
    return Color.ckBackground.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ConflictResolutionView()
                .environment(queue)
                .environment(dailies)
        }
        .preferredColorScheme(.light)
}
