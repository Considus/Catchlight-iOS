import SwiftUI
import UserNotifications

/// The line under a reminder editor's Notify toggle when Notify is on but iOS notifications
/// are off for Catchlight, so the reminder can't alert. "Turn on" is the timeline strip's own
/// action, so it does whatever the strip does.
struct NotificationsOffNote: View {
    /// Whether this reminder's Notify toggle is on.
    let notifyOn: Bool

    // Optional so the editors' previews, which have no AppModel, still render.
    @Environment(AppModel.self) private var app: AppModel?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if notifyOn, app?.notificationStatus == .denied {
            let layout = dynamicTypeSize > .large
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
            layout {
                Text("Notifications are off, so this won't notify you.")
                    .font(.caption)
                    .foregroundStyle(Color.ckTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    NotificationSettings.open()
                } label: {
                    Text("Turn on")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.ckAccent)
                        // A 44pt-tall hit area with the words on the note's first line.
                        .frame(minHeight: 44, alignment: .top)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("notifications-off-turn-on")
                .accessibilityLabel("Turn on notifications")
                .accessibilityHint("Opens iOS Settings.")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("notifications-off-note")
        }
    }
}
