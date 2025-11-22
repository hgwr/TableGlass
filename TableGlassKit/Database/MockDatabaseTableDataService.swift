import Foundation

public struct MockTableBehavior: Sendable {
    public var fetchDelay: Duration
    public var updateDelay: Duration
    public var insertDelay: Duration
    public var deleteDelay: Duration
    public var fetchError: (any Error & Sendable)?
    public var updateError: (any Error & Sendable)?
    public var insertError: (any Error & Sendable)?
    public var deleteError: (any Error & Sendable)?
    public var failingRowIDs: Set<UUID>

    public init(
        fetchDelay: Duration = .zero,
        updateDelay: Duration = .zero,
        insertDelay: Duration = .zero,
        deleteDelay: Duration = .zero,
        fetchError: (any Error & Sendable)? = nil,
        updateError: (any Error & Sendable)? = nil,
        insertError: (any Error & Sendable)? = nil,
        deleteError: (any Error & Sendable)? = nil,
        failingRowIDs: Set<UUID> = []
    ) {
        self.fetchDelay = fetchDelay
        self.updateDelay = updateDelay
        self.insertDelay = insertDelay
        self.deleteDelay = deleteDelay
        self.fetchError = fetchError
        self.updateError = updateError
        self.insertError = insertError
        self.deleteError = deleteError
        self.failingRowIDs = failingRowIDs
    }

    public static let passthrough = MockTableBehavior()
}

public struct MockTableConfiguration: Sendable {
    public var columns: [DatabaseColumn]
    public var rows: [DatabaseTableRow]
    public var behavior: MockTableBehavior

    public init(columns: [DatabaseColumn], rows: [DatabaseTableRow] = [], behavior: MockTableBehavior = .passthrough) {
        self.columns = columns
        self.rows = rows
        self.behavior = behavior
    }
}

public enum MockDatabaseTableDataServiceError: LocalizedError, Sendable, Equatable {
    case tableNotFound(DatabaseTableIdentifier)
    case rowNotFound
    case deleteRejected(UUID)

    public var errorDescription: String? {
        switch self {
        case .tableNotFound(let identifier):
            return "No mock data is registered for \(identifier.namespace).\(identifier.name)."
        case .rowNotFound:
            return "Row could not be located."
        case .deleteRejected(let id):
            return "Failed to delete row \(id.uuidString)."
        }
    }
}

public actor MockDatabaseTableDataService: DatabaseTableDataService {
    private var tables: [DatabaseTableIdentifier: MockTableConfiguration]
    private var fetchHistory: [DatabaseTableIdentifier: [Int]] = [:]

    public init(tables: [DatabaseTableIdentifier: MockTableConfiguration]) {
        self.tables = tables
    }

    public convenience init(
        table: DatabaseTableIdentifier,
        columns: [DatabaseColumn],
        rows: [DatabaseTableRow] = [],
        behavior: MockTableBehavior = .passthrough
    ) {
        self.init(tables: [table: MockTableConfiguration(columns: columns, rows: rows, behavior: behavior)])
    }

    public func fetchPage(for table: DatabaseTableIdentifier, page: Int, pageSize: Int) async throws -> DatabaseTablePage {
        var config = try configuration(for: table)
        try await sleepIfNeeded(config.behavior.fetchDelay)
        if let error = config.behavior.fetchError { throw error }

        fetchHistory[table, default: []].append(page)
        let start = max(0, page * pageSize)
        let end = min(config.rows.count, start + pageSize)
        let rows = start < end ? Array(config.rows[start..<end]) : []
        let hasMore = end < config.rows.count
        tables[table] = config
        return DatabaseTablePage(columns: config.columns, rows: rows, hasMore: hasMore)
    }

    public func updateRow(
        for table: DatabaseTableIdentifier,
        row: DatabaseTableRow,
        changedValues: [String: DatabaseQueryValue]
    ) async throws -> DatabaseTableRow {
        var config = try configuration(for: table)
        try await sleepIfNeeded(config.behavior.updateDelay)
        if let error = config.behavior.updateError { throw error }

        guard let index = config.rows.firstIndex(where: { $0.id == row.id }) else {
            throw MockDatabaseTableDataServiceError.rowNotFound
        }

        var merged = row.values.values
        for (key, value) in changedValues {
            merged[key] = value
        }
        let updated = DatabaseTableRow(id: row.id, values: DatabaseQueryRow(values: merged))
        config.rows[index] = updated
        tables[table] = config
        return updated
    }

    public func insertRow(for table: DatabaseTableIdentifier, values: [String: DatabaseQueryValue]) async throws -> DatabaseTableRow {
        var config = try configuration(for: table)
        try await sleepIfNeeded(config.behavior.insertDelay)
        if let error = config.behavior.insertError { throw error }

        var merged = Dictionary(uniqueKeysWithValues: config.columns.map { column in
            (column.name, column.defaultValue ?? .null)
        })
        for (key, value) in values {
            merged[key] = value
        }
        let newRow = DatabaseTableRow(values: DatabaseQueryRow(values: merged))
        config.rows.insert(newRow, at: 0)
        tables[table] = config
        return newRow
    }

    public func deleteRow(for table: DatabaseTableIdentifier, row: DatabaseTableRow) async throws {
        var config = try configuration(for: table)
        try await sleepIfNeeded(config.behavior.deleteDelay)
        if let error = config.behavior.deleteError { throw error }
        if config.behavior.failingRowIDs.contains(row.id) {
            throw MockDatabaseTableDataServiceError.deleteRejected(row.id)
        }
        guard let index = config.rows.firstIndex(where: { $0.id == row.id }) else {
            throw MockDatabaseTableDataServiceError.rowNotFound
        }
        config.rows.remove(at: index)
        tables[table] = config
    }

    public func updateBehavior(_ behavior: MockTableBehavior, for table: DatabaseTableIdentifier) throws {
        guard var config = tables[table] else {
            throw MockDatabaseTableDataServiceError.tableNotFound(table)
        }
        config.behavior = behavior
        tables[table] = config
    }

    public func snapshot(for table: DatabaseTableIdentifier) async -> [DatabaseTableRow] {
        tables[table]?.rows ?? []
    }

    public func recordedFetchPages(for table: DatabaseTableIdentifier) async -> [Int] {
        fetchHistory[table] ?? []
    }

    private func configuration(for table: DatabaseTableIdentifier) throws -> MockTableConfiguration {
        guard let config = tables[table] else {
            throw MockDatabaseTableDataServiceError.tableNotFound(table)
        }
        return config
    }

    private func sleepIfNeeded(_ delay: Duration) async throws {
        guard delay != .zero else { return }
        try await Task.sleep(for: delay)
    }
}
