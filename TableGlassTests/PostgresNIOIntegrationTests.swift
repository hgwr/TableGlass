#if canImport(PostgresNIO) && LOCALDEBUG
import Foundation
@testable import TableGlassKit
import XCTest

final class PostgresNIOIntegrationTests: XCTestCase {
    func testCrudAndMetadataRoundTrip() async throws {
        guard let configuration = LocalPostgresConfiguration.load() else {
            throw XCTSkip("Local PostgreSQL credentials are not configured.")
        }

        let connection = PostgresDatabaseConnection(
            profile: configuration.profile,
            passwordResolver: KeychainDatabasePasswordResolver()
        )

        try await connection.connect()
        defer { Task { await connection.disconnect() } }

        let tableName = "tg_postgres_integration"
        defer { Task { _ = try? await connection.execute(DatabaseQueryRequest(sql: "DROP TABLE IF EXISTS \(tableName)")) } }
        _ = try? await connection.execute(DatabaseQueryRequest(sql: "DROP TABLE IF EXISTS \(tableName)"))
        try await connection.execute(
            DatabaseQueryRequest(
                sql: """
                CREATE TABLE \(tableName) (
                    id SERIAL PRIMARY KEY,
                    name TEXT NOT NULL,
                    flag BOOLEAN DEFAULT FALSE
                )
                """
            )
        )

        let insertResult = try await connection.execute(
            DatabaseQueryRequest(
                sql: "INSERT INTO \(tableName) (name, flag) VALUES ($1, $2) RETURNING id",
                parameters: [.string("alice"), .bool(true)]
            )
        )
        let insertedID = try XCTUnwrap(insertResult.rows.first?.values["id"]?.intValue)

        let selectResult = try await connection.execute(
            DatabaseQueryRequest(
                sql: "SELECT id, name, flag FROM \(tableName) WHERE id = $1",
                parameters: [.int(Int64(insertedID))]
            )
        )
        XCTAssertEqual(selectResult.rows.count, 1)
        let row = try XCTUnwrap(selectResult.rows.first)
        XCTAssertEqual(row.values["name"]?.stringValue, "alice")
        XCTAssertEqual(row.values["flag"], .bool(true))

        let updateResult = try await connection.execute(
            DatabaseQueryRequest(
                sql: "UPDATE \(tableName) SET name = $1 WHERE id = $2",
                parameters: [.string("updated"), .int(Int64(insertedID))]
            )
        )
        XCTAssertEqual(updateResult.affectedRowCount, 1)

        let deleteResult = try await connection.execute(
            DatabaseQueryRequest(
                sql: "DELETE FROM \(tableName) WHERE id = $1",
                parameters: [.int(Int64(insertedID))]
            )
        )
        XCTAssertEqual(deleteResult.affectedRowCount, 1)

        let metadata = try await connection.metadata(
            scope: DatabaseMetadataScope(
                schemaNames: [configuration.schema],
                includeTables: true,
                includeViews: false,
                includeProcedures: false
            )
        )

        let hasTable = metadata.catalogs.contains { catalog in
            catalog.namespaces.contains { namespace in
                guard namespace.name == configuration.schema else { return false }
                return namespace.tables.contains { $0.name == tableName }
            }
        }
        XCTAssertTrue(hasTable, "Expected metadata to include \(tableName)")
    }
}

private struct LocalPostgresConfiguration {
    var profile: ConnectionProfile
    var schema: String

    static func load() -> LocalPostgresConfiguration? {
        guard
            let host = env("TABLEGLASS_POSTGRES_HOST"),
            let user = env("TABLEGLASS_POSTGRES_USER"),
            let database = env("TABLEGLASS_POSTGRES_DB"),
            let passwordID = env("TABLEGLASS_POSTGRES_PASSWORD_ID")
        else {
            return nil
        }

        let port = Int(env("TABLEGLASS_POSTGRES_PORT") ?? "") ?? 5432
        let schema = env("TABLEGLASS_POSTGRES_SCHEMA") ?? "public"

        let profile = ConnectionProfile(
            name: "LocalDebugPostgres",
            kind: .postgreSQL,
            host: host,
            port: port,
            username: user,
            database: database,
            passwordKeychainIdentifier: passwordID
        )

        return LocalPostgresConfiguration(profile: profile, schema: schema)
    }
}

private func env(_ key: String) -> String? {
    guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else {
        return nil
    }
    return value
}
#endif
