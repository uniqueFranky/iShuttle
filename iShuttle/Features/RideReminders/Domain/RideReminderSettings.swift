import Foundation

struct RideReminderSettings: Equatable, Codable {
    var enabled: Bool
    var advanceMinutes: Int
}

enum RideReminderAuthorizationStatus: Equatable {
    case notDetermined, authorized, denied, restricted
}

struct RideReminderContent {
    let title: String
    let body: String
}

protocol RideReminderScheduler {
    func authorizationStatus() async -> RideReminderAuthorizationStatus
    func requestAuthorization() async -> Bool
    func pendingReservationIDs() async -> Set<String>
    func schedule(reservation: Reservation, triggerDate: Date, content: RideReminderContent) async throws
    func cancel(reservationID: String) async
    func cancelAllPending() async
    func cancelAll() async
}
