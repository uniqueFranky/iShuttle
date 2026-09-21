import XCTest
@testable import iShuttle

@MainActor
final class RideReminderServiceTests: XCTestCase {
    private let settings = RideReminderSettings(enabled: true, advanceMinutes: 10)

    func testRepeatedRefreshKeepsExistingFutureReminder() async {
        let now = date(hour: 12)
        let scheduler = ReminderSchedulerSpy()
        let repository = InMemoryReminderRecordRepository()
        let service = makeService(scheduler: scheduler, repository: repository, now: now)
        let reservation = makeReservation(departure: date(hour: 13))

        await service.rescheduleAll(reservations: [reservation], settings: settings)
        await service.rescheduleAll(reservations: [reservation], settings: settings)

        XCTAssertEqual(scheduler.scheduleAttempts, 1)
        XCTAssertEqual(repository.records.count, 1)
        XCTAssertEqual(repository.records.first?.triggerDate, date(hour: 12, minute: 50))
    }

    func testRefreshAfterTriggerDoesNotScheduleImmediateReminderAgain() async {
        var currentDate = date(hour: 12, minute: 40)
        let scheduler = ReminderSchedulerSpy()
        let repository = InMemoryReminderRecordRepository()
        let service = makeService(scheduler: scheduler, repository: repository) { currentDate }
        let reservation = makeReservation(departure: date(hour: 13))

        await service.rescheduleAll(reservations: [reservation], settings: settings)
        currentDate = date(hour: 12, minute: 51)
        scheduler.pendingIDs.removeAll() // Simulate a delivered notification.
        await service.rescheduleAll(reservations: [reservation], settings: settings)

        XCTAssertEqual(scheduler.scheduleAttempts, 1)
        XCTAssertEqual(repository.records.count, 1)
    }

    func testRepeatedRefreshInsideReminderWindowSchedulesImmediateReminderOnce() async {
        let now = date(hour: 12, minute: 55)
        let scheduler = ReminderSchedulerSpy()
        let repository = InMemoryReminderRecordRepository()
        let service = makeService(scheduler: scheduler, repository: repository, now: now)
        let reservation = makeReservation(departure: date(hour: 13))

        await service.rescheduleAll(reservations: [reservation], settings: settings)
        scheduler.pendingIDs.removeAll() // The one-second notification was delivered.
        await service.rescheduleAll(reservations: [reservation], settings: settings)

        XCTAssertEqual(scheduler.scheduleAttempts, 1)
        XCTAssertEqual(repository.records.first?.triggerDate, now)
    }

    func testPersistedRecordPreventsRepeatAfterServiceRecreation() async {
        var currentDate = date(hour: 12, minute: 40)
        let scheduler = ReminderSchedulerSpy()
        let repository = InMemoryReminderRecordRepository()
        let reservation = makeReservation(departure: date(hour: 13))

        var service = makeService(scheduler: scheduler, repository: repository) { currentDate }
        await service.rescheduleAll(reservations: [reservation], settings: settings)

        currentDate = date(hour: 12, minute: 51)
        scheduler.pendingIDs.removeAll()
        service = makeService(scheduler: scheduler, repository: repository) { currentDate }
        await service.rescheduleAll(reservations: [reservation], settings: settings)

        XCTAssertEqual(scheduler.scheduleAttempts, 1)
    }

    func testMissingFutureSystemNotificationIsRestored() async {
        let now = date(hour: 12)
        let scheduler = ReminderSchedulerSpy()
        let repository = InMemoryReminderRecordRepository()
        let service = makeService(scheduler: scheduler, repository: repository, now: now)
        let reservation = makeReservation(departure: date(hour: 13))

        await service.rescheduleAll(reservations: [reservation], settings: settings)
        scheduler.pendingIDs.removeAll()
        await service.rescheduleAll(reservations: [reservation], settings: settings)

        XCTAssertEqual(scheduler.scheduleAttempts, 2)
        XCTAssertEqual(scheduler.cancelledIDs, [reservation.id])
    }

