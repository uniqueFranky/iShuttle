import Foundation

final class KeychainSessionRepository: SessionRepository {
    private struct CookieRecord: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let expires: Date?
    }

    private let keychain: KeychainStore
    private let cookiesKey = "cookies"
    private let usernameKey = "username"

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    func restoreSession(into session: URLSession) {
        guard let encoded = try? keychain.read(cookiesKey),
              let data = encoded.data(using: .utf8),
              let records = try? JSONDecoder().decode([CookieRecord].self, from: data) else { return }
        let storage = cookieStorage(for: session)
        records.compactMap { record in
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: record.name, .value: record.value,
                .domain: record.domain, .path: record.path
            ]
            if let expires = record.expires { properties[.expires] = expires }
            return HTTPCookie(properties: properties)
        }.forEach { storage.setCookie($0) }
    }

    func persistSession(from session: URLSession) {
        let records = cookieStorage(for: session).cookies?.map {
            CookieRecord(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path, expires: $0.expiresDate)
        } ?? []
        guard let data = try? JSONEncoder().encode(records),
              let encoded = String(data: data, encoding: .utf8) else { return }
        try? keychain.save(encoded, for: cookiesKey)
    }

    func clearSession(from session: URLSession) {
        let storage = cookieStorage(for: session)
        storage.cookies?.forEach { storage.deleteCookie($0) }
        try? keychain.delete(cookiesKey)
    }

    func currentUsername() -> String? { try? keychain.read(usernameKey) }
    func saveUsername(_ username: String) { try? keychain.save(username, for: usernameKey) }
    func clearUsername() { try? keychain.delete(usernameKey) }

    private func cookieStorage(for session: URLSession) -> HTTPCookieStorage {
        session.configuration.httpCookieStorage ?? .shared
    }
}
