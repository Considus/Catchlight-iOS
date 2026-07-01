//
//  CreationStampLabel.swift
//  Catchlight (iOS app target)
//
//  A quiet "Created on DD/MM/YYYY at HH:MM" line pinned at the bottom of a Take
//  (owner 2026-07-01). Where it shows is chosen in Settings → Off / In the editor /
//  Always (`SettingsViewModel.CreationStamp`).
//
//  Format follows the phone, not a hard-coded pattern:
//    • Time  — template "jmm": `j` is the flexible hour, so it honours the device's
//              24-Hour Time setting (14:39 vs 2:39 PM) automatically.
//    • Date  — template "yyyyMMdd": the locale picks the field ORDER, so it reads
//              01/07/2026 (en_GB) or 07/01/2026 (en_US) with a 4-digit year.
//  Formatters are cached — `DateFormatter` construction is costly and a row builds
//  this on every body pass. (They snapshot `Locale.current` at first use; an app
//  relaunch picks up a locale / 24-hour change — acceptable, it's passive metadata.)
//
//  Colour is the receded "Done" grey (`ckTextComplete`) at the reminder-label size,
//  so it never competes with the Take — deliberately faint per owner. NB this is
//  below the WCAG AA text-contrast minimum (it's the same faint treatment completed
//  Tasks use); an intentional owner choice for non-essential metadata.
//

import SwiftUI

enum CreationTimestamp {
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f
    }()
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("yyyyMMdd")
        return f
    }()

    /// "Created on 01/07/2026 at 14:39" — date then time (matches the reminder
    /// label's "… at <time>" shape), locale-formatted per the notes above.
    static func text(for date: Date) -> String {
        "Created on \(dateFmt.string(from: date)) at \(timeFmt.string(from: date))"
    }
}

struct CreationStampLabel: View {
    let date: Date

    var body: some View {
        Text(CreationTimestamp.text(for: date))
            .font(CatchlightFont.ui(.regular, size: 11, relativeTo: .caption))
            .foregroundStyle(Color.ckTextComplete)
            .accessibilityLabel(CreationTimestamp.text(for: date))
    }
}
