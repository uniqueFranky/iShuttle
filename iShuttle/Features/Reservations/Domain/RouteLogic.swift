import Foundation

enum CommuteDirection: String, CaseIterable, Identifiable {
    case toHaidian = "去海淀"
    case toChangping = "去昌平"

    var id: String { rawValue }
}

enum RouteLogic {
    static func stops(in routeName: String) -> [String] {
        routeName
            .split(separator: "→", omittingEmptySubsequences: false)
            .map { displayStopName(String($0)) }
    }

    static func direction(for routeName: String) -> CommuteDirection? {
        let routeStops = stops(in: routeName)
        guard let changpingIndex = routeStops.firstIndex(of: "昌平"),
              let haidianIndex = routeStops.firstIndex(of: "海淀") else {
            return nil
        }
        return haidianIndex < changpingIndex ? .toChangping : .toHaidian
    }

    static func hasDelayedChangpingArrival(_ routeName: String) -> Bool {
        guard direction(for: routeName) == .toHaidian else { return false }
        let routeStops = stops(in: routeName)
        guard let twoHundredIndex = routeStops.firstIndex(of: "200号"),
              let changpingIndex = routeStops.firstIndex(of: "昌平") else {
            return false
        }
        return twoHundredIndex < changpingIndex
    }

    static func displayRouteName(_ routeName: String) -> String {
        routeName
            .split(separator: "→", omittingEmptySubsequences: false)
            .map { displayStopName(String($0)) }
            .joined(separator: "→")
    }

    private static func displayStopName(_ rawStop: String) -> String {
        let stop = rawStop.trimmingCharacters(in: .whitespacesAndNewlines)
        switch stop {
        case "燕园校区": return "海淀"
        case "新燕园校区": return "昌平"
        case "200号校区": return "200号"
        default: return stop
        }
    }
}
