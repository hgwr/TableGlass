import Foundation

public struct ConnectionProfile: Identifiable, Hashable, Sendable {
    public enum DatabaseKind: String, CaseIterable, Sendable {
        case postgreSQL
        case mySQL
        case sqlite
    }

    public let id: UUID
    public var name: String
    public var kind: DatabaseKind
    public var host: String
    public var port: Int
    public var username: String

    public init(
        id: UUID = UUID(),
        name: String,
        kind: DatabaseKind,
        host: String,
        port: Int,
        username: String
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.host = host
        self.port = port
        self.username = username
    }
}
