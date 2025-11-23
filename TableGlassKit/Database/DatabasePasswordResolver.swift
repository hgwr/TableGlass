import Foundation
import Security

public protocol DatabasePasswordResolver: Sendable {
    func password(for identifier: String?) async throws -> String?
}

public enum DatabaseCredentialError: LocalizedError, Sendable, Equatable {
    case unexpectedItemType
    case unresolved(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unexpectedItemType:
            return "Keychain item could not be decoded."
        case .unresolved(let status):
            return "Keychain lookup failed with status \(status)."
        }
    }
}

public struct KeychainDatabasePasswordResolver: DatabasePasswordResolver {
    public init() {}

    public func password(for identifier: String?) async throws -> String? {
        guard let identifier, !identifier.isEmpty else { return nil }
        return try await Task.detached(priority: .userInitiated) {
            if let password = try Self.lookupPassword(account: identifier) {
                return password
            }
            return try Self.lookupPassword(label: identifier)
        }.value
    }
}

public struct StaticDatabasePasswordResolver: DatabasePasswordResolver {
    private let stored: String?

    public init(password: String?) {
        stored = password
    }

    public func password(for identifier: String?) async throws -> String? {
        _ = identifier
        return stored
    }
}

private extension KeychainDatabasePasswordResolver {
    static func lookupPassword(account: String) throws -> String? {
        try lookupPassword(query: [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ])
    }

    static func lookupPassword(label: String) throws -> String? {
        try lookupPassword(query: [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrLabel as String: label,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ])
    }

    static func lookupPassword(query: [String: Any]) throws -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecItemNotFound:
            return nil
        case errSecSuccess:
            guard let data = item as? Data else {
                throw DatabaseCredentialError.unexpectedItemType
            }
            return String(data: data, encoding: .utf8)
        default:
            throw DatabaseCredentialError.unresolved(status: status)
        }
    }
}
