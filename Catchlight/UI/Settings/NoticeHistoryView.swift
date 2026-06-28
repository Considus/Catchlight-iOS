//
//  NoticeHistoryView.swift
//  Catchlight (iOS app target)
//
//  Settings → Support → Notice History (owner 2026-06-28, D-085). A read-only, newest-first
//  list of the user-facing notices (sync / storage / conflict / quarantine) the app recorded —
//  so a banner that auto-dismissed before it was read isn't lost. Reads the content-free
//  `DiagnosticsLog`; the full log (incl. internal breadcrumbs) goes out via "Export diagnostics".
//

import SwiftUI
import CatchlightCore

struct NoticeHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [DiagnosticEntry] = []

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView("No notices yet",
                                           systemImage: "bell.slash",
                                           description: Text("Sync, storage and conflict notices will appear here."))
                } else {
                    List {
                        ForEach(entries) { entry in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: Self.icon(entry.category))
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(Self.tint(entry.category))
                                    .frame(width: 24)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.message)
                                        .font(CatchlightFont.ui(.regular, size: 15, relativeTo: .body))
                                        .foregroundStyle(Color.ckTextPrimary)
                                    Text(entry.timestamp, format: .relative(presentation: .named))
                                        .font(CatchlightFont.ui(.regular, size: 12, relativeTo: .caption))
                                        .foregroundStyle(Color.ckTextSecondary)
                                }
                            }
                            .padding(.vertical, 2)
                            .listRowBackground(Color.ckSurface)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(entry.category.displayName). \(entry.message)")
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.ckBackground)
            .navigationTitle("Notice History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if !entries.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear") {
                            DiagnosticsLog.shared.clear()
                            entries = []
                        }
                        .accessibilityIdentifier("notice-history-clear")
                    }
                }
            }
        }
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
