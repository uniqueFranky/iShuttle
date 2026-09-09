import Foundation

struct AuthChallenge: Equatable {
    enum Kind { case none, sms, otp }
    let kind: Kind
    let emailVerification: Bool
    let canRememberDevice: Bool
}
