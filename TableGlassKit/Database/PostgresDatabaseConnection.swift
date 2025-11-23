import Foundation
#if canImport(PostgresNIO)
import Logging
import NIOSSL
import PostgresNIO

public actor PostgresDatabaseConnection: DatabaseConnection {
    public let profile: ConnectionProfile
    private let passwordResolver: any DatabasePasswordResolver
    private let logger: Logger
    private var client: PostgresClient?
    private var runTask: Task<Void, Never>?
    private var connected = false
    private let connectionTimeout: Duration = .seconds(10)
    private let queryTimeout: Duration = .seconds(30)

    public init(
        profile: ConnectionProfile,
        passwordResolver: some DatabasePasswordResolver = KeychainDatabasePasswordResolver(),
        logger: Logger = Logger(label: "TableGlass.Postgres")
    ) {
        self.profile = profile
        self.passwordResolver = passwordResolver
        self.logger = logger
    }

    public func connect() async throws {
        guard !connected else { return }

        let configuration = try await makeConfiguration()
        let logHost = configuration.host
        let logPort = configuration.port
        let logUser = configuration.username
        let logDatabase = configuration.database ?? "<nil>"
        logger.info("Connecting to postgres host=\(logHost) port=\(logPort) user=\(logUser) db=\(logDatabase)")
        let client = PostgresClient(
            configuration: configuration,
            backgroundLogger: .init(label: "TableGlass.Postgres.Background", factory: { _ in SwiftLogNoOpLogHandler() })
        )

        runTask = Task.detached(priority: .userInitiated) {
            await client.run()
        }
        self.client = client

        do {
            try Task.checkCancellation()
            _ = try await withTimeout(
                connectionTimeout,
                onTimeout: DatabaseError.connectionFailed("Connecting to \(self.profile.host) timed out")
            ) {
                try await client.withConnection { connection in
                    try await connection.query("SELECT 1").get()
                }
            }
            connected = true
            logger.info("Postgres connection established for \(logHost)")
        } catch {
            logger.error("Postgres connection failed: \(error.localizedDescription)")
            await disconnect()
            throw mapConnectionError(error, context: "Unable to connect to \(self.profile.host)")
        }
    }

    public func disconnect() async {
        logger.info("Disconnecting postgres \(profile.host)")
        connected = false
        let task = runTask
        runTask = nil
        client = nil

        // Wait for the client loop to exit so pooled connections are torn down.
        task?.cancel()
        _ = await task?.result
    }

    public func isConnected() async -> Bool {
        connected
    }

    public func beginTransaction(options: DatabaseTransactionOptions) async throws -> any DatabaseTransaction {
        let client = try requireClient()
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    try Task.checkCancellation()
                    logger.debug("BEGIN transaction isolation=\(String(describing: options.isolationLevel))")
                    try await client.withConnection { connection in
                        _ = try await connection.query(Self.beginStatement(options: options)).get()
                        let transaction = PostgresDatabaseTransaction(
                            connection: connection,
                            mapper: Self.mapResult,
                            errorMapper: { error, context in
                                self.mapError(error, context: context)
                            }
                        )
                        continuation.resume(returning: transaction)
                        await transaction.waitForCompletion()
                    }
                } catch {
                    continuation.resume(throwing: self.mapError(error, context: "Begin transaction failed"))
                }
            }
        }
    }

    public func metadata(scope: DatabaseMetadataScope) async throws -> DatabaseSchema {
        logger.info("Loading metadata schemas=\(String(describing: scope.schemaNames)) includeTables=\(scope.includeTables) includeViews=\(scope.includeViews) includeProcedures=\(scope.includeProcedures)")
        let targetSchemas = try await resolveSchemas(scope)
        guard !targetSchemas.isEmpty else {
            logger.warning("No schemas resolved for metadata request.")
            return DatabaseSchema(catalogs: [])
        }

        let tables = try await loadTables(for: targetSchemas, scope: scope)
        let columns = try await loadColumns(for: targetSchemas, scope: scope)
        let primaryKeys = try await loadPrimaryKeys(for: targetSchemas)

        var namespaces: [String: [String: DatabaseNamespace]] = [:]

        for (identifier, definition) in tables {
            var catalogNamespaces = namespaces[identifier.catalog, default: [:]]
            var namespace = catalogNamespaces[identifier.namespace, default: DatabaseNamespace(name: identifier.namespace)]

            switch definition.kind {
            case .table:
                let tableColumns = columns[identifier] ?? []
                let primaryKey = primaryKeys[identifier] ?? []
                let table = DatabaseTable(
                    name: identifier.name,
                    columns: tableColumns,
                    primaryKey: primaryKey
                )
                namespace.tables.append(table)
            case .view:
                let view = DatabaseView(name: identifier.name)
                namespace.views.append(view)
            }

            catalogNamespaces[identifier.namespace] = namespace
            namespaces[identifier.catalog] = catalogNamespaces
        }

        let catalogs: [DatabaseCatalog] = namespaces
            .map { catalogName, namespaces in
                DatabaseCatalog(
                    name: catalogName,
                    namespaces: namespaces.values.sorted { $0.name < $1.name }
                )
            }
            .sorted { $0.name < $1.name }

        logger.info("Metadata loaded catalogs=\(catalogs.count)")
        return DatabaseSchema(catalogs: catalogs)
    }

    @discardableResult
    public func execute(_ request: DatabaseQueryRequest) async throws -> DatabaseQueryResult {
        let client = try requireClient()
        let binds = Self.makeBindings(from: request.parameters)

        do {
            try Task.checkCancellation()
            let result = try await withTimeout(
                queryTimeout,
                onTimeout: DatabaseError.queryFailed("Query timed out")
            ) {
                try await client.withConnection { connection in
                    self.logger.debug("Executing query: \(request.sql)")
                    return try await connection.query(request.sql, binds).get()
                }
            }
            return Self.mapResult(result)
        } catch {
            logger.error("Query failed: \(error.localizedDescription)")
            throw mapError(error, context: "Query failed")
        }
    }
}

