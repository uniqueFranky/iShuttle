import Foundation

final class UserDefaultsRideReminderPreferenceRepository: RideReminderPreferenceRepository {
    private static let defaultKey = "rideReminder.preferences.v1"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [RideReminderPreference] {
        guard let data = defaults.data(forKey: key),
              let preferences = try? JSONDecoder().decode([RideReminderPreference].self, from: data) else {
            return []
        }
        return preferences
    }

    func save(_ preferences: [RideReminderPreference]) {
        guard !preferences.isEmpty else {
            removeAll()
            return
        }
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }

    func removeAll() {
        defaults.removeObject(forKey: key)
    }
}
