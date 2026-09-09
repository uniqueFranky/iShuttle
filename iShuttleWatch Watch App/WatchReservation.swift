import Foundation

struct WatchReservation: Codable, Equatable {
    let id: String
    let hallAppointmentDataID: String
    let routeName: String
    let departure: Date
    let qrCodePayload: String
    let qrCodeImageData: Data?

    var isExpired: Bool {
        departure.addingTimeInterval(600) < Date()
    }
}
