import Foundation

struct Reservation: Identifiable, Codable, Equatable {
    let id: String
    let hallAppointmentDataID: String
    let routeName: String
    let departure: Date
    var qrCodePayload: String?

    var isVisibleAt: Bool {
        departure.addingTimeInterval(600) >= Date()
    }
}

struct BusOption: Identifiable, Equatable {
    let id: String
    let routeName: String
    let departure: Date
    let period: Int
}

struct AuthChallenge: Equatable {
    enum Kind {
        case none
        case sms
        case otp
    }

    let kind: Kind
    let emailVerification: Bool
    let canRememberDevice: Bool
}

enum APIError: LocalizedError {
    case invalidResponse(String)
    case authenticationRequired
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            return message
        case .authenticationRequired:
            return "登录会话已失效，请重新登录"
        case .network(let error):
            return error.localizedDescription
        }
    }
}