    func testChangingAdvanceTimeBeforeTriggerReplacesReminder() async {
        let now = date(hour: 12)
        let scheduler = ReminderSchedulerSpy()
        let repository = InMemoryReminderRecordRepository()
        let service = makeService(scheduler: scheduler, repository: repository, now: now)
        let reservation = makeReservation(departure: date(hour: 13))

        await service.rescheduleAll(reservations: [reservation], settings: settings)
        await service.rescheduleAll(
            reservations: [reservation],
            settings: RideReminderSettings(enabled: true, advanceMinutes: 20)
        )

        XCTAssertEqual(scheduler.scheduleAttempts, 2)
        XCTAssertEqual(scheduler.cancelledIDs, [reservation.id])
        XCTAssertEqual(repository.records.first?.triggerDate, date(hour: 12, minute: 40))
    }

    func testChangingAdvanceTimeAfterTriggerDoesNotRepeatReminder() async {
        var currentDate = date(hour: 12)
        let scheduler = ReminderSchedulerSpy()
        let repository = InMemoryReminderRecordRepository()
        let service = makeService(scheduler: scheduler, repository: repository) { currentDate }
        let reservation = makeReservation(departure: date(hour: 13))

        await service.rescheduleAll(reservations: [reservation], settings: settings)
        currentDate = date(hour: 12, minute: 51)
        scheduler.pendingIDs.removeAll()
        await service.rescheduleAll(
            reservations: [reservation],
            settings: RideReminderSettings(enabled: true, advanceMinutes: 20)
        )

        XCTAssertEqual(scheduler.scheduleAttempts, 1)
    }

    func testReservationPreferenceOverridesGlobalAdvanceTime() async {
        let now = date(hour: 12)
        let scheduler = ReminderSchedulerSpy()
        let repository = InMemoryReminderRecordRepository()
        let preferenceRepository = InMemoryReminderPreferenceRepository()
        let service = makeService(
            scheduler: scheduler,
            repository: repository,
            preferenceRepository: preferenceRepository,
            now: now
        )
        let reservation = makeReservation(departure: date(hour: 13))

        await service.updatePreference(
            advanceMinutes: 20,
            for: reservation,
            reservations: [reservation],
            settings: settings
        )

        XCTAssertEqual(scheduler.scheduled.last?.triggerDate, date(hour: 12, minute: 40))
        XCTAssertEqual(service.preference(for: reservation)?.advanceMinutes, 20)
    }

    func testChangingGlobalTimeOnlyReplacesInheritedReminder() async {
        let now = date(hour: 12)
        let scheduler = ReminderSchedulerSpy()
        let repository = InMemoryReminderRecordRepository()
        let preferenceRepository = InMemoryReminderPreferenceRepository()
        let service = makeService(
            scheduler: scheduler,
            repository: repository,
            preferenceRepository: preferenceRepository,
            now: now
        )
        let inherited = makeReservation(id: "inherited", departure: date(hour: 13))
        let customized = makeReservation(id: "customized", departure: date(hour: 14))

        await service.updatePreference(
            advanceMinutes: 20,
            for: customized,
            reservations: [inherited, customized],
            settings: settings
        )
        await service.rescheduleAll(
            reservations: [inherited, customized],
            settings: RideReminderSettings(enabled: true, advanceMinutes: 15)
        )

        XCTAssertEqual(scheduler.scheduleAttempts, 3)
        XCTAssertEqual(scheduler.cancelledIDs, [inherited.id])
        XCTAssertEqual(
            scheduler.scheduled.last { $0.reservation.id == inherited.id }?.triggerDate,
            date(hour: 12, minute: 45)
        )
        XCTAssertEqual(
            scheduler.scheduled.last { $0.reservation.id == customized.id }?.triggerDate,
            date(hour: 13, minute: 40)
        )
    }

