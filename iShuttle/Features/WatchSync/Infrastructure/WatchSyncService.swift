import Foundation
import WatchConnectivity
import UIKit
import CoreImage
import os

@MainActor
final class WatchSyncService: NSObject, WCSessionDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "iShuttle", category: "WatchSync")
    private let session: WCSession?
    private var pendingContext: [String: Any]?
    private var pendingConfirmations: [String: PendingConfirmation] = [:]

    override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        logger.info("初始化，supported=\(WCSession.isSupported(), privacy: .public)")
        session?.delegate = self
        session?.activate()
    }

    @discardableResult
    func sync(_ reservations: [Reservation], maxCount: Int = 3, expirationInterval: TimeInterval = 600) -> Int {
        logger.info("开始同步，reservations=\(reservations.count, privacy: .public)，maxCount=\(maxCount, privacy: .public)，expirationMinutes=\(expirationInterval / 60, privacy: .public)")
        guard case .payload(let prepared) = makeSyncPayload(reservations, maxCount: maxCount, expirationInterval: expirationInterval) else {
            return 0
        }
        queue(prepared.context)
        return prepared.count
    }

    func syncAndConfirm(
        _ reservations: [Reservation],
        maxCount: Int = 3,
        expirationInterval: TimeInterval = 600,
        timeout: Duration = .seconds(4)
    ) async -> WatchSyncResult {
        logger.info("开始手动同步，reservations=\(reservations.count, privacy: .public)，maxCount=\(maxCount, privacy: .public)，expirationMinutes=\(expirationInterval / 60, privacy: .public)")
        let preparation = makeSyncPayload(reservations, maxCount: maxCount, expirationInterval: expirationInterval)
        guard case .payload(let prepared) = preparation else {
            if case .encodingFailed = preparation {
                return .failed(message: "Watch 同步数据编码失败")
            }
            return .skippedNoQRCode
        }
        guard let session else {
            logger.error("当前设备不支持 WCSession")
            return .failed(message: "当前设备不支持 Apple Watch 同步")
        }
        if !session.isPaired {
            logger.warning("没有配对 Apple Watch")
            return .failed(message: "没有配对 Apple Watch")
        }
        if !session.isWatchAppInstalled {
            logger.warning("Watch App 未安装")
            return .failed(message: "Watch App 未安装")
        }
        guard queue(prepared.context) else {
            return .queued(count: prepared.count)
        }
        return await waitForAcknowledgement(syncID: prepared.syncID, count: prepared.count, timeout: timeout)
    }

    private func makeSyncPayload(
        _ reservations: [Reservation],
        maxCount: Int,
        expirationInterval: TimeInterval
    ) -> SyncPreparation {
        let latest = reservations
            .filter { $0.departure.addingTimeInterval(expirationInterval) >= Date() && !($0.qrCodePayload ?? "").isEmpty }
            .sorted { $0.departure < $1.departure }
            .prefix(max(0, maxCount))
        if latest.isEmpty, !reservations.isEmpty {
            logger.info("存在预约但暂时没有二维码，保留 Watch 当前 context，不发送 clear")
            return .skippedNoQRCode
        }
        let syncID = UUID().uuidString
        if !latest.isEmpty {
            let transfers = latest.map { reservation in
                WatchReservationTransfer(
                    id: reservation.id,
                    hallAppointmentDataID: reservation.hallAppointmentDataID,
                    routeName: reservation.routeName,
                    departure: reservation.departure,
                    qrCodePayload: reservation.qrCodePayload ?? "",
                    qrCodeImageData: Self.qrImageData(for: reservation.qrCodePayload ?? "")
                )
            }
            let envelope = WatchReservationEnvelope(
                syncID: syncID,
                reservations: Array(transfers),
                expirationInterval: expirationInterval
            )
            guard let data = try? JSONEncoder().encode(envelope) else {
                logger.error("Watch transfer 编码失败")
                return .encodingFailed
            }
            logger.info("transfer 编码成功，syncID=\(syncID, privacy: .public)，bytes=\(data.count, privacy: .public)，count=\(transfers.count, privacy: .public)")
            return .payload(PreparedSync(context: ["reservations": data, "watchSyncID": syncID], syncID: syncID, count: transfers.count))
        }
        logger.info("没有可同步的有效预约，准备清空 Watch context")
        // WCSession 对空字典在部分系统版本上会报 “Application context data is nil”。
        return .payload(PreparedSync(context: ["clear": true, "watchSyncID": syncID], syncID: syncID, count: 0))
    }

    @discardableResult
    private func queue(_ context: [String: Any]) -> Bool {
        guard let session, session.activationState == .activated else {
            logger.warning("session 尚未 activated，暂存 context，state=\(String(describing: self.session?.activationState), privacy: .public)")
            pendingContext = context
            return false
        }
        do {
            try session.updateApplicationContext(context)
            logger.info("updateApplicationContext 成功，keys=\(context.keys.sorted().joined(separator: ","), privacy: .public)")
            pendingContext = nil
            return true
        } catch {
            logger.error("updateApplicationContext 失败：\(error.localizedDescription, privacy: .public)")
            pendingContext = context
            return false
        }
    }

    private func waitForAcknowledgement(syncID: String, count: Int, timeout: Duration) async -> WatchSyncResult {
        await withCheckedContinuation { continuation in
            let timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.completeConfirmation(syncID: syncID, result: .queued(count: count), source: "timeout")
            }
            pendingConfirmations[syncID] = PendingConfirmation(count: count, continuation: continuation, timeoutTask: timeoutTask)
        }
    }

    private func completeConfirmation(syncID: String, result: WatchSyncResult, source: String) {
        guard let pending = pendingConfirmations.removeValue(forKey: syncID) else {
            logger.info("收到非当前手动同步回执 source=\(source, privacy: .public)，syncID=\(syncID, privacy: .public)")
            return
        }
        pending.timeoutTask.cancel()
        logger.info("完成手动同步等待 source=\(source, privacy: .public)，syncID=\(syncID, privacy: .public)")
        pending.continuation.resume(returning: result)
    }

    private func consumeAcknowledgement(_ payload: [String: Any], source: String) {
        guard let syncID = payload["watchSyncAckID"] as? String else {
            logger.warning("收到 Watch 消息但没有 ack syncID，source=\(source, privacy: .public)")
            return
        }
        let count = payload["watchSyncAckCount"] as? Int ?? pendingConfirmations[syncID]?.count ?? 0
        logger.info("收到 Watch 同步回执 source=\(source, privacy: .public)，syncID=\(syncID, privacy: .public)，count=\(count, privacy: .public)")
        completeConfirmation(syncID: syncID, result: .confirmed(count: count), source: source)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "iShuttle", category: "WatchSync")
        logger.info("activationDidComplete state=\(String(describing: activationState), privacy: .public)，error=\(error?.localizedDescription ?? "nil", privacy: .public)")
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.flushPendingContext(session)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.consumeAcknowledgement(message, source: "message")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            self.consumeAcknowledgement(userInfo, source: "userInfo")
        }
    }

    private func flushPendingContext(_ session: WCSession) {
        guard let context = pendingContext else { return }
        do {
            try session.updateApplicationContext(context)
            logger.info("激活后重试 updateApplicationContext 成功")
            pendingContext = nil
        } catch {
            logger.error("激活后重试 updateApplicationContext 失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "iShuttle", category: "WatchSync")
        logger.info("sessionDidBecomeInactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "iShuttle", category: "WatchSync")
        logger.info("sessionDidDeactivate，重新 activate")
        session.activate()
    }

    private static func qrImageData(for payload: String) -> Data? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage).pngData()
    }
}

private struct PreparedSync {
    let context: [String: Any]
    let syncID: String
    let count: Int
}

private enum SyncPreparation {
    case payload(PreparedSync)
    case skippedNoQRCode
    case encodingFailed
}

private struct PendingConfirmation {
    let count: Int
    let continuation: CheckedContinuation<WatchSyncResult, Never>
    let timeoutTask: Task<Void, Never>
}
