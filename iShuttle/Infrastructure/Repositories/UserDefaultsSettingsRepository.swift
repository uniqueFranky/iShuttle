import Foundation

final class UserDefaultsSettingsRepository: SettingsRepository {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        let fallback = AppSettings.default
        return AppSettings(
            themeMode: defaults.string(forKey: "themeMode") ?? fallback.themeMode,
            watchMaxReservationCount: defaults.object(forKey: "watchMaxReservationCount") as? Int ?? fallback.watchMaxReservationCount,
            watchExpirationMinutes: defaults.object(forKey: "watchExpirationMinutes") as? Double ?? fallback.watchExpirationMinutes
        )
    }

    func save(_ settings: AppSettings) {
        defaults.set(settings.themeMode, forKey: "themeMode")
        defaults.set(settings.watchMaxReservationCount, forKey: "watchMaxReservationCount")
        defaults.set(settings.watchExpirationMinutes, forKey: "watchExpirationMinutes")
    }
}