    func testClearingPreferenceReturnsReservationToGlobalTime() async {
        let now = date(hour: 12)
        let scheduler = ReminderSchedulerSpy()
        let repository = InMemoryReminderRecordRepository()
        let preferenceRepository = InMemoryReminderPreferenceRepository()
        let service = makeService(
            scheduler: scheduler,
            repository: repository,
            preferenceRepository: preferenceRepository,
            now: now
        )
        let reservation = makeReservation(departure: date(hour: 13))

        await service.updatePreference(
            advanceMinutes: 20,
            for: reservation,
            reservations: [reservation],
            settings: settings
        )
        await service.updatePreference(
            advanceMinutes: nil,
            for: reservation,
            reservations: [reservation],
            settings: settings
        )

        XCTAssertNil(service.preference(for: reservation))
        XCTAssertEqual(scheduler.scheduleAttempts, 2)
        XCTAssertEqual(scheduler.scheduled.last?.triggerDate, date(hour: 12, minute: 50))
    }

    func testDisabledRemindersPreserveReservationPreference() async {
        let now = date(hour: 12)
        let scheduler = ReminderSchedulerSpy()
        let repository = InMemoryReminderRecordRepository()
        let preferenceRepository = InMemoryReminderPreferenceRepository()
        let service = makeService(
            scheduler: scheduler,
            repository: repository,
            preferenceRepository: preferenceRepository,
            now: now
        )
        let reservation = makeReservation(departure: date(hour: 13))

        await service.updatePreference(
            advanceMinutes: 20,
            for: reservation,
            reservations: [reservation],
            settings: RideReminderSettings(enabled: false, advanceMinutes: 10)
        )

        XCTAssertEqual(service.preference(for: reservation)?.advanceMinutes, 20)
        XCTAssertEqual(scheduler.scheduleAttempts, 0)
    }

    func testRemovedReservationCleansPreference() async {
        let now = date(hour: 12)
        let scheduler = ReminderSchedulerSpy()
        let repository = InMemoryReminderRecordRepository()
        let preferenceRepository = InMemoryReminderPreferenceRepository()
        let service = makeService(
            scheduler: scheduler,
            repository: repository,
            preferenceRepository: preferenceRepository,
            now: now
        )
        let reservation = makeReservation(departure: date(hour: 13))

        await service.updatePreference(
            advanceMinutes: 20,
            for: reservation,
            reservations: [reservation],
            settings: settings
        )
        await service.rescheduleAll(
            reservations: [],
            settings: settings,
            removesStalePreferences: true
        )

        XCTAssertTrue(preferenceRepository.preferences.isEmpty)
    }

    func testNonAuthoritativeEmptyCachePreservesPreference() async {
        let now = date(hour: 12)
        let scheduler = ReminderSchedulerSpy()
        let repository = InMemoryReminderRecordRepository()
        let preferenceRepository = InMemoryReminderPreferenceRepository()
        let service = makeService(
            scheduler: scheduler,
            repository: repository,
            preferenceRepository: preferenceRepository,
            now: now
        )
        let reservation = makeReservation(departure: date(hour: 13))

        await service.updatePreference(
            advanceMinutes: 20,
            for: reservation,
            reservations: [reservation],
            settings: settings
        )
        await service.rescheduleAll(reservations: [], settings: settings)

        XCTAssertEqual(service.preference(for: reservation)?.advanceMinutes, 20)
    }

    func testReusedReservationIDDoesNotInheritOldPreference() async {
        let now = date(hour: 12)
        let scheduler = ReminderSchedulerSpy()
        let repository = InMemoryReminderRecordRepository()
        let preferenceRepository = InMemoryReminderPreferenceRepository()
        let service = makeService(
            scheduler: scheduler,
            repository: repository,
            preferenceRepository: preferenceRepository,
            now: now
        )
        let original = makeReservation(departure: date(hour: 13))
        let replacement = makeReservation(departure: date(hour: 14))

        await service.updatePreference(
            advanceMinutes: 20,
            for: original,
            reservations: [original],
            settings: settings
        )
        await service.rescheduleAll(
            reservations: [replacement],
            settings: settings,
            removesStalePreferences: true
        )

        XCTAssertNil(service.preference(for: replacement))
        XCTAssertEqual(scheduler.scheduled.last?.triggerDate, date(hour: 13, minute: 50))
    }

