import Foundation

public protocol DatabaseQueryExecutor: Sendable {
    @discardableResult
    func execute(_ request: DatabaseQueryRequest) async throws -> DatabaseQueryResult
}

public protocol DatabaseMetadataProvider: Sendable {
    func metadata(scope: DatabaseMetadataScope) async throws -> DatabaseSchema
}

public enum DatabaseAccessMode: Sendable, Equatable {
    case readOnly
    case writable
}

public protocol DatabaseSessionModeControlling: Sendable {
    var currentMode: DatabaseAccessMode { get async }
    func setMode(_ mode: DatabaseAccessMode) async throws
}

public actor InMemoryDatabaseSessionModeController: DatabaseSessionModeControlling {
    private var mode: DatabaseAccessMode

    public init(initialMode: DatabaseAccessMode = .readOnly) {
        self.mode = initialMode
    }

    public var currentMode: DatabaseAccessMode {
        mode
    }

    public func setMode(_ mode: DatabaseAccessMode) async throws {
        self.mode = mode
    }
}

public struct DatabaseTransactionOptions: Sendable, Equatable {
    public var isolationLevel: DatabaseIsolationLevel?

    public init(isolationLevel: DatabaseIsolationLevel? = nil) {
        self.isolationLevel = isolationLevel
    }
}

public enum DatabaseIsolationLevel: Sendable, Equatable {
    case readUncommitted
    case readCommitted
    case repeatableRead
    case serializable
}

public protocol DatabaseTransaction: DatabaseQueryExecutor {
    func commit() async throws
    func rollback() async
}

public protocol DatabaseTableDataService: Sendable {
    func fetchPage(for table: DatabaseTableIdentifier, page: Int, pageSize: Int) async throws -> DatabaseTablePage
    func updateRow(
        for table: DatabaseTableIdentifier,
        row: DatabaseTableRow,
        changedValues: [String: DatabaseQueryValue]
    ) async throws -> DatabaseTableRow
    func insertRow(for table: DatabaseTableIdentifier, values: [String: DatabaseQueryValue]) async throws -> DatabaseTableRow
    func deleteRow(for table: DatabaseTableIdentifier, row: DatabaseTableRow) async throws
}

public protocol DatabaseConnection: DatabaseQueryExecutor, DatabaseMetadataProvider {
    var profile: ConnectionProfile { get }
    func connect() async throws
    func disconnect() async
    func isConnected() async -> Bool
    func beginTransaction(options: DatabaseTransactionOptions) async throws
        -> any DatabaseTransaction
}

public enum DatabaseConnectionError: Error, Sendable, Equatable {
    case notConnected
    case closed
    case driverUnavailable(DatabaseDriverUnavailable)
    case cancelled
}

public struct DatabaseDriverUnavailable: Error, Sendable, Equatable {
    public var driverKind: ConnectionProfile.DatabaseKind
    public var reason: String

    public init(driverKind: ConnectionProfile.DatabaseKind, reason: String) {
        self.driverKind = driverKind
        self.reason = reason
    }
}

public protocol DatabaseConnectionFactory: Sendable {
    func makeConnection(for profile: ConnectionProfile) -> any DatabaseConnection
}

public struct AnyDatabaseConnectionFactory: DatabaseConnectionFactory {
    private let builder: @Sendable (ConnectionProfile) -> any DatabaseConnection

    public init(_ builder: @escaping @Sendable (ConnectionProfile) -> any DatabaseConnection) {
        self.builder = builder
    }

    public func makeConnection(for profile: ConnectionProfile) -> any DatabaseConnection {
        builder(profile)
    }
}

public struct DatabaseConnectionProvider: Sendable {
    private var factories: [ConnectionProfile.DatabaseKind: AnyDatabaseConnectionFactory]
    private var defaultFactory: AnyDatabaseConnectionFactory

    public init(
        factories: [ConnectionProfile.DatabaseKind: AnyDatabaseConnectionFactory] = [:],
        defaultFactory: AnyDatabaseConnectionFactory = .pending(reason: "No driver registered")
    ) {
        self.factories = factories
        self.defaultFactory = defaultFactory
    }

    public func registering(
        _ kind: ConnectionProfile.DatabaseKind,
        factory: AnyDatabaseConnectionFactory
    ) -> DatabaseConnectionProvider {
        var copy = self
        copy.factories[kind] = factory
        return copy
    }

    public func makeConnection(for profile: ConnectionProfile) -> any DatabaseConnection {
        let factory = factories[profile.kind] ?? defaultFactory
        return factory.makeConnection(for: profile)
    }
}

extension AnyDatabaseConnectionFactory {
    public static func pending(reason: String) -> AnyDatabaseConnectionFactory {
        AnyDatabaseConnectionFactory { profile in
            let error = DatabaseDriverUnavailable(driverKind: profile.kind, reason: reason)
            return PendingDatabaseConnection(profile: profile, error: error)
        }
    }
}

extension DatabaseConnectionProvider {
    public static var placeholderDrivers: DatabaseConnectionProvider {
        DatabaseConnectionProvider(
            factories: [
                .postgreSQL: .pending(reason: "PostgresNIO integration pending"),
                .mySQL: .pending(reason: "MySQLNIO integration pending"),
                .sqlite: .pending(reason: "sqlite3 integration pending"),
            ]
        )
    }
}

#if canImport(PostgresNIO)
import PostgresNIO

public extension DatabaseConnectionProvider {
    func withPostgresNIO(
        passwordResolver: some DatabasePasswordResolver = KeychainDatabasePasswordResolver()
    ) -> DatabaseConnectionProvider {
        registering(
            .postgreSQL,
            factory: AnyDatabaseConnectionFactory { profile in
                PostgresDatabaseConnection(profile: profile, passwordResolver: passwordResolver)
            }
        )
    }
}
#else
public extension DatabaseConnectionProvider {
    func withPostgresNIO(
        passwordResolver: some DatabasePasswordResolver = KeychainDatabasePasswordResolver()
    ) -> DatabaseConnectionProvider {
        _ = passwordResolver
        return self
    }
}
#endif

public actor PendingDatabaseConnection: DatabaseConnection {
    public let profile: ConnectionProfile
    private let error: DatabaseDriverUnavailable
    private var connected: Bool = false

    public init(profile: ConnectionProfile, error: DatabaseDriverUnavailable) {
        self.profile = profile
        self.error = error
    }

    public func connect() async throws {
        throw error
    }

    public func disconnect() async {
        connected = false
    }

    public func isConnected() async -> Bool {
        connected
    }

    public func beginTransaction(options: DatabaseTransactionOptions) async throws
        -> any DatabaseTransaction
    {
        throw error
    }

    public func metadata(scope: DatabaseMetadataScope) async throws -> DatabaseSchema {
        throw error
    }

    public func execute(_ request: DatabaseQueryRequest) async throws -> DatabaseQueryResult {
        throw error
    }
}
