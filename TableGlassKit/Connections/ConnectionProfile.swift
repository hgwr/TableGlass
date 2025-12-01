import Foundation

public struct ConnectionProfile: Identifiable, Hashable, Sendable, Codable {
    public enum DatabaseKind: String, CaseIterable, Sendable, Codable {
        case postgreSQL
        case mySQL
        case sqlite
    }
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case host
        case port
        case username
        case database
        case sshConfiguration
        case passwordKeychainIdentifier
        case isDraft
    }

    public struct SSHConfiguration: Hashable, Sendable, Codable {
        public enum AuthenticationMethod: String, CaseIterable, Sendable, Codable {
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
    public var isDraft: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        kind: DatabaseKind,
        host: String,
        port: Int,
        username: String,
        database: String? = nil,
        sshConfiguration: SSHConfiguration = SSHConfiguration(),
        passwordKeychainIdentifier: String? = nil,
        isDraft: Bool = false
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
        self.isDraft = isDraft
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(DatabaseKind.self, forKey: .kind)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        username = try container.decode(String.self, forKey: .username)
        database = try container.decodeIfPresent(String.self, forKey: .database)
        sshConfiguration = try container.decode(SSHConfiguration.self, forKey: .sshConfiguration)
        passwordKeychainIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .passwordKeychainIdentifier
        )
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(username, forKey: .username)
        try container.encodeIfPresent(database, forKey: .database)
        try container.encode(sshConfiguration, forKey: .sshConfiguration)
        try container.encodeIfPresent(passwordKeychainIdentifier, forKey: .passwordKeychainIdentifier)
        try container.encode(isDraft, forKey: .isDraft)
    }
}
