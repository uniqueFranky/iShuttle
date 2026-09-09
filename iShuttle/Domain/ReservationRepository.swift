import Foundation

protocol ReservationRemoteDataSource {
    func availableBuses(on date: Date) async throws -> [BusOption]
    func currentReservations() async throws -> [Reservation]
    func qrCode(for reservation: Reservation) async throws -> String
    func createReservation(resourceID: String, date: String, period: Int) async throws -> Reservation
    func cancelReservation(_ reservation: Reservation) async throws
}

protocol ReservationLocalDataSource {
    func load() async -> [Reservation]
    func all() async -> [Reservation]
    func upsert(_ reservation: Reservation) async
    func remove(id: String) async
    func replace(_ reservations: [Reservation]) async
}

protocol ReservationRepository {
    func availableBuses(on date: Date) async throws -> [BusOption]
    func refreshReservations() async throws -> [Reservation]
    func reservationWithQRCode(_ reservation: Reservation) async throws -> Reservation
    func createReservation(for bus: BusOption, calendar: Calendar) async throws -> Reservation
    func cancelReservation(_ reservation: Reservation) async throws
}

extension Reservation {
    func hasSameIdentity(as other: Reservation) -> Bool {
        id == other.id && hallAppointmentDataID == other.hallAppointmentDataID
    }
}
