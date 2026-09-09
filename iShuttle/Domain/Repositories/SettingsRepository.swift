import Foundation

protocol SettingsRepository {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}
