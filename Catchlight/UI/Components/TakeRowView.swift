//
//  TakeRowView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  A single Take on the timeline: the quadrant circle (aligned to the spine) on the
//  left, the Take's first line of text on the right. Reminder Takes show their alarm
//  time as a small Fog label beside the circle. Gestures:
//    • tap circle      → open the petal fan (activity-type selector)
//    • long-press circle → designate as Obie (caller handles replacement confirm)
//    • tap text        → open the Take edit surface
//
//  All three callbacks are injected so this view is reusable across Dailies,
//  Search, and Sequence with no behavioural assumptions of its own.
//

import SwiftUI
import CatchlightCore

struct TakeRowView: View {
    let take: Take
    var onTapCircle: () -> Void = {}
    var onLongPressCircle: () -> Void = {}
    var onTapText: () -> Void = {}
    /// Optional row actions (2026-06-10): when supplied, a context menu on the
    /// TEXT column offers "Mark as done" (Tasks only) and "Delete take". The
    /// menu is deliberately NOT attached to the whole row — a row-level context
    /// menu's long-press recognizer preempts the circle's long-press (Obie
    /// designation). VoiceOver gets the same actions as named accessibility
    /// actions on the combined row element.
    var onToggleComplete: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicSize

    private var firstLine: String {
        let line = take.plainText
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled take" : trimmed
    }

    /// Composed VoiceOver label: text + status (+ progress) + reminder date.
    /// Example: "Buy milk. Task, 3 of 5 complete." or "The north star. Obie, your
    /// pinned Take. Note. Reminder set. Tomorrow at 3 PM."
    private var rowAccessibilityLabel: String {
        var parts: [String] = [firstLine, Self.statusDescription(for: take)]
        if let when = reminderLabel { parts.append(when) }
        return parts.filter { !$0.isEmpty }.joined(separator: ". ")
    }

    /// The spoken status (Obie / Task + progress / Note / reminder-set) portion of
    /// the row label, without the first line or the formatted reminder date.
    /// Internal + static so the progress/completed wording is unit-testable.
    static func statusDescription(for take: Take) -> String {
        var parts: [String] = []
        if take.isObie { parts.append("Obie, your pinned Take") }
        if take.isTask {
            if let progress = take.checklistProgress {
                parts.append("Task, \(progress.done) of \(progress.total) complete")
            } else {
                parts.append(take.isComplete ? "Task, complete" : "Task")
            }
        }
        if take.timeReminder != nil { parts.append("Reminder set") }
        if take.isNote && !take.isTask && take.timeReminder == nil { parts.append("Note") }
        return parts.joined(separator: ". ")
    }

    /// The "3 of 5" progress marker, or nil (one-item Tasks / non-Tasks show none).
    private var progressText: String? {
        guard let progress = take.checklistProgress else { return nil }
        return "\(progress.done) of \(progress.total)"
    }

    /// The Take's first-line colour. A complete Task recedes to the HiFi `.tt.done`
    /// treatment (plus the strikethrough); Obie keeps its emphasis colour.
    private var textColor: Color {
        if take.isTask && take.isComplete { return .ckTextComplete }
        return take.isObie ? .ckTextObie : .ckTextPrimary
    }

