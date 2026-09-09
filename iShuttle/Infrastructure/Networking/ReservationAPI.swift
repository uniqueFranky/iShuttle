import Foundation

struct ReservationAPI: ReservationRemoteDataSource {
    private let session: URLSession
    private let baseURL = URL(string: "https://wproc.pku.edu.cn")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func currentReservations() async throws -> [Reservation] {
        let url = makeURL(
            path: "/site/reservation/my-list-time",
            query: [
                URLQueryItem(name: "p", value: "1"),
                URLQueryItem(name: "page_size", value: "0"),
                URLQueryItem(name: "status", value: "2"),
                URLQueryItem(name: "sort_time", value: "true"),
                URLQueryItem(name: "sort", value: "asc")
            ]
        )
        let (data, response) = try await session.data(from: url)
        let object = try WProcResponse.decode(data, response: response)
        guard let details = object["d"] as? [String: Any],
              let values = details["data"] as? [[String: Any]] else { return [] }
        return values.compactMap(parseReservation)
    }

    func qrCode(for reservation: Reservation) async throws -> String {
        let url = makeURL(
            path: "/site/reservation/get-sign-qrcode",
            query: [
                URLQueryItem(name: "type", value: "0"),
                URLQueryItem(name: "id", value: reservation.id),
                URLQueryItem(name: "hall_appointment_data_id", value: reservation.hallAppointmentDataID)
            ]
        )
        let (data, response) = try await session.data(from: url)
        let object = try WProcResponse.decode(data, response: response)
        let details = object["d"] as? [String: Any]
        guard let code = details?["code"] as? String else {
            throw APIError.invalidResponse("二维码返回格式无效")
        }
        return code
    }

    func availableBuses(on date: Date) async throws -> [BusOption] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let url = makeURL(
            path: "/site/reservation/list-page",
            query: [
                URLQueryItem(name: "hall_id", value: "1"),
                URLQueryItem(name: "time", value: formatter.string(from: date)),
                URLQueryItem(name: "p", value: "1"),
                URLQueryItem(name: "page_size", value: "0")
            ]
        )
        let (data, response) = try await session.data(from: url)
        let object = try WProcResponse.decode(data, response: response)
        guard let details = object["d"] as? [String: Any],
              let routes = details["list"] as? [[String: Any]] else { return [] }
        return routes.flatMap(parseBusOptions)
    }

    func createReservation(resourceID: String, date: String, period: Int) async throws -> Reservation {
        let url = baseURL.appendingPathComponent("/site/reservation/launch")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let payload = "[{\"date\":\"\(date)\",\"period\":\(period),\"sub_resource_id\":0}]"
        request.httpBody = "resource_id=\(resourceID)&data=\(payload.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? payload)".data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        print("[ReservationAPI] launch response:", String(data: data, encoding: .utf8) ?? "<non-UTF8 response>")
        let object = try WProcResponse.decodeOperation(data, response: response)
        guard let details = object["d"] as? [String: Any] else {
            throw APIError.invalidResponse("预约成功，但服务器未返回预约信息")
        }
        let id = details["id"] ?? details["appointment_id"] ?? value(named: "id", in: details)
        let dataID = details["hall_appointment_data_id"] ?? details["hallAppointmentDataId"]
            ?? value(named: "hall_appointment_data_id", in: details)
            ?? value(named: "hallAppointmentDataId", in: details)
        // 创建成功是由 m == "操作成功" 确认的。编号有时会在后续查询接口中补齐，
        // 因此缺失编号不能把已经成功的预约报告为失败。
        return Reservation(
            id: WProcResponse.stringValue(id) ?? "",
            hallAppointmentDataID: WProcResponse.stringValue(dataID) ?? "",
            routeName: "班车",
            departure: Date.distantFuture,
            qrCodePayload: nil
        )
    }

    func cancelReservation(_ reservation: Reservation) async throws {
        let url = baseURL.appendingPathComponent("/site/reservation/single-time-cancel")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "appointment_id=\(reservation.id)&data_id%5B0%5D=\(reservation.hallAppointmentDataID)".data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        _ = try WProcResponse.decodeOperation(data, response: response)
    }

    private func makeURL(path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        return components.url!
    }

    private func value(named key: String, in object: Any) -> Any? {
        if let dictionary = object as? [String: Any] {
            if let value = dictionary[key] { return value }
            for nested in dictionary.values {
                if let value = value(named: key, in: nested) { return value }
            }
        } else if let array = object as? [Any] {
            for nested in array {
                if let value = value(named: key, in: nested) { return value }
            }
        }
        return nil
    }

    private func parseReservation(_ value: [String: Any]) -> Reservation? {
        guard let id = value["id"],
              let periods = value["periodList"] as? [[String: Any]],
              let periodID = periods.first?["id"] else { return nil }
        let text = (value["appointment_tim"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard let date = Self.parseDate(text) else { return nil }
        return Reservation(
            id: String(describing: id),
            hallAppointmentDataID: String(describing: periodID),
            routeName: value["resource_name"] as? String ?? "班车",
            departure: date,
            qrCodePayload: nil
        )
    }

    private func parseBusOptions(_ route: [String: Any]) -> [BusOption] {
        guard let id = route["id"], let name = route["name"] as? String,
              let table = route["table"] as? [String: Any] else { return [] }
        return table.values.flatMap { value -> [BusOption] in
            guard let slots = value as? [[String: Any] ] else { return [] }
            return slots.compactMap { slot in
                guard Self.hasAvailability(slot["row"]) else { return nil }
                guard let period = slot["time_id"] as? Int,
                      let dateText = slot["abscissa"] as? String,
                      let timeText = slot["yaxis"] as? String else { return nil }
                let departureText = "\(dateText.trimmingCharacters(in: .whitespaces)) \(timeText.trimmingCharacters(in: .whitespaces))"
                guard let departure = Self.parseDate(departureText) else { return nil }
                let uniqueID = "\(id)-\(dateText)-\(timeText)-\(period)"
                return BusOption(id: uniqueID, routeName: name, departure: departure, period: period)
            }
        }
    }

    private static func hasAvailability(_ value: Any?) -> Bool {
        guard let row = value as? [String: Any],
              let margin = row["margin"] else { return false }
        if let number = margin as? NSNumber { return number.intValue > 0 }
        return Int(String(describing: margin)) ?? 0 > 0
    }

    private static func parseDate(_ text: String) -> Date? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let localFormatter = DateFormatter()
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.calendar = Calendar(identifier: .gregorian)
        localFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            localFormatter.dateFormat = format
            if let date = localFormatter.date(from: normalized) { return date }
        }
        let isoFormatter = ISO8601DateFormatter()
        return isoFormatter.date(from: normalized)
    }
}
