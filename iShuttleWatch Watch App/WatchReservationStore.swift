import Foundation
import Combine
import os

@MainActor
final class WatchReservationStore: ObservableObject {
    @Published private(set) var reservation: WatchReservation?
    private var reservations: [WatchReservation] = []
    private var expirationInterval: TimeInterval = 600
    private let key = "watchReservations"
    private let expirationKey = "watchExpirationInterval"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "iShuttleWatch", category: "WatchStore")

    init() {
        logger.info("初始化")
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let values = try? JSONDecoder().decode([WatchReservation].self, from: data) else {
            logger.info("load: 没有有效的本地预约")
            clear()
            return
        }
        expirationInterval = UserDefaults.standard.object(forKey: expirationKey) as? TimeInterval ?? 600
        reservations = values
        selectVisibleReservation()
        logger.info("load: 恢复预约 count=\(values.count, privacy: .public)")
    }

    func save(_ values: [WatchReservation], expirationInterval: TimeInterval) {
        guard let data = try? JSONEncoder().encode(values) else {
            logger.info("save: 编码失败，清除预约")
            clear()
            return
        }
        UserDefaults.standard.set(data, forKey: key)
        UserDefaults.standard.set(expirationInterval, forKey: expirationKey)
        self.reservations = values
        self.expirationInterval = expirationInterval
        selectVisibleReservation()
        logger.info("save: 成功 count=\(values.count, privacy: .public)，bytes=\(data.count, privacy: .public)")
    }

    private func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: expirationKey)
        reservations = []
        reservation = nil
        logger.info("clear: 已移除本地预约")
    }

    private func selectVisibleReservation() {
        reservation = reservations
            .filter { !$0.isExpired(using: expirationInterval) }
            .sorted { $0.departure < $1.departure }
            .first
    }
}
