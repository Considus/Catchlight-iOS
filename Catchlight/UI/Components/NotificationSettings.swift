import SwiftUI
import UIKit

/// The one action behind every "Turn on" for notifications: the timeline's
/// reminders-silenced strip and the reminder editors' note both call it, so they can't drift.
enum NotificationSettings {
    @MainActor
    static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
