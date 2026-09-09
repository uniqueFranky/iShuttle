import Foundation

struct AppSettings: Equatable {
    var themeMode: String
    var watchMaxReservationCount: Int
    var watchExpirationMinutes: Double

    static let `default` = AppSettings(
        themeMode: "system",
        watchMaxReservationCount: 3,
        watchExpirationMinutes: 10
    )
}
