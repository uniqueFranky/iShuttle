import Foundation
import Combine
import os

@MainActor
final class WatchReservationStore: ObservableObject {
    @Published private(set) var reservation: WatchReservation?
    private let key = "latestWatchReservation"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "iShuttleWatch", category: "WatchStore")

    init() {
        logger.info("初始化")
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(WatchReservation.self, from: data),
              !value.isExpired else {
            logger.info("load: 没有有效的本地预约")
            clear()
            return
        }
        reservation = value
        logger.info("load: 恢复预约 id=\(value.id, privacy: .public)")
    }

    func save(_ value: WatchReservation?) {
        guard let value, !value.isExpired,
              let data = try? JSONEncoder().encode(value) else {
            logger.info("save: 清除预约（nil、过期或编码失败）")
            clear()
            return
        }
        UserDefaults.standard.set(data, forKey: key)
        reservation = value
        logger.info("save: 成功 id=\(value.id, privacy: .public)，bytes=\(data.count, privacy: .public)")
    }

    private func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        reservation = nil
        logger.info("clear: 已移除本地预约")
    }
}
