import Foundation
import Security

struct KeychainHelper {
    private static let service = "com.christiannikolov.CafePulse"

    static let accessTokenKey = "accessToken"
    static let refreshTokenKey = "refreshToken"
    static let tokenExpiryKey = "tokenExpiry"

    static func save(key: String, data: Data) -> Bool {
        delete(key: key)  // Remove old value first

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func save(key: String, string: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return save(key: key, data: data)
    }

    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func loadString(key: String) -> String? {
        guard let data = load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAll() {
        delete(key: accessTokenKey)
        delete(key: refreshTokenKey)
        delete(key: tokenExpiryKey)
    }

    // Convenience for Date storage
    static func saveDate(key: String, date: Date) -> Bool {
        let interval = date.timeIntervalSince1970
        let data = withUnsafeBytes(of: interval) { Data($0) }
        return save(key: key, data: data)
    }

    static func loadDate(key: String) -> Date? {
        guard let data = load(key: key), data.count == MemoryLayout<TimeInterval>.size else { return nil }
        let interval = data.withUnsafeBytes { $0.load(as: TimeInterval.self) }
        return Date(timeIntervalSince1970: interval)
    }
}
