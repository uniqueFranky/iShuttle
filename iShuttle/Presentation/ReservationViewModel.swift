import Foundation
import Combine

@MainActor
final class ReservationViewModel: ObservableObject {
    @Published private(set) var buses: [BusOption] = []
    @Published private(set) var reservations: [Reservation] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service: ReservationService
    private let onAuthenticationRequired: () -> Void

    init(
        service: ReservationService,
        onAuthenticationRequired: @escaping () -> Void
    ) {
        self.service = service
        self.onAuthenticationRequired = onAuthenticationRequired
    }

    func refresh(on date: Date, calendar: Calendar, reportErrors: Bool = true) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await service.availableBuses(on: date)
            let selectedDay = calendar.startOfDay(for: date)
            let today = calendar.startOfDay(for: Date())
            buses = fetched.filter { bus in
                let busDay = calendar.startOfDay(for: bus.departure)
                guard busDay == selectedDay else { return false }
                return selectedDay != today || bus.departure >= Date()
            }
            reservations = try await service.refreshReservations()
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            handle(error, reportErrors: reportErrors)
        }
    }

    func refreshReservations(reportErrors: Bool = true) async {
        isLoading = true
        defer { isLoading = false }
        do {
            reservations = try await service.refreshReservations()
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            handle(error, reportErrors: reportErrors)
        }
    }

    func reserve(_ bus: BusOption, calendar: Calendar) async {
        do {
            _ = try await service.reserve(bus, calendar: calendar)
            reservations = (try? await service.refreshReservations()) ?? reservations
        } catch {
            handle(error)
        }
    }

    func cancel(_ reservation: Reservation) async {
        do {
            try await service.cancel(reservation)
            reservations = (try? await service.refreshReservations()) ?? []
        } catch {
            handle(error)
        }
    }

    private func handle(_ error: Error, reportErrors: Bool = true) {
        if case APIError.authenticationRequired = error {
            onAuthenticationRequired()
        } else if reportErrors {
            errorMessage = error.localizedDescription
        }
    }
}
