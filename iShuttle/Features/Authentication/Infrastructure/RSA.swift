import Foundation
import Security

enum RSA {
    static func encryptPKCS1(password: String, pem: String) throws -> String {
        let base64 = pem
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("---") }
            .joined()
        guard let der = Data(base64Encoded: base64) else {
            throw APIError.invalidResponse("登录公钥格式无效")
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 2048
        ]
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, nil) else {
            throw APIError.invalidResponse("无法创建登录公钥")
        }
        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(
            key,
            .rsaEncryptionPKCS1,
            Data(password.utf8) as CFData,
            &error
        ) as Data? else {
            throw (error?.takeRetainedValue() as Error?) ?? APIError.invalidResponse("密码加密失败")
        }
        return encrypted.base64EncodedString()
    }
}
