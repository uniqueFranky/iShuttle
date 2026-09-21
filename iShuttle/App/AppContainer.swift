import SwiftUI
import Foundation
import UIKit

@MainActor
final class AppContainer: ObservableObject {
    let session: URLSession
    let authService: AuthService
    private let sessionRepository: any SessionRepository
    let reservationAPI: ReservationAPI
    let reservations: ReservationStore
    var reservationRepository: any ReservationRepository
    let reservationService: ReservationService
    let watchSync: WatchSyncService
    let rideReminderService: RideReminderService
    let settingsRepository: any SettingsRepository
    @Published var isAuthenticated: Bool
    @Published var sessionMessage: String?
    @Published var settings: AppSettings
    @Published var rideReminderAuthorization: RideReminderAuthorizationStatus = .notDetermined

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
        let reminderService = RideReminderService(
            scheduler: UserNotificationReminderScheduler(),
            recordRepository: UserDefaultsRideReminderRecordRepository()
        )
        self.rideReminderService = reminderService
        let settingsRepository = UserDefaultsSettingsRepository()
        let settings = settingsRepository.load()
        self.settingsRepository = settingsRepository
        self.settings = settings
        reservations = ReservationStore(expirationInterval: settings.watchExpirationMinutes * 60)
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
            Task { await reminderService.rescheduleAll(reservations: values, settings: RideReminderSettings(enabled: currentSettings.rideReminderEnabled, advanceMinutes: currentSettings.rideReminderAdvanceMinutes)) }
        })
        sessionRepository.restoreSession(into: session)
        isAuthenticated = sessionRepository.currentUsername() != nil
        Task { @MainActor in
            rideReminderAuthorization = await reminderService.authorizationStatus()
        }
    }

    func updateWatchSettings(maxCount: Int, expirationMinutes: Double) async {
        var updated = settingsRepository.load()
        updated.watchMaxReservationCount = maxCount
        updated.watchExpirationMinutes = expirationMinutes
        settingsRepository.save(updated)
        settings = updated
        reservationRepository.expirationInterval = expirationMinutes * 60
        await reservations.setExpirationInterval(expirationMinutes * 60)
        let cached = await reservations.all()
        watchSync.sync(cached, maxCount: maxCount, expirationInterval: reservationRepository.expirationInterval)
    }

    func syncWatchData() async -> WatchSyncResult {
        let currentSettings = settingsRepository.load()
        let cached = await reservations.all()
        return await watchSync.syncAndConfirm(
            cached,
            maxCount: currentSettings.watchMaxReservationCount,
            expirationInterval: currentSettings.watchExpirationMinutes * 60
        )
    }

    func updateThemeMode(_ themeMode: String) {
        var updated = settingsRepository.load()
        updated.themeMode = themeMode
        settingsRepository.save(updated)
        settings = updated
    }

    func updateRideReminderSettings(enabled: Bool, advanceMinutes: Int) async {
        var updated = settingsRepository.load()
        updated.rideReminderEnabled = enabled
        updated.rideReminderAdvanceMinutes = max(1, advanceMinutes)
        if enabled {
            let status = await rideReminderService.authorizationStatus()
            if status == .notDetermined { _ = await rideReminderService.requestAuthorization() }
            rideReminderAuthorization = await rideReminderService.authorizationStatus()
            guard rideReminderAuthorization == .authorized else {
                updated.rideReminderEnabled = false
                settingsRepository.save(updated); settings = updated
                await rideReminderService.disable(); return
            }
        } else {
            await rideReminderService.disable()
            rideReminderAuthorization = await rideReminderService.authorizationStatus()
        }
        settingsRepository.save(updated); settings = updated
        let cached = await reservations.all()
        await rideReminderService.rescheduleAll(reservations: cached, settings: RideReminderSettings(enabled: updated.rideReminderEnabled, advanceMinutes: updated.rideReminderAdvanceMinutes))
    }

    func refreshRideReminderAuthorization() async {
        let status = await rideReminderService.authorizationStatus()
        rideReminderAuthorization = status

        guard status == .authorized else {
            guard settings.rideReminderEnabled else { return }
            var updated = settingsRepository.load()
            updated.rideReminderEnabled = false
            settingsRepository.save(updated)
            settings = updated
            await rideReminderService.disable()
            return
        }

        guard settings.rideReminderEnabled else { return }
        let cached = await reservations.all()
        await rideReminderService.rescheduleAll(
            reservations: cached,
            settings: RideReminderSettings(
                enabled: settings.rideReminderEnabled,
                advanceMinutes: settings.rideReminderAdvanceMinutes
            )
        )
    }

    func completeAuthentication(username: String) {
        sessionRepository.saveUsername(username)
        sessionRepository.persistSession(from: session)
        isAuthenticated = true
    }

    func expireSession() {
        Task { await rideReminderService.reset() }
        clearSession()
        sessionMessage = "登录会话已失效，请重新登录"
        isAuthenticated = false
    }

    func logout() {
        Task { await rideReminderService.reset() }
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
