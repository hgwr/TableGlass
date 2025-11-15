import Foundation
import Security

public struct SSHKeychainIdentityReference: Sendable, Hashable {
    public let label: String
    public let persistentReference: Data

    public init(label: String, persistentReference: Data) {
        self.label = label
        self.persistentReference = persistentReference
    }
}

public protocol SSHKeychainService: Sendable {
    func identity(forLabel label: String) async throws -> SSHKeychainIdentityReference?
}

public enum SSHKeychainError: Error, Sendable, Equatable {
    case unexpectedItemType
    case unresolved(status: OSStatus)
}

public struct DefaultSSHKeychainService: SSHKeychainService {
    public init() {}

    public func identity(forLabel label: String) async throws -> SSHKeychainIdentityReference? {
        try await Task.detached(priority: .userInitiated) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassIdentity,
                kSecAttrLabel as String: label,
                kSecReturnPersistentRef as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            switch status {
            case errSecSuccess:
                guard let data = item as? Data else {
                    throw SSHKeychainError.unexpectedItemType
                }
                return SSHKeychainIdentityReference(label: label, persistentReference: data)
            case errSecItemNotFound:
                return nil
            default:
                throw SSHKeychainError.unresolved(status: status)
            }
        }.value
    }
}
