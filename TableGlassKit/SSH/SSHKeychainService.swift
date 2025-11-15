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
    func allIdentities() async throws -> [SSHKeychainIdentityReference]
    func identity(forLabel label: String) async throws -> SSHKeychainIdentityReference?
}

public enum SSHKeychainError: Error, Sendable, Equatable {
    case unexpectedItemType
    case unresolved(status: OSStatus)
}

public struct DefaultSSHKeychainService: SSHKeychainService {
    public init() {}

    public func allIdentities() async throws -> [SSHKeychainIdentityReference] {
        try await Task.detached(priority: .userInitiated) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassIdentity,
                kSecReturnAttributes as String: true,
                kSecReturnPersistentRef as String: true,
                kSecMatchLimit as String: kSecMatchLimitAll,
            ]

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            switch status {
            case errSecItemNotFound:
                return []
            case errSecSuccess:
                guard let array = item as? [[String: Any]] else {
                    throw SSHKeychainError.unexpectedItemType
                }
                return array.compactMap { attributes in
                    guard let reference = attributes[kSecValuePersistentRef as String] as? Data else {
                        return nil
                    }

                    let resolvedLabel = Self.label(from: attributes)
                        ?? Self.fallbackLabel(for: reference)
                    return SSHKeychainIdentityReference(
                        label: resolvedLabel,
                        persistentReference: reference
                    )
                }
            default:
                throw SSHKeychainError.unresolved(status: status)
            }
        }.value
    }

    public func identity(forLabel label: String) async throws -> SSHKeychainIdentityReference? {
        let identities = try await allIdentities()
        return identities.first { $0.label == label }
    }
}

private extension DefaultSSHKeychainService {
    static func label(from attributes: [String: Any]) -> String? {
        if let label = attributes[kSecAttrLabel as String] as? String, !label.isEmpty {
            return label
        }

        if let applicationLabel = attributes[kSecAttrApplicationLabel as String] as? Data,
            let string = String(data: applicationLabel, encoding: .utf8), !string.isEmpty
        {
            return string
        }

        return nil
    }

    static func fallbackLabel(for reference: Data) -> String {
        let suffix = reference.base64EncodedString().suffix(8)
        return "Keychain Identity \(suffix)"
    }
}
