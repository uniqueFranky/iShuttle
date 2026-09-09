import SwiftUI
import Foundation
import UIKit

@MainActor
final class AppContainer: ObservableObject {
    let session: URLSession
    let authService: AuthService
    private let sessionRepository: any SessionRepository
    let reservationAPI: ReservationAPI
    let reservations = ReservationStore()
    var reservationRepository: any ReservationRepository
    let reservationService: ReservationService
    let watchSync: WatchSyncService
    let settingsRepository: any SettingsRepository
    @Published var isAuthenticated: Bool
    @Published var sessionMessage: String?
    @Published var settings: AppSettings

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: configuration)
        sessionRepository = KeychainSessionRepository()
        authService = AuthService(session: session)
        reservationAPI = ReservationAPI(session: session)
        let watchSync = WatchSyncService()
        self.watchSync = watchSync
        let settingsRepository = UserDefaultsSettingsRepository()
        let settings = settingsRepository.load()
        self.settingsRepository = settingsRepository
        self.settings = settings
        let repository = DefaultReservationRepository(
            remote: reservationAPI,
            local: reservations,
            expirationInterval: settings.watchExpirationMinutes * 60
        )
        reservationRepository = repository
        isAuthenticated = false
        sessionMessage = nil
        reservationService = ReservationService(repository: repository, onReservationsChanged: { values in
            let currentSettings = settingsRepository.load()
            watchSync.sync(values, maxCount: currentSettings.watchMaxReservationCount, expirationInterval: repository.expirationInterval)
        })
        sessionRepository.restoreSession(into: session)
        isAuthenticated = sessionRepository.currentUsername() != nil
    }

    func updateWatchSettings(maxCount: Int, expirationMinutes: Double) async {
        var updated = settingsRepository.load()
        updated.watchMaxReservationCount = maxCount
        updated.watchExpirationMinutes = expirationMinutes
        settingsRepository.save(updated)
        settings = updated
        reservationRepository.expirationInterval = expirationMinutes * 60
        let cached = await reservations.all()
        watchSync.sync(cached, maxCount: maxCount, expirationInterval: reservationRepository.expirationInterval)
    }

    func updateThemeMode(_ themeMode: String) {
        var updated = settingsRepository.load()
        updated.themeMode = themeMode
        settingsRepository.save(updated)
        settings = updated
    }

    func completeAuthentication(username: String) {
        sessionRepository.saveUsername(username)
        sessionRepository.persistSession(from: session)
        isAuthenticated = true
    }

    func expireSession() {
        clearSession()
        sessionMessage = "登录会话已失效，请重新登录"
        isAuthenticated = false
    }

    func logout() {
        sessionRepository.clearUsername()
        sessionRepository.clearSession(from: session)
        sessionMessage = nil
        isAuthenticated = false
    }

    func currentUsername() -> String? {
        sessionRepository.currentUsername()
    }

    private func clearSession() {
        sessionRepository.clearUsername()
        sessionRepository.clearSession(from: session)
    }
}
