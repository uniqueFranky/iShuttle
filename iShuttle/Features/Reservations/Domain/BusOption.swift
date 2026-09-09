import Foundation

struct BusOption: Identifiable, Equatable {
    let id: String
    let routeName: String
    let departure: Date
    let period: Int
}
