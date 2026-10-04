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
            if queue.attentionCount == 0 {
                emptyState
            } else {
                list
            }
        }
        .background(Color.ckBackground)
        .presentationDragIndicator(.visible)
        .onChange(of: queue.attentionCount == 0) { _, isEmpty in
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
        // Audit 2026-08, V17: a label on a non-combined container is a no-op —
        // combine first so the label lands on a real element.
        .accessibilityElement(children: .combine)
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
                if !queue.unverified.isEmpty {
                    guidance("The copies of these Takes in your cloud folder didn't pass their check. Nothing changes on this phone until you choose.")
                        .padding(.horizontal, 20)
                        .padding(.top, queue.pending.isEmpty ? 0 : 8)
                    ForEach(queue.unverified, id: \.id) { item in
                        unverifiedCard(item)
                            .padding(.horizontal, 20)
                    }
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
            if !queue.pending.isEmpty {
                guidance("These Takes may have been edited on different devices, so we can't resolve which to keep. Tap on the version you'd like to remain. The other will be removed.")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 4)
    }

    private func guidance(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
            .foregroundStyle(Color.ckTextSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Unverified cloud copies (2026-09-30)

    private static let unverifiedNote = String(localized: "Didn't pass its check, and may be an older version.")
    private static let replacesNewerEdit = String(localized: "Keeping it replaces any newer edit that may exist on another device when it syncs.")

    /// Three shapes, one per owner rule: both versions (pick one), only this phone's (the newer
    /// version elsewhere can't be read), or only the cloud copy (recover a Take not on this phone).
    @ViewBuilder
    private func unverifiedCard(_ item: UnverifiedCopy) -> some View {
        VStack(spacing: 12) {
            switch (item.local, item.cloud) {
            case let (local?, cloud?):
                let chosenPhone = selection[item.id]
                HStack(alignment: .top, spacing: 12) {
                    versionPanel(.mine, take: local, selected: chosenPhone == true,
                                 tap: { selection[item.id] = true })
                    versionPanel(.theirs, take: cloud, selected: chosenPhone == false,
                                 note: Self.unverifiedNote,
                                 tap: { selection[item.id] = false })
                }
                footnote(Self.replacesNewerEdit)
                pillRow(primary: "Keep this version", enabled: chosenPhone != nil, id: item.id) {
                    if chosenPhone == true { try queue.keepPhone(id: item.id, store: dailies.store) }
                    else { try queue.keepCloud(id: item.id, store: dailies.store) }
                }
            case let (local?, nil):
                versionPanel(.mine, take: local, selected: false,
                             note: String(localized: "The newer version from another device can't be read."),
                             tap: {})
                    .allowsHitTesting(false)
                footnote(Self.replacesNewerEdit)
                pillRow(primary: "Keep this version", enabled: true, id: item.id) {
                    try queue.keepPhone(id: item.id, store: dailies.store)
                }
            case let (nil, cloud?):
                Text("Recover this Take?")
                    .font(CatchlightFont.ui(.regular, size: 15, relativeTo: .body))
                    .foregroundStyle(Color.ckTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                versionPanel(.theirs, take: cloud, selected: false,
                             note: String(localized: "It's in your cloud folder but not on this phone. It didn't pass its check, so it may be an older version."),
                             tap: {})
                    .allowsHitTesting(false)
                pillRow(primary: "Recover", enabled: true, id: item.id) {
                    try queue.keepCloud(id: item.id, store: dailies.store)
                }
            case (nil, nil):
                EmptyView()   // never produced: the engine quarantines these instead
            }
        }
        .padding(14)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
            .foregroundStyle(Color.ckTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pillRow(primary: LocalizedStringKey, enabled: Bool, id: UUID,
                         action: @escaping () throws -> Void) -> some View {
        HStack(spacing: 12) {
            DockPill(title: primary) {
                guard enabled else { return }
                do {
                    try action()
                    selection.removeValue(forKey: id)
                    dailies.reload()
                } catch {
                    dailies.reportStorageError(String(localized: "Couldn't save that choice. Please try again."))
                }
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.38)
            DockPill(title: "Skip for now", secondary: true) {
                queue.skipUnverified(id: id)
                selection.removeValue(forKey: id)
            }
        }
        .frame(minHeight: CatchlightLayout.minTouchTarget)
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
        var label: String { self == .mine ? String(localized: "Local") : String(localized: "Cloud") }
    }

    private func versionPanel(_ side: Side,
                              take: Take,
                              selected: Bool,
                              note: String? = nil,
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
                if let note {
                    Text(note)
                        .font(CatchlightFont.ui(.regular, size: 11, relativeTo: .caption2))
                        .foregroundStyle(Color.ckTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
        .accessibilityLabel("\(side.label). \(note.map { "\($0) " } ?? "")\(displayBody). Modified \(relativeDate(take.modifiedAt)).")
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
                    dailies.reportStorageError(String(localized: "Couldn't save that resolution. Please try again."))
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
        // Audit 2026-08, DT5: a MINIMUM, not a fixed height — the pills grow with
        // Dynamic Type (D-030) and a fixed slot made them overflow it.
        .frame(minHeight: CatchlightLayout.minTouchTarget)
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
