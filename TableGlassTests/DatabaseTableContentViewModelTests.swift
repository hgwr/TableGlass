import TableGlassKit
import Testing

@testable import TableGlass

@MainActor
struct DatabaseTableContentViewModelTests {
    private let tableID = DatabaseTableIdentifier(catalog: "main", namespace: "public", name: "artists")
    private let columns: [DatabaseColumn] = [
        DatabaseColumn(name: "id", dataType: .integer, isNullable: false),
        DatabaseColumn(name: "name", dataType: .text, isNullable: false),
        DatabaseColumn(name: "country", dataType: .text, isNullable: true),
    ]

    @Test
    func loadingFetchesFirstPage() async throws {
        let service = MockTableDataService(columns: columns, seedRows: [
            DatabaseTableRow(values: DatabaseQueryRow(values: ["id": .int(1), "name": .string("One")]))
        ])
        let viewModel = DatabaseTableContentViewModel(tableDataService: service, pageSize: 1)

        await viewModel.loadIfNeeded(for: tableID, columns: columns)
        try await Task.sleep(for: .milliseconds(10))

        #expect(viewModel.rows.count == 1)
        #expect(viewModel.hasMorePages == false)
        let snapshot = await service.snapshot(for: tableID)
        #expect(snapshot.count == 1)
    }

    @Test
    func commitRowUpdatesChanges() async throws {
        let service = MockTableDataService(columns: columns, seedRows: [
            DatabaseTableRow(values: DatabaseQueryRow(values: ["id": .int(1), "name": .string("Original")]))
        ])
        let viewModel = DatabaseTableContentViewModel(tableDataService: service, pageSize: 1)
        await viewModel.loadIfNeeded(for: tableID, columns: columns)
        try await Task.sleep(for: .milliseconds(10))

        guard let row = viewModel.rows.first else {
            Issue.record("Expected a row to edit")
            return
        }

        viewModel.updateCell(id: row.id, column: "name", text: "Updated")
        await viewModel.commitRow(row.id)
        try await Task.sleep(for: .milliseconds(10))

        let stored = await service.snapshot(for: tableID)
        #expect(stored.first?.values.values["name"] == .string("Updated"))
        #expect(viewModel.rows.first?.hasChanges == false)
    }

    @Test
    func insertAndDeleteRowsFlow() async throws {
        let service = MockTableDataService(columns: columns, seedRows: [])
        let viewModel = DatabaseTableContentViewModel(tableDataService: service, pageSize: 10)
        await viewModel.loadIfNeeded(for: tableID, columns: columns)

        viewModel.addRow()
        guard let pending = viewModel.rows.first else {
            Issue.record("Expected new row to be present")
            return
        }

        viewModel.updateCell(id: pending.id, column: "id", text: "10")
        viewModel.updateCell(id: pending.id, column: "name", text: "New Artist")
        await viewModel.commitRow(pending.id)
        try await Task.sleep(for: .milliseconds(10))

        var stored = await service.snapshot(for: tableID)
        #expect(stored.count == 1)

        if let saved = viewModel.rows.first {
            viewModel.selection = [saved.id]
            await viewModel.deleteSelectedRows()
        }

        stored = await service.snapshot(for: tableID)
        #expect(stored.isEmpty)
    }

    @Test
    func validationErrorsSurfaceOnMissingRequiredField() async throws {
        let service = MockTableDataService(columns: columns, seedRows: [
            DatabaseTableRow(values: DatabaseQueryRow(values: ["id": .int(5), "name": .string("Stale")]))
        ])
        let viewModel = DatabaseTableContentViewModel(tableDataService: service, pageSize: 10)
        await viewModel.loadIfNeeded(for: tableID, columns: columns)
        try await Task.sleep(for: .milliseconds(10))

        guard let row = viewModel.rows.first else {
            Issue.record("Missing expected row")
            return
        }

        viewModel.updateCell(id: row.id, column: "name", text: "")
        await viewModel.commitRow(row.id)

        #expect(viewModel.rows.first?.error?.contains("requires a value") == true)
        #expect(viewModel.bannerError?.isEmpty == false)
    }

