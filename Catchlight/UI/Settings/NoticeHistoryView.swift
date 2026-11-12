//
//  NoticeHistoryView.swift
//  Catchlight (iOS app target)
//
//  Settings → Support → Notice History. A read-only, newest-first
//  list of the user-facing notices (sync / storage / conflict / quarantine) the app recorded —
//  so a banner that auto-dismissed before it was read isn't lost. Reads the content-free
//  `DiagnosticsLog`; the full log (incl. internal breadcrumbs) goes out via "Export diagnostics".
//

import SwiftUI
import CatchlightCore

struct NoticeHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [DiagnosticEntry] = []

    /// Where Clear sits, while Mark picks between two layouts (Art Director, 2026-11-12):
    /// on its own row under the centred heading (A), or on the heading's first line with the
    /// same room kept on both sides (B). A debug build can show B with
    /// `-noticeClearLayout besideTitle`; a release build always shows A.
    enum ClearPlacement: String { case ownRow, besideTitle }
    static var clearPlacement: ClearPlacement {
        #if DEBUG
        ClearPlacement(rawValue: UserDefaults.standard.string(forKey: "noticeClearLayout") ?? "") ?? .ownRow
        #else
        .ownRow
        #endif
    }

    /// Scoped to the notices this view SHOWS (2026-07-01): the full clear() also erased the
    /// lifecycle breadcrumbs, silently emptying Export diagnostics.
    private func clearNotices() {
        DiagnosticsLog.shared.clearUserFacing()
        entries = []
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    // Custom empty state (owner 2026-06-29) so the hero line can take
                    // the onboarding hero face; mirrors the Privacy phrase layout.
                    VStack(spacing: 16) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 40, weight: .regular))
                            .foregroundStyle(Color.ckTextSecondary)
                            .accessibilityHidden(true)
                        Text("No notices yet")
                            .ckDisplay(size: 28, relativeTo: .title2)
                            .lineSpacing(CatchlightFont.tightLeading(size: 28))
                            .foregroundStyle(Color.ckTextPrimary)
                            .multilineTextAlignment(.center)
                        Text("Sync, storage and conflict notices will appear here.")
                            .ckBody(.regular, size: 15, relativeTo: .subheadline)
                            .foregroundStyle(Color.ckTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                    // Pinned near the top (padding 60 + bottom Spacer) to match the
                    // Privacy phrase explainer, rather than vertically centred.
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .combine)
                } else {
                    List {
                        if Self.clearPlacement == .ownRow {
                            // Clear on its own row under the heading, its right edge on the
                            // notice card's (Art Director's option A, 2026-11-12).
                            Section {
                                HStack {
                                    Spacer(minLength: 0)
                                    Button(action: clearNotices) {
                                        Text("Clear")
                                            .font(.body)
                                            .foregroundStyle(Color.ckAccent)
                                            .frame(minWidth: CatchlightLayout.minTouchTarget,
                                                   minHeight: CatchlightLayout.minTouchTarget, alignment: .trailing)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("notice-history-clear")
                                }
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                        Section {
                        ForEach(entries) { entry in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: Self.icon(entry.category))
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(Self.tint(entry.category))
                                    .frame(width: 24)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    // The reference code is for the export only.
                                    Text(Notice.displayText(of: entry.message))
                                        .ckBody(.regular, size: 15, relativeTo: .body)
                                        .foregroundStyle(Color.ckTextPrimary)
                                    Text(entry.timestamp, format: .relative(presentation: .named))
                                        .ckBody(.regular, size: 12, relativeTo: .caption)
                                        .monospacedDigit()   // a time: tabular digits
                                        .foregroundStyle(Color.ckTextSecondary)
                                }
                            }
                            .padding(.vertical, 2)
                            .listRowBackground(Color.ckSurface)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(entry.category.localizedName). \(Notice.displayText(of: entry.message))")
                            // Audit 2026-08, V15: the explicit label overrides the
                            // combine, dropping the relative time — carry it as the
                            // value so VoiceOver still speaks it after the message.
                            .accessibilityValue(entry.timestamp.formatted(.relative(presentation: .named)))
                        }
                        }
                    }
                    // Clear's row sits 8 below the heading, and the notices straight under it.
                    .contentMargins(.top, Self.clearPlacement == .ownRow ? 8 - CatchlightLayout.minTouchTarget / 2 + 10 : nil,
                                    for: .scrollContent)
                    .listSectionSpacing(0)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                }
            }
            .background(Color.ckBackground)
            // The page heading, with Clear on its first line while there are notices
            // (owner 2026-11-12). No Done button: dismiss by swiping down (owner 2026-06-29).
            .sheetPageHeading(LocalizedStringResource("notice-history.heading", defaultValue: "Notice History"),
                              centred: true,
                              action: entries.isEmpty || Self.clearPlacement == .ownRow ? nil
                                  : SheetHeadingAction(label: "Clear", identifier: "notice-history-clear", perform: clearNotices))
        }
        .presentationDragIndicator(.visible)
        .onAppear { entries = DiagnosticsLog.shared.userFacingEntries() }
    }

    private static func icon(_ category: DiagnosticCategory) -> String {
        switch category {
        case .sync:       return "arrow.triangle.2.circlepath"
        case .storage:    return "externaldrive.badge.exclamationmark"
        case .conflict:   return "arrow.triangle.branch"
        case .quarantine: return "lock.slash"
        case .lifecycle:  return "info.circle"
        }
    }

    private static func tint(_ category: DiagnosticCategory) -> Color {
        switch category {
        case .sync, .conflict, .lifecycle: return .ckAccent
        case .storage, .quarantine:        return .ckRuby
        }
    }
}
