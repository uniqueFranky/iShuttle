import Foundation
import Security

struct KeychainStore {
    private let service: String

    init(service: String = "me.ezreal.iShuttle") {
        self.service = service
    }

    func save(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidValue
        }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(baseQuery as CFDictionary)
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func read(_ key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = result as? Data else { throw KeychainError.invalidValue }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case invalidValue
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidValue: return "无法读取安全存储内容"
        case .status(let status): return "Keychain 操作失败（\(status)）"
        }
    }
}