    @Test
    func deleteSelectedRowsAggregatesErrors() async throws {
        let failingOne = DatabaseTableRow(id: UUID(), values: DatabaseQueryRow(values: ["id": .int(1)]))
        let failingTwo = DatabaseTableRow(id: UUID(), values: DatabaseQueryRow(values: ["id": .int(2)]))
        let succeed = DatabaseTableRow(id: UUID(), values: DatabaseQueryRow(values: ["id": .int(3)]))
        let service = FailingDeleteService(
            columns: columns,
            seedRows: [failingOne, failingTwo, succeed],
            failingIDs: [failingOne.id, failingTwo.id]
        )
        let viewModel = DatabaseTableContentViewModel(tableDataService: service, pageSize: 10)
        await viewModel.loadIfNeeded(for: tableID, columns: columns)

        viewModel.selection = [failingOne.id, failingTwo.id, succeed.id]
        await viewModel.deleteSelectedRows()

        #expect(viewModel.rows.count == 2)
        #expect(viewModel.selection == Set([failingOne.id, failingTwo.id]))
        #expect(viewModel.bannerError?.contains(failingOne.id.uuidString) == true)
        #expect(viewModel.bannerError?.contains(failingTwo.id.uuidString) == true)
    }

    @Test
    func previewServiceDoesNotClearStateWhenPagingBeyondEnd() async throws {
        let service = PreviewDatabaseTableDataService()
        let tableID = DatabaseTableIdentifier(catalog: "main", namespace: "public", name: "artists")

        let firstPage = try await service.fetchPage(for: tableID, page: 0, pageSize: 10)
        let initialCount = firstPage.rows.count

        let emptyPage = try await service.fetchPage(for: tableID, page: 10, pageSize: 10)
        #expect(emptyPage.rows.isEmpty)

        let refreshed = try await service.fetchPage(for: tableID, page: 0, pageSize: 10)
        #expect(refreshed.rows.count == initialCount)
    }
}

private actor MockTableDataService: DatabaseTableDataService {
    private var storage: [DatabaseTableIdentifier: (columns: [DatabaseColumn], rows: [DatabaseTableRow])]

    init(columns: [DatabaseColumn], seedRows: [DatabaseTableRow]) {
        let tableID = DatabaseTableIdentifier(catalog: "main", namespace: "public", name: "artists")
        storage = [tableID: (columns: columns, rows: seedRows)]
    }

    func fetchPage(for table: DatabaseTableIdentifier, page: Int, pageSize: Int) async throws -> DatabaseTablePage {
        guard let state = storage[table] else {
            throw PreviewDatabaseTableDataServiceError.tableNotFound(table)
        }
        let start = max(0, page * pageSize)
        let end = min(state.rows.count, start + pageSize)
        let rows = start < end ? Array(state.rows[start..<end]) : []
        let hasMore = end < state.rows.count
        return DatabaseTablePage(columns: state.columns, rows: rows, hasMore: hasMore)
    }

    func updateRow(
        for table: DatabaseTableIdentifier,
        row: DatabaseTableRow,
        changedValues: [String: DatabaseQueryValue]
    ) async throws -> DatabaseTableRow {
        guard var state = storage[table] else {
            throw PreviewDatabaseTableDataServiceError.tableNotFound(table)
        }
        guard let index = state.rows.firstIndex(where: { $0.id == row.id }) else {
            throw PreviewDatabaseTableDataServiceError.rowNotFound
        }
        var merged = row.values.values
        for (key, value) in changedValues {
            merged[key] = value
        }
        let updated = DatabaseTableRow(id: row.id, values: DatabaseQueryRow(values: merged))
        state.rows[index] = updated
        storage[table] = state
        return updated
    }

    func insertRow(for table: DatabaseTableIdentifier, values: [String: DatabaseQueryValue]) async throws -> DatabaseTableRow {
        guard var state = storage[table] else {
            throw PreviewDatabaseTableDataServiceError.tableNotFound(table)
        }
        var merged = Dictionary(uniqueKeysWithValues: state.columns.map { ($0.name, DatabaseQueryValue.null) })
        for (key, value) in values {
            merged[key] = value
        }
        let newRow = DatabaseTableRow(values: DatabaseQueryRow(values: merged))
        state.rows.insert(newRow, at: 0)
        storage[table] = state
        return newRow
    }

    func deleteRow(for table: DatabaseTableIdentifier, row: DatabaseTableRow) async throws {
        guard var state = storage[table] else {
            throw PreviewDatabaseTableDataServiceError.tableNotFound(table)
        }
        state.rows.removeAll { $0.id == row.id }
        storage[table] = state
    }

    func snapshot(for table: DatabaseTableIdentifier) async -> [DatabaseTableRow] {
        storage[table]?.rows ?? []
    }
}

