import Foundation

actor ReservationStore: ReservationLocalDataSource {
    private let url: URL
    private var reservations: [Reservation] = []

    init(fileManager: FileManager = .default) {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("reservations.json")
    }

    func load() -> [Reservation] {
        guard let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([Reservation].self, from: data) else {
            return reservations
        }
        reservations = values
        purgeExpired()
        persist()
        return reservations
    }

    func all() -> [Reservation] {
        purgeExpired()
        persist()
        return reservations
    }

    func upsert(_ reservation: Reservation) {
        reservations.removeAll { $0.id == reservation.id }
        reservations.append(reservation)
        persist()
    }

    func remove(id: String) {
        reservations.removeAll { $0.id == id }
        persist()
    }

    func replace(_ values: [Reservation]) {
        reservations = values
        purgeExpired()
        persist()
    }

    private func purgeExpired() {
        let expiration = Date().addingTimeInterval(-600)
        reservations.removeAll { $0.departure < expiration }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(reservations) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
