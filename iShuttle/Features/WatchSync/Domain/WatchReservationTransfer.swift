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
    let reservations: [WatchReservationTransfer]
    let expirationInterval: TimeInterval
}
