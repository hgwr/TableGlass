import Foundation
import TableGlassKit

enum PreviewDatabaseTableDataServiceError: LocalizedError {
    case tableNotFound(DatabaseTableIdentifier)
    case rowNotFound

    var errorDescription: String? {
        switch self {
        case .tableNotFound(let identifier):
            return "No data service configured for \(identifier.namespace).\(identifier.name)."
        case .rowNotFound:
            return "Row could not be located."
        }
    }
}

actor PreviewDatabaseTableDataService: DatabaseTableDataService {
    private struct TableState {
        var columns: [DatabaseColumn]
        var rows: [DatabaseTableRow]
    }

    private var tables: [DatabaseTableIdentifier: TableState]

    init(schema: DatabaseSchema = .previewBrowserSchema) {
        var storage: [DatabaseTableIdentifier: TableState] = [:]

        for catalog in schema.catalogs {
            for namespace in catalog.namespaces {
                for table in namespace.tables {
                    let identifier = DatabaseTableIdentifier(
                        catalog: catalog.name,
                        namespace: namespace.name,
                        name: table.name
                    )
                    storage[identifier] = TableState(
                        columns: table.columns,
                        rows: Self.seedRows(for: identifier)
                    )
                }
            }
        }

        tables = storage
    }

    func fetchPage(for table: DatabaseTableIdentifier, page: Int, pageSize: Int) async throws -> DatabaseTablePage {
        guard var state = tables[table] else {
            throw PreviewDatabaseTableDataServiceError.tableNotFound(table)
        }

        let start = max(0, page * pageSize)
        let end = min(state.rows.count, start + pageSize)
        if start >= state.rows.count {
            state.rows = []
        }
        tables[table] = state
        let slice = start < end ? Array(state.rows[start..<end]) : []
        let hasMore = end < state.rows.count

        return DatabaseTablePage(columns: state.columns, rows: slice, hasMore: hasMore)
    }

    func updateRow(
        for table: DatabaseTableIdentifier,
        row: DatabaseTableRow,
        changedValues: [String: DatabaseQueryValue]
    ) async throws -> DatabaseTableRow {
        guard var state = tables[table] else {
            throw PreviewDatabaseTableDataServiceError.tableNotFound(table)
        }
        guard let index = state.rows.firstIndex(where: { $0.id == row.id }) else {
            throw PreviewDatabaseTableDataServiceError.rowNotFound
        }

        var mergedValues = row.values.values
        for (key, value) in changedValues {
            mergedValues[key] = value
        }
        let updatedRow = DatabaseTableRow(id: row.id, values: DatabaseQueryRow(values: mergedValues))
        state.rows[index] = updatedRow
        tables[table] = state
        return updatedRow
    }

    func insertRow(for table: DatabaseTableIdentifier, values: [String: DatabaseQueryValue]) async throws -> DatabaseTableRow {
        guard var state = tables[table] else {
            throw PreviewDatabaseTableDataServiceError.tableNotFound(table)
        }

        var mergedValues: [String: DatabaseQueryValue] = Dictionary(uniqueKeysWithValues: state.columns.map { column in
            (column.name, column.defaultValue ?? .null)
        })
        for (key, value) in values {
            mergedValues[key] = value
        }

        let newRow = DatabaseTableRow(values: DatabaseQueryRow(values: mergedValues))
        state.rows.insert(newRow, at: 0)
        tables[table] = state
        return newRow
    }

    func deleteRow(for table: DatabaseTableIdentifier, row: DatabaseTableRow) async throws {
        guard var state = tables[table] else {
            throw PreviewDatabaseTableDataServiceError.tableNotFound(table)
        }
        guard let index = state.rows.firstIndex(where: { $0.id == row.id }) else {
            throw PreviewDatabaseTableDataServiceError.rowNotFound
        }
        state.rows.remove(at: index)
        tables[table] = state
    }
}

private extension PreviewDatabaseTableDataService {
    static func seedRows(for table: DatabaseTableIdentifier) -> [DatabaseTableRow] {
        switch table.name {
        case "artists":
            return [
                DatabaseTableRow(values: DatabaseQueryRow(values: [
                    "id": .int(1),
                    "name": .string("Alice & The Cats"),
                    "country": .string("US"),
                ])),
                DatabaseTableRow(values: DatabaseQueryRow(values: [
                    "id": .int(2),
                    "name": .string("Neon Rivers"),
                    "country": .string("DE"),
                ])),
            ]
        case "albums":
            return [
                DatabaseTableRow(values: DatabaseQueryRow(values: [
                    "id": .int(1),
                    "artist_id": .int(1),
                    "title": .string("Arcade Nights"),
                ])),
                DatabaseTableRow(values: DatabaseQueryRow(values: [
                    "id": .int(2),
                    "artist_id": .int(2),
                    "title": .string("Lakeside"),
                ])),
            ]
        default:
            return []
        }
    }
}
