import Foundation
import Combine
import WatchConnectivity
import os

@MainActor
final class WatchConnectivityReceiver: NSObject, ObservableObject, WCSessionDelegate {
    let store: WatchReservationStore
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "iShuttleWatch", category: "WatchSync")

    init(store: WatchReservationStore) {
        self.store = store
        super.init()
        guard WCSession.isSupported() else {
            logger.error("WCSession 不受支持")
            return
        }
        let session = WCSession.default
        session.delegate = self
        logger.info("初始化并 activate，已有 applicationContext keys=\(session.applicationContext.keys.sorted().joined(separator: ","), privacy: .public)")
        session.activate()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "iShuttleWatch", category: "WatchSync")
        logger.info("activationDidComplete state=\(String(describing: activationState), privacy: .public)，error=\(error?.localizedDescription ?? "nil", privacy: .public)，contextKeys=\(session.applicationContext.keys.sorted().joined(separator: ","), privacy: .public)")
        guard activationState == .activated else { return }
        let context = session.applicationContext
        Task { @MainActor in
            self.consume(context, source: "activation")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.consume(applicationContext, source: "didReceive")
        }
    }

#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif

    @MainActor
    private func consume(_ context: [String: Any], source: String) {
        logger.info("处理 context source=\(source, privacy: .public)，keys=\(context.keys.sorted().joined(separator: ","), privacy: .public)")
        guard let raw = context["reservations"] else {
            if context["clear"] as? Bool == true {
                logger.info("收到 clear 标记，清除 Watch 本地预约")
                store.clearReservations()
            } else {
                logger.warning("context 没有 reservation 或 clear 标记，忽略")
            }
            return
        }
        guard let data = raw as? Data else {
            logger.error("reservation 类型不是 Data，实际类型=\(String(describing: type(of: raw)), privacy: .public)")
            return
        }
        logger.info("收到 reservation bytes=\(data.count, privacy: .public)")
        do {
            let envelope = try JSONDecoder().decode(WatchReservationEnvelope.self, from: data)
            logger.info("解码成功 count=\(envelope.reservations.count, privacy: .public)，expirationMinutes=\(envelope.expirationInterval / 60, privacy: .public)")
            store.save(envelope.reservations, expirationInterval: envelope.expirationInterval)
            logger.info("已交给 WatchReservationStore 保存")
        } catch {
            logger.error("WatchReservation 解码失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}

private struct WatchReservationEnvelope: Codable {
    let reservations: [WatchReservation]
    let expirationInterval: TimeInterval
}
