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

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicSize

    private var firstLine: String {
        let line = take.bodyText
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled take" : trimmed
    }

    /// Composed VoiceOver label: text + status + reminder date.
    /// Example: "Buy milk. Task. Complete." or "The north star. Obie, your pinned Take. Note. Reminder: Tomorrow at 3 PM."
    private var rowAccessibilityLabel: String {
        var parts: [String] = [firstLine]
        if take.isObie { parts.append("Obie, your pinned Take") }
        if take.isTask { parts.append(take.isComplete ? "Task, complete" : "Task") }
        if take.timeReminder != nil { parts.append("Reminder set") }
        if take.isNote && !take.isTask && take.timeReminder == nil { parts.append("Note") }
        if let when = reminderLabel { parts.append(when) }
        return parts.joined(separator: ". ")
    }

    private var reminderLabel: String? {
        guard let r = take.timeReminder else { return nil }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: r.scheduledDate)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Circle column — fixed width so every circle's centre lands on the spine.
            ZStack {
                TakeCircleView(take: take)
            }
            .frame(width: CatchlightLayout.circleDiameter,
                   height: CatchlightLayout.circleDiameter)
            .frame(minWidth: CatchlightLayout.minTouchTarget,
                   minHeight: CatchlightLayout.minTouchTarget)
            .contentShape(Rectangle())
            .onTapGesture { onTapCircle() }
            .onLongPressGesture(minimumDuration: 0.45) { onLongPressCircle() }
            .accessibilityElement()
            .accessibilityIdentifier("take-iris")
            .accessibilityLabel(take.isObie
                ? "Iris. Obie — your pinned Take. \(TakeCircleView.activityDescription(for: take))"
                : "Iris. \(TakeCircleView.activityDescription(for: take))")
            .accessibilityHint("Double-tap to open actions. Long press to make this your Obie.")
            // VoiceOver intercepts long-press, so expose the Obie designation as a
            // named action too. The tap-to-open path stays on .onTapGesture above.
            .accessibilityAction(named: "Make Obie") { onLongPressCircle() }
            .accessibilityAddTraits(.isButton)

            // Text column.
            VStack(alignment: .leading, spacing: 4) {
                Text(firstLine)
                    .font(CatchlightFont.display(size: 20, relativeTo: .body))
                    .foregroundStyle(take.isObie ? Color.ckTextObie : Color.ckTextPrimary)
                    // Compact 2-line preview at default sizes; let the row grow
                    // up to 4 lines at accessibility text sizes so a Take's first
                    // sentence is never cut off mid-word.
                    .lineLimit(dynamicSize.isAccessibilitySize ? 4 : 2)
                    .multilineTextAlignment(.leading)
                    .strikethrough(take.isTask && take.isComplete, color: .ckTextSecondary)

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
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("take-row")
            .accessibilityLabel(rowAccessibilityLabel)
            .accessibilityHint("Double-tap to edit this take.")
        }
        .padding(.vertical, 6)
    }
}

#Preview("Rows — Night") {
    let reminder = TimeReminder(scheduledDate: .now.addingTimeInterval(86_400),
                                notificationIdentifier: "x")
    return VStack(alignment: .leading, spacing: 0) {
        TakeRowView(take: Take(bodyText: "A plain thought, nothing more."))
        TakeRowView(take: Take(bodyText: "Ship the Phase 6 UI", isTask: true))
        TakeRowView(take: Take(bodyText: "Done already", isTask: true, isComplete: true))
        TakeRowView(take: { var t = Take(bodyText: "Call the framer back"); t.timeReminder = reminder; return t }())
        TakeRowView(take: Take(bodyText: "The north star", isObie: true))
    }
    .padding()
    .background(Color.ckBackground)
    .preferredColorScheme(.dark)
}

#Preview("Rows — Daylight") {
    VStack(alignment: .leading, spacing: 0) {
        TakeRowView(take: Take(bodyText: "A plain thought."))
        TakeRowView(take: Take(bodyText: "A task to do", isTask: true))
        TakeRowView(take: Take(bodyText: "The north star", isObie: true))
    }
    .padding()
    .background(Color.ckBackground)
    .preferredColorScheme(.light)
}