private extension PostgresDatabaseConnection {
    func makeConfiguration() async throws -> PostgresClient.Configuration {
        let password = try await passwordResolver.password(for: profile.passwordKeychainIdentifier)
        let database = profile.database?.isEmpty == false ? profile.database : profile.username

        guard let database else {
            throw DatabaseError.invalidConfiguration("Database name is required for PostgreSQL connections.")
        }

        let host = profile.host.lowercased() == "localhost" ? "127.0.0.1" : profile.host

        return PostgresClient.Configuration(
            host: host,
            port: profile.port,
            username: profile.username,
            password: password,
            database: database,
            tls: .prefer(.makeClientConfiguration())
        )
    }

    func requireClient() throws -> PostgresClient {
        guard let client else {
            throw DatabaseConnectionError.notConnected
        }
        return client
    }

    func resolveSchemas(_ scope: DatabaseMetadataScope) async throws -> [String] {
        if let specified = scope.schemaNames, !specified.isEmpty {
            return specified
        }

        let result = try await execute(DatabaseQueryRequest(
            sql: """
            SELECT schema_name
            FROM information_schema.schemata
            WHERE schema_name NOT IN ('pg_catalog', 'information_schema')
            """
        ))

        return result.rows.compactMap { $0.values["schema_name"]?.stringValue }
    }

    func loadTables(for schemas: [String], scope: DatabaseMetadataScope) async throws
        -> [DatabaseTableIdentifier: TableDefinition]
    {
        let placeholders = Self.placeholders(count: schemas.count)
        let types: [String] = {
            var kinds: [String] = []
            if scope.includeTables { kinds.append("BASE TABLE") }
            if scope.includeViews { kinds.append("VIEW") }
            return kinds
        }()

        guard !types.isEmpty else { return [:] }

        let typePlaceholders = Self.placeholders(offset: schemas.count, count: types.count)
        let request = DatabaseQueryRequest(
            sql: """
            SELECT table_catalog, table_schema, table_name, table_type
            FROM information_schema.tables
            WHERE table_schema IN (\(placeholders))
              AND table_type IN (\(typePlaceholders))
            """,
            parameters: schemas.map { .string($0) } + types.map { .string($0) }
        )

        let result = try await execute(request)
        var definitions: [DatabaseTableIdentifier: TableDefinition] = [:]

        for row in result.rows {
            guard
                let catalog = row.values["table_catalog"]?.stringValue,
                let schema = row.values["table_schema"]?.stringValue,
                let name = row.values["table_name"]?.stringValue,
                let type = row.values["table_type"]?.stringValue
            else { continue }

            let identifier = DatabaseTableIdentifier(catalog: catalog, namespace: schema, name: name)
            let kind: TableDefinition.Kind = type == "VIEW" ? .view : .table
            definitions[identifier] = TableDefinition(kind: kind)
        }

        return definitions
    }

