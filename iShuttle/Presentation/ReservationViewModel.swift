import Foundation
import Combine

@MainActor
final class ReservationViewModel: ObservableObject {
    @Published private(set) var buses: [BusOption] = []
    @Published private(set) var reservations: [Reservation] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api: ReservationAPI
    private let store: ReservationStore
    private let onAuthenticationRequired: () -> Void

    init(
        api: ReservationAPI,
        store: ReservationStore,
        onAuthenticationRequired: @escaping () -> Void
    ) {
        self.api = api
        self.store = store
        self.onAuthenticationRequired = onAuthenticationRequired
    }

    func refresh(on date: Date, calendar: Calendar, reportErrors: Bool = true) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await api.availableBuses(on: date)
            let selectedDay = calendar.startOfDay(for: date)
            let today = calendar.startOfDay(for: Date())
            buses = fetched.filter { bus in
                let busDay = calendar.startOfDay(for: bus.departure)
                guard busDay == selectedDay else { return false }
                return selectedDay != today || bus.departure >= Date()
            }
            reservations = try await api.currentReservations()
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
            reservations = try await api.currentReservations()
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
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            let reservation = try await api.createReservation(
                resourceID: bus.id,
                date: formatter.string(from: bus.departure),
                period: bus.period
            )
            var completeReservation = reservation
            if completeReservation.hallAppointmentDataID.isEmpty {
                await refreshReservations(reportErrors: false)
                if let queried = reservations.first(where: { $0.id == reservation.id }) {
                    completeReservation = queried
                }
            }
            // 预约接口成功后即视为预约完成。二维码接口可能因服务端延迟暂时失败，
            // 首页会在后续刷新时再次获取，不应把预约成功误报为失败。
            let code: String?
            if completeReservation.id.isEmpty || completeReservation.hallAppointmentDataID.isEmpty {
                code = nil
            } else {
                do {
                    code = try await api.qrCode(for: completeReservation)
                } catch APIError.authenticationRequired {
                    onAuthenticationRequired()
                    code = nil
                } catch {
                    code = nil
                }
            }
            let saved = Reservation(
                id: reservation.id,
                hallAppointmentDataID: completeReservation.hallAppointmentDataID,
                routeName: bus.routeName,
                departure: bus.departure,
                qrCodePayload: code
            )
            if !reservation.id.isEmpty {
                await store.upsert(saved)
            }
            await refresh(on: bus.departure, calendar: calendar, reportErrors: false)
        } catch {
            handle(error)
        }
    }

    func cancel(_ reservation: Reservation) async {
        do {
            try await api.cancelReservation(reservation)
            // 先更新当前列表，避免等待网络刷新期间继续显示已取消的预约。
            reservations.removeAll { $0.id == reservation.id }
            await store.remove(id: reservation.id)

            // 取消状态在服务端落库存在短暂延迟，稍后再查询，避免旧状态把预约重新带回来。
            try? await Task.sleep(for: .milliseconds(800))
            await refreshReservations()
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
