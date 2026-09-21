import Foundation
import UserNotifications

final class UserNotificationReminderScheduler: RideReminderScheduler {
    private static let identifierPrefix = "ride-reminder-"
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> RideReminderAuthorizationStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: return .authorized
        case .denied: return .denied
        default: return .notDetermined
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func pendingReservationIDs() async -> Set<String> {
        let requests = await center.pendingNotificationRequests()
        return Set(requests.compactMap { Self.reservationID(from: $0.identifier) })
    }

    func schedule(reservation: Reservation, triggerDate: Date, content: RideReminderContent) async throws {
        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.body = content.body
        notification.sound = .default
        notification.userInfo = [
            "reservationID": reservation.id,
            "departure": reservation.departure.timeIntervalSince1970,
            "triggerDate": triggerDate.timeIntervalSince1970
        ]
        let interval = triggerDate.timeIntervalSinceNow
        let trigger: UNNotificationTrigger
        if interval <= 1 {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        } else {
            let components = Calendar(identifier: .gregorian).dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: triggerDate
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
        let request = UNNotificationRequest(
            identifier: Self.identifier(for: reservation.id), content: notification, trigger: trigger
        )
        try await center.add(request)
    }

    func cancel(reservationID: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(for: reservationID)])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier(for: reservationID)])
    }

    func cancelAllPending() async {
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { Self.reservationID(from: $0) != nil }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func cancelAll() async {
        let pendingIdentifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { Self.reservationID(from: $0) != nil }
        let deliveredIdentifiers = await center.deliveredNotifications()
            .map { $0.request.identifier }
            .filter { Self.reservationID(from: $0) != nil }
        center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers)
        center.removeDeliveredNotifications(withIdentifiers: deliveredIdentifiers)
    }

    private static func identifier(for reservationID: String) -> String {
        "\(identifierPrefix)\(reservationID)"
    }

    private static func reservationID(from identifier: String) -> String? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        return String(identifier.dropFirst(identifierPrefix.count))
    }
}
