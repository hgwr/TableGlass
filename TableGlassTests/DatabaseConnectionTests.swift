import XCTest

@testable import TableGlassKit

final class DatabaseConnectionTests: XCTestCase {
    func testMockConnectionExecutesQueries() async throws {
        let profile = ConnectionProfile(
            name: "Test Postgres",
            kind: .postgreSQL,
            host: "127.0.0.1",
            port: 5432,
            username: "postgres"
        )

        let schema = DatabaseSchema(
            catalogs: [
                DatabaseCatalog(
                    name: "public",
                    namespaces: [
                        DatabaseNamespace(
                            name: "public",
                            tables: [
                                DatabaseTable(
                                    name: "artists",
                                    columns: [
                                        DatabaseColumn(
                                            name: "id", dataType: .integer, isNullable: false),
                                        DatabaseColumn(name: "name", dataType: .text),
                                    ],
                                    primaryKey: ["id"]
                                )
                            ]
                        )
                    ]
                )
            ]
        )

        let connection = MockDatabaseConnection(profile: profile, metadataResponse: schema)
        try await connection.connect()
        let isConnected = await connection.isConnected()
        XCTAssertTrue(isConnected)

        let request = DatabaseQueryRequest(sql: "SELECT * FROM artists")
        let result = try await connection.execute(request)
        XCTAssertEqual(result.rows.count, 1)
        let recordedRequests = await connection.recordedRequests()
        XCTAssertEqual(recordedRequests, [request])

        let metadata = try await connection.metadata(scope: DatabaseMetadataScope())
        XCTAssertEqual(metadata, schema)
    }

    func testTransactionLifecycle() async throws {
        let profile = ConnectionProfile(
            name: "Txn",
            kind: .mySQL,
            host: "localhost",
            port: 3306,
            username: "root"
        )

        let connection = MockDatabaseConnection(
            profile: profile, metadataResponse: DatabaseSchema(catalogs: []))
        try await connection.connect()

        let transaction = try await connection.beginTransaction(
            options: DatabaseTransactionOptions())
        let request = DatabaseQueryRequest(sql: "UPDATE accounts SET balance = balance - 100")
        _ = try await transaction.execute(request)
        try await transaction.commit()

        guard let mockTransaction = transaction as? MockDatabaseTransaction else {
            XCTFail("Expected MockDatabaseTransaction")
            return
        }

        let executedRequests = await mockTransaction.executedRequests()
        XCTAssertEqual(executedRequests, [request])

        let didCommit = await mockTransaction.didCommit()
        XCTAssertTrue(didCommit)

        let didRollback = await mockTransaction.didRollback()
        XCTAssertFalse(didRollback)
    }

    func testPlaceholderDriverThrows() async {
        let profile = ConnectionProfile(
            name: "SQLite",
            kind: .sqlite,
            host: ":memory:",
            port: 0,
            username: ""
        )

        let provider = DatabaseConnectionProvider.placeholderDrivers
        let connection = provider.makeConnection(for: profile)

        do {
            _ = try await connection.execute(DatabaseQueryRequest(sql: "SELECT 1"))
            XCTFail("Expected driver unavailable error")
        } catch let error as DatabaseDriverUnavailable {
            XCTAssertEqual(error.driverKind, .sqlite)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCustomFactoryOverridesPlaceholder() async throws {
        let profile = ConnectionProfile(
            name: "Custom",
            kind: .sqlite,
            host: ":memory:",
            port: 0,
            username: ""
        )

        let provider = DatabaseConnectionProvider.placeholderDrivers
            .registering(
                .sqlite,
                factory: AnyDatabaseConnectionFactory { profile in
                    MockDatabaseConnection(
                        profile: profile, metadataResponse: DatabaseSchema(catalogs: []))
                })

        let connection = provider.makeConnection(for: profile)
        try await connection.connect()
        let isConnected = await connection.isConnected()
        XCTAssertTrue(isConnected)
    }
}

actor MockDatabaseConnection: DatabaseConnection {
    let profile: ConnectionProfile
    private var connected = false
    private var requests: [DatabaseQueryRequest] = []
    private let metadataResponse: DatabaseSchema

    init(profile: ConnectionProfile, metadataResponse: DatabaseSchema) {
        self.profile = profile
        self.metadataResponse = metadataResponse
    }

    func connect() async throws {
        connected = true
    }

    func disconnect() async {
        connected = false
    }

    func isConnected() async -> Bool {
        connected
    }

    func beginTransaction(options: DatabaseTransactionOptions) async throws
        -> any DatabaseTransaction
    {
        MockDatabaseTransaction()
    }

    func metadata(scope: DatabaseMetadataScope) async throws -> DatabaseSchema {
        metadataResponse
    }

    @discardableResult
    func execute(_ request: DatabaseQueryRequest) async throws -> DatabaseQueryResult {
        requests.append(request)
        let row = DatabaseQueryRow(values: ["value": .int(1)])
        return DatabaseQueryResult(rows: [row], affectedRowCount: nil)
    }

    func recordedRequests() async -> [DatabaseQueryRequest] {
        requests
    }
}

actor MockDatabaseTransaction: DatabaseTransaction {
    private var requests: [DatabaseQueryRequest] = []
    private var commitCalled = false
    private var rollbackCalled = false

    @discardableResult
    func execute(_ request: DatabaseQueryRequest) async throws -> DatabaseQueryResult {
        requests.append(request)
        return DatabaseQueryResult(rows: [], affectedRowCount: 1)
    }

    func commit() async throws {
        commitCalled = true
    }

    func rollback() async {
        rollbackCalled = true
    }

    func executedRequests() async -> [DatabaseQueryRequest] {
        requests
    }

    func didCommit() async -> Bool {
        commitCalled
    }

    func didRollback() async -> Bool {
        rollbackCalled
    }
}