    /// Cached formatter — this label is evaluated twice per row render (body +
    /// accessibility label), and a fresh `DateFormatter` per evaluation is one
    /// of Foundation's most expensive allocations.
    private static let reminderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var reminderLabel: String? {
        guard let r = take.timeReminder else { return nil }
        return Self.reminderFormatter.string(from: r.scheduledDate)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Circle column — fixed width so every circle's centre lands on the
            // spine. Gestures are UIKit recognizers (2026-06-10): SwiftUI's
            // `LongPressGesture` (plain or simultaneous, with or without a
            // Button) never fires for synthesized presses inside this
            // ScrollView on the current runtime — while UIKit long-press
            // interactions (e.g. the context menu's) work for both real and
            // synthesized touches. `tap.require(toFail: long)` preserves the
            // original exclusive semantics.
            ZStack {
                TakeCircleView(take: take)
            }
            .frame(width: CatchlightLayout.circleDiameter,
                   height: CatchlightLayout.circleDiameter)
            .frame(minWidth: CatchlightLayout.minTouchTarget,
                   minHeight: CatchlightLayout.minTouchTarget)
            .contentShape(Rectangle())
            .overlay(
                TapAndLongPressRecognizer(
                    minimumDuration: 0.45,
                    onTap: onTapCircle,
                    onLongPress: onLongPressCircle
                )
            )
            .accessibilityElement()
            .accessibilityIdentifier("take-iris")
            .accessibilityLabel(take.isObie
                ? "Iris. Obie — your pinned Take. \(TakeCircleView.activityDescription(for: take))"
                : "Iris. \(TakeCircleView.activityDescription(for: take))")
            .accessibilityHint("Double-tap to open actions. Long press to make this your Obie.")
            // VoiceOver intercepts long-press, so expose the Obie designation as a
            // named action too. VO activation lands as a tap on the recognizer.
            .accessibilityAction(named: "Make Obie") { onLongPressCircle() }
            .accessibilityAddTraits(.isButton)

            // Text column.
            VStack(alignment: .leading, spacing: 4) {
                Text(firstLine)
                    .font(CatchlightFont.display(size: 20, relativeTo: .body))
                    .foregroundStyle(textColor)
                    // Compact 2-line preview at default sizes; let the row grow
                    // up to 4 lines at accessibility text sizes so a Take's first
                    // sentence is never cut off mid-word.
                    .lineLimit(dynamicSize.isAccessibilitySize ? 4 : 2)
                    .multilineTextAlignment(.leading)
                    .strikethrough(take.isTask && take.isComplete, color: .ckTextComplete)

                // Quiet meta line: the checklist progress marker (2+ items) and/or
                // the reminder time. New marker — HiFi v1.7 is silent on it, so it
                // matches the reminder label's scale (DM Sans caption, Secondary);
                // flagged for owner review. Stacked so neither fights the other.
                if let progressText {
                    Text(progressText)
                        .font(CatchlightFont.ui(.regular, size: 12, relativeTo: .caption))
                        .foregroundStyle(Color.ckTextSecondary)
                        .accessibilityHidden(true)   // already spoken in the row label
                }

                if let reminderLabel {
                    Text(reminderLabel)
                        .font(CatchlightFont.ui(.regular, size: 12, relativeTo: .caption))
                        .foregroundStyle(Color.ckTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: CatchlightLayout.minTouchTarget, alignment: .center)
            .contentShape(Rectangle())
            .onTapGesture { onTapText() }
            .contextMenu { rowMenuItems }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("take-row")
            .accessibilityLabel(rowAccessibilityLabel)
            .accessibilityHint("Double-tap to edit this take.")
            .accessibilityActions { rowAccessibilityActions }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var rowMenuItems: some View {
        if take.isTask, let onToggleComplete {
            Button {
                onToggleComplete()
            } label: {
                Label(take.isComplete ? "Mark as not done" : "Mark as done",
                      systemImage: take.isComplete ? "circle" : "checkmark.circle")
            }
        }
        if let onDelete {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete take", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var rowAccessibilityActions: some View {
        if take.isTask, let onToggleComplete {
            Button(take.isComplete ? "Mark as not done" : "Mark as done") { onToggleComplete() }
        }
        if let onDelete {
            Button("Delete take") { onDelete() }
        }
    }
}

/// UIKit tap + long-press recognizers bridged into SwiftUI. Exists because
/// SwiftUI's `LongPressGesture` does not fire for synthesized presses inside a
/// ScrollView on the current runtime (UIKit recognizers do — the context menu
/// proves it). `tap.require(toFail: long)` keeps the two mutually exclusive,
/// and the long press fires at `.began` (i.e. at the duration threshold while
/// the finger is still down), matching the previous SwiftUI behaviour.
private struct TapAndLongPressRecognizer: UIViewRepresentable {
    var minimumDuration: TimeInterval
    var onTap: () -> Void
    var onLongPress: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let long = UILongPressGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.longPressed(_:)))
        long.minimumPressDuration = minimumDuration
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.tapped))
        tap.require(toFail: long)
        view.addGestureRecognizer(long)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject {
        var parent: TapAndLongPressRecognizer
        init(_ parent: TapAndLongPressRecognizer) { self.parent = parent }

        @objc func tapped() { parent.onTap() }

        @objc func longPressed(_ recognizer: UILongPressGestureRecognizer) {
            if recognizer.state == .began { parent.onLongPress() }
        }
    }
}

#Preview("Rows — Night") {
    let reminder = TimeReminder(scheduledDate: .now.addingTimeInterval(86_400),
                                notificationIdentifier: "x")
    return VStack(alignment: .leading, spacing: 0) {
        TakeRowView(take: Take(blocks: [.textLine("A plain thought, nothing more.")]))
        TakeRowView(take: Take(blocks: [.checkItem("Ship the Phase 6 UI")]))
        TakeRowView(take: Take(blocks: [.checkItem("Done already", isComplete: true)]))
        TakeRowView(take: Take(blocks: [.textLine("Weekend shop"), .checkItem("milk", isComplete: true),
                                        .checkItem("eggs"), .checkItem("bread", isComplete: true),
                                        .checkItem("coffee"), .checkItem("apples")]))
        TakeRowView(take: Take(blocks: [.checkItem("wash", isComplete: true),
                                        .checkItem("fold", isComplete: true)]))
        TakeRowView(take: { var t = Take(blocks: [.textLine("Call the framer back")]); t.timeReminder = reminder; return t }())
        TakeRowView(take: Take(blocks: [.textLine("The north star")], isObie: true))
    }
    .padding()
    .background(Color.ckBackground)
    .preferredColorScheme(.dark)
}

#Preview("Rows — Daylight") {
    VStack(alignment: .leading, spacing: 0) {
        TakeRowView(take: Take(blocks: [.textLine("A plain thought.")]))
        TakeRowView(take: Take(blocks: [.checkItem("A task to do")]))
        TakeRowView(take: Take(blocks: [.textLine("The north star")], isObie: true))
    }
    .padding()
    .background(Color.ckBackground)
    .preferredColorScheme(.light)
}