    func loadColumns(for schemas: [String], scope: DatabaseMetadataScope) async throws
        -> [DatabaseTableIdentifier: [DatabaseColumn]]
    {
        guard scope.includeTables else { return [:] }

        let placeholders = Self.placeholders(count: schemas.count)
        let request = DatabaseQueryRequest(
            sql: """
            SELECT table_catalog, table_schema, table_name, column_name, data_type,
                   is_nullable, column_default, numeric_precision, numeric_scale
            FROM information_schema.columns
            WHERE table_schema IN (\(placeholders))
            ORDER BY ordinal_position
            """,
            parameters: schemas.map { .string($0) }
        )

        let result = try await execute(request)
        var columns: [DatabaseTableIdentifier: [DatabaseColumn]] = [:]

        for row in result.rows {
            guard
                let catalog = row.values["table_catalog"]?.stringValue,
                let schema = row.values["table_schema"]?.stringValue,
                let name = row.values["table_name"]?.stringValue,
                let columnName = row.values["column_name"]?.stringValue,
                let dataType = row.values["data_type"]?.stringValue
            else { continue }

            let isNullable = row.values["is_nullable"]?.stringValue == "YES"
            let precision = row.values["numeric_precision"]?.intValue
            let scale = row.values["numeric_scale"]?.intValue
            let column = DatabaseColumn(
                name: columnName,
                dataType: Self.mapColumnType(dataType, precision: precision, scale: scale),
                isNullable: isNullable,
                defaultValue: row.values["column_default"]
            )

            let identifier = DatabaseTableIdentifier(catalog: catalog, namespace: schema, name: name)
            columns[identifier, default: []].append(column)
        }

        return columns
    }

    func loadPrimaryKeys(for schemas: [String]) async throws -> [DatabaseTableIdentifier: [String]] {
        let placeholders = Self.placeholders(count: schemas.count)
        let request = DatabaseQueryRequest(
            sql: """
            SELECT tc.table_catalog, tc.table_schema, tc.table_name, kc.column_name
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kc
              ON tc.constraint_name = kc.constraint_name
             AND tc.table_schema = kc.table_schema
            WHERE tc.constraint_type = 'PRIMARY KEY'
              AND tc.table_schema IN (\(placeholders))
            ORDER BY kc.ordinal_position
            """,
            parameters: schemas.map { .string($0) }
        )

        let result = try await execute(request)
        var keys: [DatabaseTableIdentifier: [String]] = [:]

        for row in result.rows {
            guard
                let catalog = row.values["table_catalog"]?.stringValue,
                let schema = row.values["table_schema"]?.stringValue,
                let name = row.values["table_name"]?.stringValue,
                let column = row.values["column_name"]?.stringValue
            else { continue }

            let identifier = DatabaseTableIdentifier(catalog: catalog, namespace: schema, name: name)
            keys[identifier, default: []].append(column)
        }

        return keys
    }

    func mapError(_ error: Error, context: String) -> Error {
        if error is CancellationError {
            return DatabaseError.cancelled
        }
        if let databaseError = error as? DatabaseError {
            return databaseError
        }
        if let postgresError = error as? PSQLError {
            if postgresError.code == .queryCancelled {
                return DatabaseError.cancelled
            }
            if let message = postgresError.serverInfo?[.message] {
                return DatabaseError.queryFailed(message)
            }
            return DatabaseError.queryFailed("\(context) (\(postgresError.code.description))")
        }
        return DatabaseError.queryFailed(context)
    }

    func mapConnectionError(_ error: Error, context: String) -> Error {
        if error is CancellationError {
            return DatabaseError.cancelled
        }
        if let databaseError = error as? DatabaseError {
            return databaseError
        }
        if let postgresError = error as? PSQLError {
            if let message = postgresError.serverInfo?[.message] {
                return DatabaseError.connectionFailed(message)
            }
            return DatabaseError.connectionFailed("\(context) (\(postgresError.code.description))")
        }
        return DatabaseError.connectionFailed(context)
    }

    static func makeBindings(from parameters: [DatabaseQueryValue]) -> [PostgresData] {
        parameters.map { value in
            switch value {
            case .null:
                return .null
            case .bool(let flag):
                return PostgresData(bool: flag)
            case .int(let value):
                return PostgresData(int64: value)
            case .decimal(let value):
                return PostgresData(decimal: value)
            case .double(let value):
                return PostgresData(double: value)
            case .string(let value):
                return PostgresData(string: value)
            case .date(let value):
                return PostgresData(date: value)
            case .data(let value):
                return PostgresData(bytes: value)
            case .uuid(let value):
                return PostgresData(uuid: value)
            }
        }
    }

    static func mapResult(_ result: PostgresQueryResult) -> DatabaseQueryResult {
        let rows: [DatabaseQueryRow] = result.rows.map { row in
            let randomAccess = row.makeRandomAccess()
            var values: [String: DatabaseQueryValue] = [:]
            for index in 0..<randomAccess.count {
                let cell = randomAccess[index]
                let data = randomAccess[data: index]
                values[cell.columnName] = mapValue(data)
            }
            return DatabaseQueryRow(values: values)
        }
        return DatabaseQueryResult(rows: rows, affectedRowCount: result.metadata.rows)
    }

