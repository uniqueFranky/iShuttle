import Foundation

@MainActor
final class RideReminderService {
    private struct RescheduleRequest {
        let reservations: [Reservation]
        let settings: RideReminderSettings
    }

    private let scheduler: any RideReminderScheduler
    private let recordRepository: any RideReminderRecordRepository
    private let now: () -> Date
    private let policy = RideReminderPolicy()
    private var pendingReschedule: RescheduleRequest?
    private var rescheduleWorker: Task<Void, Never>?

    init(
        scheduler: any RideReminderScheduler,
        recordRepository: any RideReminderRecordRepository,
        now: @escaping () -> Date = Date.init
    ) {
        self.scheduler = scheduler
        self.recordRepository = recordRepository
        self.now = now
    }

    func authorizationStatus() async -> RideReminderAuthorizationStatus {
        await scheduler.authorizationStatus()
    }

    func requestAuthorization() async -> Bool {
        await scheduler.requestAuthorization()
    }

    func rescheduleAll(reservations: [Reservation], settings: RideReminderSettings) async {
        pendingReschedule = RescheduleRequest(reservations: reservations, settings: settings)

        let worker: Task<Void, Never>
        if let rescheduleWorker {
            worker = rescheduleWorker
        } else {
            worker = Task { @MainActor [weak self] in
                await self?.drainReschedules()
            }
            rescheduleWorker = worker
        }
        await worker.value
    }

    func cancel(for reservation: Reservation) async {
        await scheduler.cancel(reservationID: reservation.id)
        var records = recordsByReservationID()
        records.removeValue(forKey: reservation.id)
        persist(records)
    }

    /// Stops future reminders while retaining records whose reminder time has
    /// already passed, so toggling the feature back on cannot repeat them.
    func disable() async {
        await stopRescheduleWorker()
        await scheduler.cancelAllPending()

        let currentDate = now()
        let records = recordsByReservationID().filter {
            $0.value.triggerDate <= currentDate && $0.value.departure >= currentDate
        }
        persist(records)
    }

    /// Removes all reminder state. This is reserved for account boundaries.
    func reset() async {
        await stopRescheduleWorker()
        await scheduler.cancelAll()
        recordRepository.removeAll()
    }

    private func stopRescheduleWorker() async {
        pendingReschedule = nil
        if let rescheduleWorker {
            rescheduleWorker.cancel()
            await rescheduleWorker.value
        }
        self.rescheduleWorker = nil
    }

    private func drainReschedules() async {
        while !Task.isCancelled, let request = pendingReschedule {
            pendingReschedule = nil
            await apply(request)
        }
        rescheduleWorker = nil
    }

    private func apply(_ request: RescheduleRequest) async {
        let currentDate = now()

        guard request.settings.enabled else {
            await reconcileDisabledState(at: currentDate)
            return
        }

        let authorization = await scheduler.authorizationStatus()
        guard !Task.isCancelled else { return }
        guard authorization == .authorized else {
            await reconcileDisabledState(at: currentDate)
            return
        }

        var records = recordsByReservationID()
        var reservationsByID: [String: Reservation] = [:]
        for reservation in request.reservations {
            reservationsByID[reservation.id] = reservation
        }

        var recordsChanged = false
        for (reservationID, record) in Array(records) {
            guard let reservation = reservationsByID[reservationID],
                  record.matches(reservation),
                  reservation.departure >= currentDate else {
                await scheduler.cancel(reservationID: reservationID)
                records.removeValue(forKey: reservationID)
                recordsChanged = true
                continue
            }
        }
        if recordsChanged { persist(records) }
        guard !Task.isCancelled else { return }

        var pendingReservationIDs = await scheduler.pendingReservationIDs()
        guard !Task.isCancelled else { return }

        for reservation in request.reservations {
            guard !Task.isCancelled else { return }
            guard let triggerDate = policy.triggerDate(
                for: reservation,
                settings: request.settings,
                now: currentDate
            ) else { continue }

            if let record = records[reservation.id] {
                // A successfully registered reminder whose target time has
                // passed is consumed, regardless of notification-center state.
                guard record.triggerDate > currentDate else { continue }

                let unchanged = datesMatch(record.triggerDate, triggerDate)
                if unchanged, pendingReservationIDs.contains(reservation.id) {
                    continue
                }

                await scheduler.cancel(reservationID: reservation.id)
                pendingReservationIDs.remove(reservation.id)
                records.removeValue(forKey: reservation.id)
                persist(records)
            }

            do {
                try await scheduler.schedule(
                    reservation: reservation,
                    triggerDate: triggerDate,
                    content: reminderContent(
                        for: reservation,
                        triggerDate: triggerDate,
                        settings: request.settings,
                        now: currentDate
                    )
                )
                records[reservation.id] = RideReminderScheduleRecord(
                    reservationID: reservation.id,
                    departure: reservation.departure,
                    triggerDate: triggerDate
                )
                pendingReservationIDs.insert(reservation.id)
                persist(records)
            } catch {
                print("[RideReminder] schedule failed for \(reservation.id): \(error)")
            }
        }
    }

    private func reconcileDisabledState(at currentDate: Date) async {
        await scheduler.cancelAllPending()
        let records = recordsByReservationID().filter {
            $0.value.triggerDate <= currentDate && $0.value.departure >= currentDate
        }
        persist(records)
    }

    private func reminderContent(
        for reservation: Reservation,
        triggerDate: Date,
        settings: RideReminderSettings,
        now currentDate: Date
    ) -> RideReminderContent {
        let route = RouteLogic.displayRouteName(reservation.routeName)
        let body: String
        if triggerDate <= currentDate.addingTimeInterval(1) {
            let remaining = max(1, Int(ceil(reservation.departure.timeIntervalSince(currentDate) / 60)))
            body = "\(route)班车将在约\(remaining)分钟后发车，请尽快前往乘车点"
        } else {
            body = "\(route)班车将在\(settings.advanceMinutes)分钟后发车"
        }
        return RideReminderContent(title: "班车提醒", body: body)
    }

    private func recordsByReservationID() -> [String: RideReminderScheduleRecord] {
        var records: [String: RideReminderScheduleRecord] = [:]
        for record in recordRepository.load() {
            records[record.reservationID] = record
        }
        return records
    }

    private func persist(_ records: [String: RideReminderScheduleRecord]) {
        let values = records.values.sorted {
            if $0.reservationID == $1.reservationID {
                return $0.departure < $1.departure
            }
            return $0.reservationID < $1.reservationID
        }
        recordRepository.save(values)
    }

    private func datesMatch(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 0.5
    }
}
