import Foundation

enum APIError: LocalizedError {
    case invalidResponse(String)
    case authenticationRequired
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message): return message
        case .authenticationRequired: return "登录会话已失效，请重新登录"
        case .network(let error): return error.localizedDescription
        }
    }
}
