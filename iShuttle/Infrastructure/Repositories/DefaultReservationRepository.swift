import Foundation

final class DefaultReservationRepository: ReservationRepository {
    private let remote: any ReservationRemoteDataSource
    private let local: any ReservationLocalDataSource

    init(remote: any ReservationRemoteDataSource, local: any ReservationLocalDataSource) {
        self.remote = remote
        self.local = local
    }

    func availableBuses(on date: Date) async throws -> [BusOption] {
        try await remote.availableBuses(on: date)
    }

    func refreshReservations() async throws -> [Reservation] {
        let remoteReservations = try await remote.currentReservations()
        let cached = await local.load()
        let merged = remoteReservations.compactMap { remoteReservation -> Reservation? in
            guard remoteReservation.isVisibleAt else { return nil }
            guard let cachedReservation = cached.first(where: { $0.hasSameIdentity(as: remoteReservation) }) else {
                return remoteReservation
            }
            var mergedReservation = remoteReservation
            mergedReservation.qrCodePayload = cachedReservation.qrCodePayload
            return mergedReservation
        }
        await local.replace(merged)
        return merged
    }

    func reservationWithQRCode(_ reservation: Reservation) async throws -> Reservation {
        let cached = await local.load()
        if let cachedReservation = cached.first(where: {
            $0.hasSameIdentity(as: reservation) && $0.isVisibleAt && !($0.qrCodePayload ?? "").isEmpty
        }) {
            return cachedReservation
        }
        let payload = try await remote.qrCode(for: reservation)
        var resolved = reservation
        resolved.qrCodePayload = payload
        await local.upsert(resolved)
        return resolved
    }

    func createReservation(for bus: BusOption, calendar: Calendar) async throws -> Reservation {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let created = try await remote.createReservation(
            resourceID: bus.id,
            date: formatter.string(from: bus.departure),
            period: bus.period
        )
        let refreshed = try? await refreshReservations()
        var result = refreshed?.first(where: { $0.id == created.id }) ?? Reservation(
            id: created.id,
            hallAppointmentDataID: created.hallAppointmentDataID,
            routeName: bus.routeName,
            departure: bus.departure,
            qrCodePayload: nil
        )
        result = Reservation(
            id: result.id,
            hallAppointmentDataID: result.hallAppointmentDataID,
            routeName: bus.routeName,
            departure: result.departure == .distantFuture ? bus.departure : result.departure,
            qrCodePayload: result.qrCodePayload
        )
        guard !result.id.isEmpty, !result.hallAppointmentDataID.isEmpty else {
            await local.upsert(result)
            return result
        }
        return (try? await reservationWithQRCode(result)) ?? result
    }

    func cancelReservation(_ reservation: Reservation) async throws {
        try await remote.cancelReservation(reservation)
        await local.remove(id: reservation.id)
        _ = try? await refreshReservations()
    }
}
