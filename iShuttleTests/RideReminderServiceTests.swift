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
        let service = makeService(scheduler: scheduler, repository: repository, now: now)
        let reservation = makeReservation(departure: date(hour: 13))

        await service.rescheduleAll(reservations: [reservation], settings: settings)
        await service.reset()

        XCTAssertEqual(scheduler.cancelAllCount, 1)
        XCTAssertTrue(repository.records.isEmpty)
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

    private func makeService(
        scheduler: ReminderSchedulerSpy,
        repository: InMemoryReminderRecordRepository,
        now: @escaping () -> Date
    ) -> RideReminderService {
        RideReminderService(scheduler: scheduler, recordRepository: repository, now: now)
    }

    private func makeService(
        scheduler: ReminderSchedulerSpy,
        repository: InMemoryReminderRecordRepository,
        now: Date
    ) -> RideReminderService {
        makeService(scheduler: scheduler, repository: repository) { now }
    }

    private func makeReservation(departure: Date) -> Reservation {
        Reservation(
            id: "reservation-1",
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