    func testRemovedReservationCleansNotificationAndRecord() async {
        let now = date(hour: 12)
        let scheduler = ReminderSchedulerSpy()
        let repository = InMemoryReminderRecordRepository()
        let service = makeService(scheduler: scheduler, repository: repository, now: now)
        let reservation = makeReservation(departure: date(hour: 13))

        await service.rescheduleAll(reservations: [reservation], settings: settings)
        await service.rescheduleAll(reservations: [], settings: settings)

        XCTAssertEqual(scheduler.cancelledIDs, [reservation.id])
        XCTAssertTrue(repository.records.isEmpty)
    }

    func testSameReservationIDWithNewDepartureCreatesNewReminder() async {
        let now = date(hour: 12)
        let scheduler = ReminderSchedulerSpy()
        let repository = InMemoryReminderRecordRepository()
        let service = makeService(scheduler: scheduler, repository: repository, now: now)
        let original = makeReservation(departure: date(hour: 13))
        let updated = makeReservation(departure: date(hour: 14))

        await service.rescheduleAll(reservations: [original], settings: settings)
        await service.rescheduleAll(reservations: [updated], settings: settings)

        XCTAssertEqual(scheduler.scheduleAttempts, 2)
        XCTAssertEqual(repository.records.first?.departure, updated.departure)
    }

    func testScheduleFailureDoesNotPersistRecordAndCanRetry() async {
        let now = date(hour: 12)
        let scheduler = ReminderSchedulerSpy()
        scheduler.shouldFail = true
        let repository = InMemoryReminderRecordRepository()
        let service = makeService(scheduler: scheduler, repository: repository, now: now)
        let reservation = makeReservation(departure: date(hour: 13))

        await service.rescheduleAll(reservations: [reservation], settings: settings)
        XCTAssertTrue(repository.records.isEmpty)

        scheduler.shouldFail = false
        await service.rescheduleAll(reservations: [reservation], settings: settings)

        XCTAssertEqual(scheduler.scheduleAttempts, 2)
        XCTAssertEqual(repository.records.count, 1)
    }

    func testDisableDropsFuturePlanButKeepsConsumedPlan() async {
        var currentDate = date(hour: 12)
        let scheduler = ReminderSchedulerSpy()
        let repository = InMemoryReminderRecordRepository()
        let service = makeService(scheduler: scheduler, repository: repository) { currentDate }
        let reservation = makeReservation(departure: date(hour: 13))

        await service.rescheduleAll(reservations: [reservation], settings: settings)
        await service.disable()
        XCTAssertTrue(repository.records.isEmpty)

        await service.rescheduleAll(reservations: [reservation], settings: settings)
        currentDate = date(hour: 12, minute: 51)
        await service.disable()

        XCTAssertEqual(repository.records.count, 1)
    }

    func testResetClearsNotificationsAndPersistedState() async {
        let now = date(hour: 12)
        let scheduler = ReminderSchedulerSpy()
        let repository = InMemoryReminderRecordRepository()
        let preferenceRepository = InMemoryReminderPreferenceRepository()
        let service = makeService(
            scheduler: scheduler,
            repository: repository,
            preferenceRepository: preferenceRepository,
            now: now
        )
        let reservation = makeReservation(departure: date(hour: 13))

        await service.updatePreference(
            advanceMinutes: 20,
            for: reservation,
            reservations: [reservation],
            settings: settings
        )
        await service.reset()

        XCTAssertEqual(scheduler.cancelAllCount, 1)
        XCTAssertTrue(repository.records.isEmpty)
        XCTAssertTrue(preferenceRepository.preferences.isEmpty)
    }

    func testUserDefaultsRepositoryPersistsRecords() {
        let suiteName = "RideReminderServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = UserDefaultsRideReminderRecordRepository(
            defaults: defaults,
            key: "records"
        )
        let record = RideReminderScheduleRecord(
            reservationID: "reservation-1",
            departure: date(hour: 13),
            triggerDate: date(hour: 12, minute: 50)
        )

