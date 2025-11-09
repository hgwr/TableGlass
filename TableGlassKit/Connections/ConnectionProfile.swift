import Foundation

public struct ConnectionProfile: Identifiable, Hashable, Sendable {
    public enum DatabaseKind: String, CaseIterable, Sendable {
        case postgreSQL
        case mySQL
        case sqlite
    }

    public struct SSHConfiguration: Hashable, Sendable {
        public var isEnabled: Bool
        public var configAlias: String
        public var username: String

        public init(isEnabled: Bool = false, configAlias: String = "", username: String = "") {
            self.isEnabled = isEnabled
            self.configAlias = configAlias
            self.username = username
        }
    }

    public let id: UUID
    public var name: String
    public var kind: DatabaseKind
    public var host: String
    public var port: Int
    public var username: String
    public var sshConfiguration: SSHConfiguration
    public var passwordKeychainIdentifier: String?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: DatabaseKind,
        host: String,
        port: Int,
        username: String,
        sshConfiguration: SSHConfiguration = SSHConfiguration(),
        passwordKeychainIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.host = host
        self.port = port
        self.username = username
        self.sshConfiguration = sshConfiguration
        self.passwordKeychainIdentifier = passwordKeychainIdentifier
    }
}
