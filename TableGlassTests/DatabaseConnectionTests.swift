import Foundation
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
                                        DatabaseColumn(name: "id", dataType: .integer, isNullable: false),
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

        let price = Decimal(string: "19.99") ?? .zero
        let connection = MockDatabaseConnection(
            profile: profile,
            metadata: .schema(schema),
            routes: [
                .sqlEquals(
                    "SELECT * FROM artists",
                    response: .result(
                        DatabaseQueryResult(
                            rows: [
                                DatabaseQueryRow(values: [
                                    "value": .int(1),
                                    "price": .decimal(price),
                                ])
                            ]
                        )
                    )
                ),
            ],
            defaultResponse: .failure(MockDatabaseError.unhandledRequest("default"))
        )

        try await connection.connect()
        let isConnected = await connection.isConnected()
        XCTAssertTrue(isConnected)

        let request = DatabaseQueryRequest(sql: "SELECT * FROM artists")
        let result = try await connection.execute(request)
        XCTAssertEqual(result.rows.count, 1)

        let firstRow = try XCTUnwrap(result.rows.first)
        XCTAssertEqual(firstRow[column: "value"], .int(1))
        XCTAssertEqual(firstRow[column: "price"], .decimal(price))

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

        let transactionPlan = MockDatabaseTransactionPlan(
            defaultResponse: .result(DatabaseQueryResult(rows: [], affectedRowCount: 1))
        )

        let connection = MockDatabaseConnection(
            profile: profile,
            metadata: .schema(DatabaseSchema(catalogs: [])),
            transactionPlan: transactionPlan
        )
        try await connection.connect()

        let transaction = try await connection.beginTransaction(options: DatabaseTransactionOptions())
        let request = DatabaseQueryRequest(sql: "UPDATE accounts SET balance = balance - 100")
        _ = try await transaction.execute(request)
        try await transaction.commit()

        guard let mockTransaction = transaction as? MockDatabaseTransaction else {
            XCTFail("Expected MockDatabaseTransaction")
            return
        }

        let executedRequests = await mockTransaction.executedRequestsSnapshot()
        XCTAssertEqual(executedRequests, [request])

        let didCommit = await mockTransaction.didCommit()
        XCTAssertTrue(didCommit)

        let didRollback = await mockTransaction.didRollback()
        XCTAssertFalse(didRollback)
    }

    func testMocksCanSimulateErrorsAndLatency() async throws {
        let profile = ConnectionProfile(
            name: "SQLite",
            kind: .sqlite,
            host: ":memory:",
            port: 0,
            username: ""
        )

        let latency = MockDatabaseLatency(
            connect: .milliseconds(5),
            metadata: .milliseconds(5),
            execute: .milliseconds(5),
            transaction: .milliseconds(2)
        )
        let metadataDelay: Duration = .milliseconds(3)
        let brokenQueryDelay: Duration = .milliseconds(2)

        let connection = MockDatabaseConnection(
            profile: profile,
            metadata: .failure(SampleError.unavailable, delay: metadataDelay),
            routes: [
                .sqlContains("broken", response: .failure(SampleError.unavailable, delay: brokenQueryDelay))
            ],
            defaultResponse: .result(DatabaseQueryResult(rows: [DatabaseQueryRow(values: ["id": .int(1)])])),
            latency: latency
        )

        let clock = ContinuousClock()
        let tolerance = Duration.milliseconds(1)
        let minimumConnect = max(Duration.zero, latency.connect - tolerance)
        let connectStart = clock.now
        try await connection.connect()
        let connectElapsed = clock.now - connectStart
        XCTAssertGreaterThanOrEqual(connectElapsed, minimumConnect)

        let metadataStart = clock.now
        do {
            _ = try await connection.metadata(scope: DatabaseMetadataScope())
            XCTFail("Expected metadata to fail")
        } catch let error as SampleError {
            XCTAssertEqual(error, .unavailable)
        }
        let metadataElapsed = clock.now - metadataStart
        let minimumMetadata = max(Duration.zero, (metadataDelay) - tolerance)
        XCTAssertGreaterThanOrEqual(metadataElapsed, minimumMetadata)

        do {
            _ = try await connection.execute(DatabaseQueryRequest(sql: "SELECT * FROM broken"))
            XCTFail("Expected query to fail")
        } catch let error as SampleError {
            XCTAssertEqual(error, .unavailable)
        }
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
                        profile: profile,
                        metadata: .schema(DatabaseSchema(catalogs: []))
                    )
                })

        let connection = provider.makeConnection(for: profile)
        try await connection.connect()
        let isConnected = await connection.isConnected()
        XCTAssertTrue(isConnected)
    }
}

private enum SampleError: Error, LocalizedError, Sendable, Equatable {
    case unavailable

    var errorDescription: String? {
        "Resource unavailable"
    }
}
