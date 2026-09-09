import Foundation

enum WProcResponse {
    static func decode(_ data: Data, response: URLResponse) throws -> [String: Any] {
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.invalidResponse("服务器请求失败")
        }
        let object = try decodeObject(data)
        if let value = object["e"], String(describing: value) != "0" {
            let message = (object["m"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let errorMessage = message?.isEmpty == false ? message! : "服务器操作失败"
            if isAuthenticationMessage(errorMessage) {
                throw APIError.authenticationRequired
            }
            throw APIError.invalidResponse(errorMessage)
        }
        return object
    }

    static func decodeOperation(_ data: Data, response: URLResponse) throws -> [String: Any] {
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.invalidResponse("服务器请求失败")
        }
        let object = try decodeObject(data)
        try requireOperationSuccess(object)
        return object
    }

    private static func decodeObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse("服务器返回了无效数据")
        }
        return object
    }

    static func requireOperationSuccess(_ object: [String: Any]) throws {
        let message = (object["m"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard message == "操作成功" else {
            if isAuthenticationMessage(message) {
                throw APIError.authenticationRequired
            }
            throw APIError.invalidResponse(message.isEmpty ? "服务器操作失败" : message)
        }
    }

    private static func isAuthenticationMessage(_ message: String) -> Bool {
        ["该操作需要登录", "请先登录", "登录超时", "会话已失效", "用户未登录"]
            .contains { message.contains($0) }
    }

    static func stringValue(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        let result = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
