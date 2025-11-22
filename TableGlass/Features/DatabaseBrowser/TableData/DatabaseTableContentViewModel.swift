import Combine
import Foundation
import TableGlassKit

@MainActor
final class DatabaseTableContentViewModel: ObservableObject {
    struct EditableCellValue: Equatable {
        var original: DatabaseQueryValue?
        var text: String

        var isModified: Bool {
            DatabaseTableContentViewModel.displayText(from: original) != text
        }
    }

    struct EditableTableRow: Identifiable, Equatable {
        let id: UUID
        var source: DatabaseTableRow
        var cells: [String: EditableCellValue]
        var isNew: Bool
        var isSaving: Bool
        var error: String?

        var hasChanges: Bool {
            isNew || cells.values.contains { $0.isModified }
        }
    }

    @Published private(set) var columns: [DatabaseColumn] = []
    @Published private(set) var rows: [EditableTableRow] = []
    @Published private(set) var isLoadingPage = false
    @Published private(set) var hasMorePages = false
    @Published private(set) var bannerError: String?
    @Published private(set) var isPerformingMutation = false
    @Published var selection: Set<EditableTableRow.ID> = []

    private let tableDataService: any DatabaseTableDataService
    private let pageSize: Int
    private var activeTable: DatabaseTableIdentifier?
    private var currentPage: Int = 0

    init(tableDataService: some DatabaseTableDataService, pageSize: Int = 50) {
        self.tableDataService = tableDataService
        self.pageSize = pageSize
    }

    func loadIfNeeded(for table: DatabaseTableIdentifier, columns: [DatabaseColumn]) async {
        if table != activeTable {
            resetState(for: table, columns: columns)
        } else if !columns.isEmpty {
            self.columns = columns
        }

        guard rows.isEmpty else { return }
        await loadNextPage()
    }

    func loadNextPage() async {
        guard let table = activeTable, !isLoadingPage, hasMorePages || rows.isEmpty else { return }

        isLoadingPage = true
        defer { isLoadingPage = false }

        do {
            let page = try await tableDataService.fetchPage(for: table, page: currentPage, pageSize: pageSize)
            apply(page: page)
            currentPage += 1
        } catch {
            bannerError = error.localizedDescription
        }
    }

    func addRow() {
        guard activeTable != nil else { return }
        let seedValues = Dictionary(uniqueKeysWithValues: columns.map { column in
            (column.name, column.defaultValue ?? (column.isNullable ? DatabaseQueryValue.null : DatabaseQueryValue.string("")))
        })
        let baseRow = DatabaseTableRow(values: DatabaseQueryRow(values: seedValues))
        let editable = makeEditableRow(from: baseRow, isNew: true)
        rows.insert(editable, at: 0)
        selection = [editable.id]
    }

    func commitRow(_ id: EditableTableRow.ID) async {
        guard
            let table = activeTable,
            let index = rows.firstIndex(where: { $0.id == id })
        else { return }

        var row = rows[index]

        do {
            let payload = try buildPayload(for: row)
            row.isSaving = true
            row.error = nil
            rows[index] = row
            isPerformingMutation = true
            defer { isPerformingMutation = false }

            let savedRow: DatabaseTableRow
            if row.isNew {
                savedRow = try await tableDataService.insertRow(for: table, values: payload)
            } else {
                savedRow = try await tableDataService.updateRow(for: table, row: row.source, changedValues: payload)
            }

            let updated = makeEditableRow(from: savedRow, isNew: false)
            rows[index] = updated
            selection = [updated.id]
        } catch {
            row.isSaving = false
            row.error = error.localizedDescription
            rows[index] = row
            bannerError = error.localizedDescription
        }
    }

    func deleteSelectedRows() async {
        guard let table = activeTable, !selection.isEmpty else { return }
        isPerformingMutation = true
        defer { isPerformingMutation = false }

        let ids = selection
        var deletedRowIDs: [EditableTableRow.ID] = []
        var errorMessages: [String] = []

        for id in ids {
            guard let index = rows.firstIndex(where: { $0.id == id }) else { continue }
            let row = rows[index]
            do {
                try await tableDataService.deleteRow(for: table, row: row.source)
                deletedRowIDs.append(id)
            } catch {
                errorMessages.append(error.localizedDescription)
            }
        }

        if !deletedRowIDs.isEmpty {
            rows.removeAll { deletedRowIDs.contains($0.id) }
            selection.subtract(deletedRowIDs)
        }

        if !errorMessages.isEmpty {
            bannerError = errorMessages.joined(separator: "\n")
        }
    }

