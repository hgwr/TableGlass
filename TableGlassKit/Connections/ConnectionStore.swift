import Foundation

public protocol ConnectionStore: Sendable {
    func listConnections() async throws -> [ConnectionProfile]
    func saveConnection(_ connection: ConnectionProfile) async throws
    func deleteConnection(id: ConnectionProfile.ID) async throws
}

public struct PreviewConnectionStore: ConnectionStore {
    public init() {}

    public func listConnections() async throws -> [ConnectionProfile] {
        [
            ConnectionProfile(
                name: "Local Postgres",
                kind: .postgreSQL,
                host: "localhost",
                port: 5432,
                username: "postgres"
            ),
            ConnectionProfile(
                name: "Local MySQL",
                kind: .mySQL,
                host: "localhost",
                port: 3306,
                username: "root"
            ),
            ConnectionProfile(
                name: "Sandbox SQLite",
                kind: .sqlite,
                host: "localhost",
                port: 0,
                username: ""
            )
        ]
    }

    public func saveConnection(_ connection: ConnectionProfile) async throws {
        _ = connection
    }

    public func deleteConnection(id: ConnectionProfile.ID) async throws {
        _ = id
    }
}

public struct EmptyConnectionStore: ConnectionStore {
    public init() {}

    public func listConnections() async throws -> [ConnectionProfile] { [] }

    public func saveConnection(_ connection: ConnectionProfile) async throws {
        _ = connection
    }

    public func deleteConnection(id: ConnectionProfile.ID) async throws {
        _ = id
    }
}
