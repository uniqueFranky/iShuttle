import Foundation

struct RideReminderPreference: Codable, Equatable {
    let reservationID: String
    let departure: Date
    let advanceMinutes: Int

    func matches(_ reservation: Reservation) -> Bool {
        reservationID == reservation.id && departure == reservation.departure
    }
}
