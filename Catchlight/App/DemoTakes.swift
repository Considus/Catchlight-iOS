//
//  DemoTakes.swift
//  Catchlight
//
//  The believable Takes the catchlight.app motion clips are recorded on. Debug builds only:
//  `--uitesting-demo` (with `--uitesting`) seeds these in place of the two fixture Takes, and
//  `scripts/site-clips/record.sh` records the clips. The whole file is compiled out of Release.
//

#if DEBUG
import Foundation
import CatchlightCore

enum DemoTakes {
    /// The Takes of the site's drawn phone, newest first on the timeline: creation times are
    /// 1 minute apart, newest at `base`. The reminder Take is due on the first Saturday at least
    /// two days out, at 07:30, so the card never reads as overdue whatever day the clips are
    /// recorded.
    static func seed(into store: InMemoryTakeStore, base: Date) {
        let cal = Calendar.current
        let day = cal.nextDate(after: base.addingTimeInterval(86_400), matching: DateComponents(weekday: 7),
                               matchingPolicy: .nextTime) ?? base.addingTimeInterval(2 * 86_400)
        let due = cal.date(bySettingHour: 7, minute: 30, second: 0, of: day) ?? day
        let takes: [(blocks: [TakeBlock], important: Bool, reminder: TimeReminder?)] = [
            ([.textLine("Idea from the walk\nShoot the bridge at golden hour")], false, nil),
            ([.textLine("Buy film for the weekend shoot"),
              .checkItem("Colour negative, 3 rolls", isComplete: true),
              .checkItem("Lens wipes")], false, nil),
            ([.textLine("Water the studio plants")], false, nil),
            ([.checkItem("Send the gallery the final prints")], true, nil),
            ([.textLine("The eye is the lamp of the body. Might belong on the About page one day.")], false, nil),
            ([.textLine("Book the lake swim")], false,
             TimeReminder(scheduledDate: due, notificationIdentifier: "demo-lake")),
        ]
        for (i, t) in takes.enumerated() {
            try? store.upsert(Take(createdAt: base.addingTimeInterval(Double(-60 * i)),
                                   blocks: t.blocks, timeReminder: t.reminder,
                                   isImportant: t.important))
        }
    }
}
#endif
