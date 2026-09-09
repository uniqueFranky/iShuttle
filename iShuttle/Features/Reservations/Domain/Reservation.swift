import Foundation

struct Reservation: Identifiable, Codable, Equatable {
    let id: String
    let hallAppointmentDataID: String
    let routeName: String
    let departure: Date
    var qrCodePayload: String?

    func isVisibleAt(using expirationInterval: TimeInterval) -> Bool {
        departure.addingTimeInterval(expirationInterval) >= Date()
    }
}
