import Foundation

struct Reservation: Identifiable, Codable, Equatable {
    let id: String
    let hallAppointmentDataID: String
    let routeName: String
    let departure: Date
    var qrCodePayload: String?

    var isVisibleAt: Bool { departure.addingTimeInterval(600) >= Date() }
}