    static func mapValue(_ data: PostgresData) -> DatabaseQueryValue {
        guard data.value != nil else { return .null }

        if let bool = data.bool {
            return .bool(bool)
        }

        if let int = data.int {
            return .int(Int64(int))
        }

        if let decimal = data.decimal {
            return .decimal(decimal)
        }

        if let double = data.double {
            return .double(double)
        }

        if let string = data.string {
            return .string(string)
        }

        if let date = data.date {
            return .date(date)
        }

        if let bytes = data.bytes {
            return .data(Data(bytes))
        }

        if let uuid = data.uuid {
            return .uuid(uuid)
        }

        let length = data.value?.readableBytes ?? 0
        return .string("<unmapped oid=\(data.type) length=\(length)>")
    }

    static func mapColumnType(_ type: String, precision: Int?, scale: Int?) -> DatabaseColumnDataType {
        switch type.lowercased() {
        case "smallint", "integer", "bigint", "int", "int2", "int4", "int8":
            return .integer
        case "numeric", "decimal":
            return .numeric(precision: precision, scale: scale)
        case "boolean":
            return .boolean
        case "character varying", "character", "varchar", "text":
            return .text
        case "bytea":
            return .binary
        case "timestamp with time zone":
            return .timestamp(withTimeZone: true)
        case "timestamp without time zone", "timestamp":
            return .timestamp(withTimeZone: false)
        case "date":
            return .date
        default:
            return .custom(type)
        }
    }

    static func placeholders(offset: Int = 0, count: Int) -> String {
        guard count > 0 else { return "" }
        return (0..<count).map { "$\($0 + offset + 1)" }.joined(separator: ", ")
    }

    static func beginStatement(options: DatabaseTransactionOptions) -> String {
        guard let isolation = options.isolationLevel else { return "BEGIN" }
        let level: String
        switch isolation {
        case .readUncommitted:
            level = "READ UNCOMMITTED"
        case .readCommitted:
            level = "READ COMMITTED"
        case .repeatableRead:
            level = "REPEATABLE READ"
        case .serializable:
            level = "SERIALIZABLE"
        }
        return "BEGIN ISOLATION LEVEL \(level)"
    }

    func withTimeout<T>(
        _ duration: Duration,
        onTimeout timeoutError: @autoclosure @escaping @Sendable () -> Error,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw timeoutError()
            }

            guard let result = try await group.next() else {
                throw timeoutError()
            }
            group.cancelAll()
            return result
        }
    }
}

private struct TableDefinition: Sendable {
    enum Kind: Sendable {
        case table
        case view
    }

    var kind: Kind
}

private actor PostgresDatabaseTransaction: DatabaseTransaction {
    private let connection: PostgresConnection
    private let mapper: (PostgresQueryResult) -> DatabaseQueryResult
    private let errorMapper: (Error, String) -> Error
    private var finishContinuation: CheckedContinuation<Void, Never>?
    private var finished = false

    init(
        connection: PostgresConnection,
        mapper: @escaping (PostgresQueryResult) -> DatabaseQueryResult,
        errorMapper: @escaping (Error, String) -> Error
    ) {
        self.connection = connection
        self.mapper = mapper
        self.errorMapper = errorMapper
    }

    @discardableResult
    func execute(_ request: DatabaseQueryRequest) async throws -> DatabaseQueryResult {
        do {
            let binds = PostgresDatabaseConnection.makeBindings(from: request.parameters)
            let result = try await connection.query(request.sql, binds).get()
            return mapper(result)
        } catch {
            throw errorMapper(error, "Transaction query failed")
        }
    }

    func commit() async throws {
        guard !finished else { return }
        do {
            _ = try await connection.query("COMMIT").get()
            finish()
        } catch {
            finish()
            throw errorMapper(error, "Commit failed")
        }
    }

    func rollback() async {
        guard !finished else { return }
        _ = try? await connection.query("ROLLBACK").get()
        finish()
    }

    func waitForCompletion() async {
        guard !finished else { return }
        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
    }

    private func finish() {
        finished = true
        finishContinuation?.resume()
        finishContinuation = nil
    }
}

extension DatabaseQueryValue {
    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .double(let value):
            return String(value)
        case .decimal(let value):
            return NSDecimalNumber(decimal: value).stringValue
        case .date(let value):
            return value.formatted(.iso8601)
        case .uuid(let value):
            return value.uuidString
        case .data, .null:
            return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let value):
            return Int(value)
        case .string(let value):
            return Int(value)
        default:
            return nil
        }
    }
}
#endif

