import Foundation

struct RideReminderPolicy {
    func triggerDate(for reservation: Reservation, settings: RideReminderSettings, now: Date = Date()) -> Date? {
        guard settings.enabled, settings.advanceMinutes > 0,
              reservation.departure != .distantFuture,
              reservation.departure >= now else { return nil }
        return max(now, reservation.departure.addingTimeInterval(-Double(settings.advanceMinutes) * 60))
    }
}