    func clearBanner() {
        bannerError = nil
    }

    func updateCell(id: EditableTableRow.ID, column: String, text: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].cells[column]?.text = text
    }

    func prefetchNextPageIfNeeded(currentRowID: EditableTableRow.ID) async {
        guard !isLoadingPage, hasMorePages,
              let index = rows.firstIndex(where: { $0.id == currentRowID })
        else { return }

        let prefetchWindow = min(max(pageSize / 4, 2), 10)
        let thresholdIndex = max(rows.count - prefetchWindow, 0)
        guard rows.count > prefetchWindow, index >= thresholdIndex else { return }

        await loadNextPage()
    }

    private func resetState(for table: DatabaseTableIdentifier, columns: [DatabaseColumn]) {
        activeTable = table
        self.columns = columns
        rows = []
        selection = []
        currentPage = 0
        hasMorePages = true
        bannerError = nil
    }

    private func apply(page: DatabaseTablePage) {
        columns = page.columns.isEmpty ? columns : page.columns
        let newRows = page.rows.map { makeEditableRow(from: $0, isNew: false) }
        rows.append(contentsOf: newRows)
        hasMorePages = page.hasMore
    }

    private func makeEditableRow(from row: DatabaseTableRow, isNew: Bool) -> EditableTableRow {
        let cellPairs: [(String, EditableCellValue)] = columns.map { column in
            let value = row.values.values[column.name]
            let editable = EditableCellValue(
                original: value == .null ? nil : value,
                text: Self.displayText(from: value)
            )
            return (column.name, editable)
        }

        return EditableTableRow(
            id: row.id,
            source: row,
            cells: Dictionary(uniqueKeysWithValues: cellPairs),
            isNew: isNew,
            isSaving: false,
            error: nil
        )
    }

    private func buildPayload(for row: EditableTableRow) throws -> [String: DatabaseQueryValue] {
        var values: [String: DatabaseQueryValue] = [:]
        var validationErrors: [String] = []

        for column in columns {
            let text = row.cells[column.name]?.text ?? ""
            do {
                if let coerced = try coerceValue(text, for: column) {
                    if row.isNew || row.cells[column.name]?.isModified == true {
                        values[column.name] = coerced
                    }
                }
            } catch {
                validationErrors.append(error.localizedDescription)
            }
        }

        if !validationErrors.isEmpty {
            throw ValidationError(messages: validationErrors)
        }

        if values.isEmpty {
            throw ValidationError(messages: ["No changes to save."])
        }

        return values
    }

    private func coerceValue(_ text: String, for column: DatabaseColumn) throws -> DatabaseQueryValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard column.isNullable || column.defaultValue != nil else {
                throw ValidationError(messages: ["\(column.name) requires a value."])
            }
            return column.defaultValue ?? .null
        }

        switch column.dataType {
        case .integer:
            guard let intValue = Int64(trimmed) else { throw ValidationError(messages: ["\(column.name) must be an integer."]) }
            return .int(intValue)
        case .numeric:
            guard let decimal = Decimal(string: trimmed) else {
                throw ValidationError(messages: ["\(column.name) must be numeric."])
            }
            return .decimal(decimal)
        case .boolean:
            guard let boolValue = Bool(trimmed) ?? (trimmed == "1" ? true : (trimmed == "0" ? false : nil)) else {
                throw ValidationError(messages: ["\(column.name) must be true or false."])
            }
            return .bool(boolValue)
        case .text, .custom:
            return .string(trimmed)
        case .binary:
            return .data(Data(trimmed.utf8))
        case .timestamp(_), .date:
            return .string(trimmed)
        }
    }

    private static func displayText(from value: DatabaseQueryValue?) -> String {
        guard let value else { return "" }
        if case .null = value { return "" }
        return value.description
    }

    struct ValidationError: LocalizedError {
        let messages: [String]

        var errorDescription: String? {
            messages.joined(separator: "\n")
        }
    }
}
