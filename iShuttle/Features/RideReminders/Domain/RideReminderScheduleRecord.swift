import Foundation

struct RideReminderScheduleRecord: Codable, Equatable {
    let reservationID: String
    let departure: Date
    let triggerDate: Date

    func matches(_ reservation: Reservation) -> Bool {
        reservationID == reservation.id && departure == reservation.departure
    }
}
