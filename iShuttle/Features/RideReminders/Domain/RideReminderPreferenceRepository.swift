import Foundation

protocol RideReminderPreferenceRepository {
    func load() -> [RideReminderPreference]
    func save(_ preferences: [RideReminderPreference])
    func removeAll()
}
