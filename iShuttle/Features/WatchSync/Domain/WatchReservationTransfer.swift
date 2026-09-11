import Foundation

struct WatchReservationTransfer: Codable {
    let id: String
    let hallAppointmentDataID: String
    let routeName: String
    let departure: Date
    let qrCodePayload: String
    let qrCodeImageData: Data?
}

struct WatchReservationEnvelope: Codable {
    let syncID: String
    let reservations: [WatchReservationTransfer]
    let expirationInterval: TimeInterval
}

enum WatchSyncResult: Equatable {
    case confirmed(count: Int)
    case queued(count: Int)
    case skippedNoQRCode
    case failed(message: String)

    var displayMessage: String {
        switch self {
        case .confirmed(let count):
            if count == 0 {
                return "已同步，Watch 预约已清空"
            }
            return "已同步 \(count) 条预约"
        case .queued:
            return "已排队，打开 Watch App 后同步"
        case .skippedNoQRCode:
            return "没有可同步的乘车码"
        case .failed(let message):
            return message
        }
    }
}
