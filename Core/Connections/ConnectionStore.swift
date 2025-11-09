import Foundation

public protocol ConnectionStore: Sendable {
    func listConnections() async throws -> [ConnectionProfile]
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
                name: "Sandbox Sqlite",
                kind: .sqlite,
                host: "localhost",
                port: 0,
                username: ""
            )
        ]
    }
}

public struct EmptyConnectionStore: ConnectionStore {
    public init() {}

    public func listConnections() async throws -> [ConnectionProfile] { [] }
}
