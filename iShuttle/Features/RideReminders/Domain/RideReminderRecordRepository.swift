import Foundation

protocol RideReminderRecordRepository {
    func load() -> [RideReminderScheduleRecord]
    func save(_ records: [RideReminderScheduleRecord])
    func removeAll()
}
