import Foundation
import Security

public enum DatabasePasswordKeychain {
    private static let service = "com.tableglass.database.credentials"

    @discardableResult
    public static func store(password: String, identifier: String) throws -> String {
        let payload = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: payload,
            kSecAttrLabel as String: "TableGlass DB Password",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return identifier
        case errSecItemNotFound:
            var insert = query
            insert.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw DatabaseCredentialError.unresolved(status: addStatus)
            }
            return identifier
        default:
            throw DatabaseCredentialError.unresolved(status: status)
        }
    }

    public static func deletePassword(identifier: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier,
        ]
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw DatabaseCredentialError.unresolved(status: status)
        }
    }
}
