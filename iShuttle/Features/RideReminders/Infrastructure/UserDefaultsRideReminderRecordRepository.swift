import Foundation

final class UserDefaultsRideReminderRecordRepository: RideReminderRecordRepository {
    private static let defaultKey = "rideReminder.scheduleRecords.v1"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [RideReminderScheduleRecord] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([RideReminderScheduleRecord].self, from: data) else {
            return []
        }
        return records
    }

    func save(_ records: [RideReminderScheduleRecord]) {
        guard !records.isEmpty else {
            removeAll()
            return
        }
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }

    func removeAll() {
        defaults.removeObject(forKey: key)
    }
}