        repository.save([record])
        XCTAssertEqual(repository.load(), [record])

        repository.removeAll()
        XCTAssertTrue(repository.load().isEmpty)
    }

    func testUserDefaultsRepositoryPersistsPreferences() {
        let suiteName = "RideReminderServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = UserDefaultsRideReminderPreferenceRepository(
            defaults: defaults,
            key: "preferences"
        )
        let preference = RideReminderPreference(
            reservationID: "reservation-1",
            departure: date(hour: 13),
            advanceMinutes: 20
        )

        repository.save([preference])
        XCTAssertEqual(repository.load(), [preference])

        repository.removeAll()
        XCTAssertTrue(repository.load().isEmpty)
    }

    private func makeService(
        scheduler: ReminderSchedulerSpy,
        repository: InMemoryReminderRecordRepository,
        preferenceRepository: InMemoryReminderPreferenceRepository = InMemoryReminderPreferenceRepository(),
        now: @escaping () -> Date
    ) -> RideReminderService {
        RideReminderService(
            scheduler: scheduler,
            recordRepository: repository,
            preferenceRepository: preferenceRepository,
            now: now
        )
    }

    private func makeService(
        scheduler: ReminderSchedulerSpy,
        repository: InMemoryReminderRecordRepository,
        preferenceRepository: InMemoryReminderPreferenceRepository = InMemoryReminderPreferenceRepository(),
        now: Date
    ) -> RideReminderService {
        makeService(
            scheduler: scheduler,
            repository: repository,
            preferenceRepository: preferenceRepository
        ) { now }
    }

    private func makeReservation(id: String = "reservation-1", departure: Date) -> Reservation {
        Reservation(
            id: id,
            hallAppointmentDataID: "period-1",
            routeName: "燕园至昌平",
            departure: departure,
            qrCodePayload: nil
        )
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 9
        components.day = 21
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}

private final class InMemoryReminderRecordRepository: RideReminderRecordRepository {
    var records: [RideReminderScheduleRecord] = []

    func load() -> [RideReminderScheduleRecord] { records }
    func save(_ records: [RideReminderScheduleRecord]) { self.records = records }
    func removeAll() { records.removeAll() }
}

private final class InMemoryReminderPreferenceRepository: RideReminderPreferenceRepository {
    var preferences: [RideReminderPreference] = []

    func load() -> [RideReminderPreference] { preferences }
    func save(_ preferences: [RideReminderPreference]) { self.preferences = preferences }
    func removeAll() { preferences.removeAll() }
}

private final class ReminderSchedulerSpy: RideReminderScheduler {
    enum TestError: Error { case failed }

    var authorization: RideReminderAuthorizationStatus = .authorized
    var pendingIDs = Set<String>()
    var scheduled: [(reservation: Reservation, triggerDate: Date, content: RideReminderContent)] = []
    var scheduleAttempts = 0
    var cancelledIDs: [String] = []
    var cancelAllPendingCount = 0
    var cancelAllCount = 0
    var shouldFail = false

    func authorizationStatus() async -> RideReminderAuthorizationStatus { authorization }
    func requestAuthorization() async -> Bool { authorization == .authorized }
    func pendingReservationIDs() async -> Set<String> { pendingIDs }

    func schedule(
        reservation: Reservation,
        triggerDate: Date,
        content: RideReminderContent
    ) async throws {
        scheduleAttempts += 1
        if shouldFail { throw TestError.failed }
        scheduled.append((reservation, triggerDate, content))
        pendingIDs.insert(reservation.id)
    }

    func cancel(reservationID: String) async {
        cancelledIDs.append(reservationID)
        pendingIDs.remove(reservationID)
    }

    func cancelAllPending() async {
        cancelAllPendingCount += 1
        pendingIDs.removeAll()
    }

    func cancelAll() async {
        cancelAllCount += 1
        pendingIDs.removeAll()
    }
}
