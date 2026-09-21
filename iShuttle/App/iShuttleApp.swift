import SwiftUI
import UserNotifications

final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

@main
struct iShuttleApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let notificationDelegate: AppNotificationDelegate
    private let container: AppContainer

    init() {
        let notificationDelegate = AppNotificationDelegate()
        self.notificationDelegate = notificationDelegate
        UNUserNotificationCenter.current().delegate = notificationDelegate
        container = AppContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await container.refreshRideReminderAuthorization() }
        }
    }
}
