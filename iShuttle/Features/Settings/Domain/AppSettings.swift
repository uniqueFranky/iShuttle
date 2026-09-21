import Foundation

struct AppSettings: Equatable {
    var themeMode: String
    var watchMaxReservationCount: Int
    var watchExpirationMinutes: Double
    var rideReminderEnabled: Bool
    var rideReminderAdvanceMinutes: Int

    static let `default` = AppSettings(
        themeMode: "system",
        watchMaxReservationCount: 3,
        watchExpirationMinutes: 10,
        rideReminderEnabled: false,
        rideReminderAdvanceMinutes: 10
    )
}