private actor FailingDeleteService: DatabaseTableDataService {
    private var storage: [DatabaseTableIdentifier: (columns: [DatabaseColumn], rows: [DatabaseTableRow])]
    private let failingIDs: Set<UUID>

    init(columns: [DatabaseColumn], seedRows: [DatabaseTableRow], failingIDs: Set<UUID>) {
        let tableID = DatabaseTableIdentifier(catalog: "main", namespace: "public", name: "artists")
        storage = [tableID: (columns: columns, rows: seedRows)]
        self.failingIDs = failingIDs
    }

    func fetchPage(for table: DatabaseTableIdentifier, page: Int, pageSize: Int) async throws -> DatabaseTablePage {
        guard let state = storage[table] else {
            throw PreviewDatabaseTableDataServiceError.tableNotFound(table)
        }
        let start = max(0, page * pageSize)
        let end = min(state.rows.count, start + pageSize)
        let rows = start < end ? Array(state.rows[start..<end]) : []
        let hasMore = end < state.rows.count
        return DatabaseTablePage(columns: state.columns, rows: rows, hasMore: hasMore)
    }

    func updateRow(
        for table: DatabaseTableIdentifier,
        row: DatabaseTableRow,
        changedValues: [String: DatabaseQueryValue]
    ) async throws -> DatabaseTableRow {
        guard var state = storage[table] else {
            throw PreviewDatabaseTableDataServiceError.tableNotFound(table)
        }
        guard let index = state.rows.firstIndex(where: { $0.id == row.id }) else {
            throw PreviewDatabaseTableDataServiceError.rowNotFound
        }
        var merged = row.values.values
        for (key, value) in changedValues {
            merged[key] = value
        }
        let updated = DatabaseTableRow(id: row.id, values: DatabaseQueryRow(values: merged))
        state.rows[index] = updated
        storage[table] = state
        return updated
    }

    func insertRow(for table: DatabaseTableIdentifier, values: [String: DatabaseQueryValue]) async throws -> DatabaseTableRow {
        guard var state = storage[table] else {
            throw PreviewDatabaseTableDataServiceError.tableNotFound(table)
        }
        var merged = Dictionary(uniqueKeysWithValues: state.columns.map { ($0.name, DatabaseQueryValue.null) })
        for (key, value) in values {
            merged[key] = value
        }
        let newRow = DatabaseTableRow(values: DatabaseQueryRow(values: merged))
        state.rows.insert(newRow, at: 0)
        storage[table] = state
        return newRow
    }

    func deleteRow(for table: DatabaseTableIdentifier, row: DatabaseTableRow) async throws {
        guard var state = storage[table] else {
            throw PreviewDatabaseTableDataServiceError.tableNotFound(table)
        }
        if failingIDs.contains(row.id) {
            throw FailingDeleteError.cannotDelete(row.id)
        }
        state.rows.removeAll { $0.id == row.id }
        storage[table] = state
    }
}

private enum FailingDeleteError: LocalizedError {
    case cannotDelete(UUID)

    var errorDescription: String? {
        switch self {
        case .cannotDelete(let id):
            return "Failed to delete row \(id.uuidString)"
        }
    }
}
