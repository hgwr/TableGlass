import Foundation

public struct ConnectionProfile: Identifiable, Hashable, Sendable {
    public enum DatabaseKind: String, CaseIterable, Sendable {
        case postgreSQL
        case mySQL
        case sqlite
    }

    public struct SSHConfiguration: Hashable, Sendable {
        public enum AuthenticationMethod: String, CaseIterable, Sendable {
            case keyFile
            case usernameAndPassword
            case sshAgent
        }

        public var isEnabled: Bool
        public var configAlias: String
        public var username: String
        public var authenticationMethod: AuthenticationMethod
        public var keychainIdentityLabel: String?
        public var keychainIdentityReference: Data?
        public var keyFilePath: String
        public var passwordKeychainIdentifier: String?

        public init(
            isEnabled: Bool = false,
            configAlias: String = "",
            username: String = "",
            authenticationMethod: AuthenticationMethod = .keyFile,
            keychainIdentityLabel: String? = nil,
            keychainIdentityReference: Data? = nil,
            keyFilePath: String = "",
            passwordKeychainIdentifier: String? = nil
        ) {
            self.isEnabled = isEnabled
            self.configAlias = configAlias
            self.username = username
            self.authenticationMethod = authenticationMethod
            self.keychainIdentityLabel = keychainIdentityLabel
            self.keychainIdentityReference = keychainIdentityReference
            self.keyFilePath = keyFilePath
            self.passwordKeychainIdentifier = passwordKeychainIdentifier
        }
    }

    public let id: UUID
    public var name: String
    public var kind: DatabaseKind
    public var host: String
    public var port: Int
    public var username: String
    public var database: String?
    public var sshConfiguration: SSHConfiguration
    public var passwordKeychainIdentifier: String?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: DatabaseKind,
        host: String,
        port: Int,
        username: String,
        database: String? = nil,
        sshConfiguration: SSHConfiguration = SSHConfiguration(),
        passwordKeychainIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.host = host
        self.port = port
        self.username = username
        self.database = database
        self.sshConfiguration = sshConfiguration
        self.passwordKeychainIdentifier = passwordKeychainIdentifier
    }
}
