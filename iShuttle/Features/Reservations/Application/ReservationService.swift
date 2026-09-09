import Foundation

@MainActor
final class ReservationService {
    private let repository: any ReservationRepository
    private let onReservationsChanged: ([Reservation]) -> Void

    init(repository: any ReservationRepository, onReservationsChanged: @escaping ([Reservation]) -> Void = { _ in }) {
        self.repository = repository
        self.onReservationsChanged = onReservationsChanged
    }

    func availableBuses(on date: Date) async throws -> [BusOption] {
        try await repository.availableBuses(on: date)
    }

    func refreshReservations() async throws -> [Reservation] {
        let values = try await repository.refreshReservations()
        onReservationsChanged(values)
        return values
    }

    func qrCodeReservation(_ reservation: Reservation) async throws -> Reservation {
        let resolved = try await repository.reservationWithQRCode(reservation)
        let values = try await repository.refreshReservations()
        onReservationsChanged(values)
        return resolved
    }

    func reserve(_ bus: BusOption, calendar: Calendar) async throws -> Reservation {
        let created = try await repository.createReservation(for: bus, calendar: calendar)
        let values = (try? await repository.refreshReservations()) ?? [created]
        onReservationsChanged(values)
        return created
    }

    func cancel(_ reservation: Reservation) async throws {
        try await repository.cancelReservation(reservation)
        let values = (try? await repository.refreshReservations()) ?? []
        onReservationsChanged(values)
    }
}
