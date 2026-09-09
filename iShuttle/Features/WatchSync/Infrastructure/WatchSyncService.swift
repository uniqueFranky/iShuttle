import Foundation
import WatchConnectivity
import UIKit
import CoreImage
import os

final class WatchSyncService: NSObject, WCSessionDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "iShuttle", category: "WatchSync")
    private let session: WCSession?
    private var pendingContext: [String: Any]?

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
        let latest = reservations
            .filter { $0.departure.addingTimeInterval(expirationInterval) >= Date() && !($0.qrCodePayload ?? "").isEmpty }
            .sorted { $0.departure < $1.departure }
            .prefix(max(0, maxCount))
        if latest.isEmpty, !reservations.isEmpty {
            logger.info("存在预约但暂时没有二维码，保留 Watch 当前 context，不发送 clear")
            return 0
        }
        let context: [String: Any]
        do {
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
                    reservations: Array(transfers),
                    expirationInterval: expirationInterval
                )
                guard let data = try? JSONEncoder().encode(envelope) else {
                    logger.error("Watch transfer 编码失败")
                    return 0
                }
                logger.info("transfer 编码成功，bytes=\(data.count, privacy: .public)，count=\(transfers.count, privacy: .public)")
                context = ["reservations": data]
            } else {
                logger.info("没有可同步的有效预约，准备清空 Watch context")
                // WCSession 对空字典在部分系统版本上会报 “Application context data is nil”。
                context = ["clear": true]
            }
        }
        guard let session, session.activationState == .activated else {
            logger.warning("session 尚未 activated，暂存 context，state=\(String(describing: self.session?.activationState), privacy: .public)")
            pendingContext = context
            return latest.count
        }
        do {
            try session.updateApplicationContext(context)
            logger.info("updateApplicationContext 成功，keys=\(context.keys.sorted().joined(separator: ","), privacy: .public)")
            pendingContext = nil
        } catch {
            logger.error("updateApplicationContext 失败：\(error.localizedDescription, privacy: .public)")
            pendingContext = context
        }
        return latest.count
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        logger.info("activationDidComplete state=\(String(describing: activationState), privacy: .public)，error=\(error?.localizedDescription ?? "nil", privacy: .public)")
        guard activationState == .activated, let context = pendingContext else { return }
        do {
            try session.updateApplicationContext(context)
            logger.info("激活后重试 updateApplicationContext 成功")
            pendingContext = nil
        } catch {
            logger.error("激活后重试 updateApplicationContext 失败：\(error.localizedDescription, privacy: .public)")
        }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {
        logger.info("sessionDidBecomeInactive")
    }
    func sessionDidDeactivate(_ session: WCSession) {
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
