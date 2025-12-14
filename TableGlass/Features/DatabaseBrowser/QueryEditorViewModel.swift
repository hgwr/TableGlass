import Combine
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import TableGlassKit

struct RowDetailSelection: Equatable {
    var rowIndex: Int
    var focusedColumn: String?
}

enum RowCopyFormat: String, CaseIterable {
    case tsv
    case json

    var title: String {
        switch self {
        case .tsv:
            return "TSV"
        case .json:
            return "JSON"
        }
    }
}

struct RowDetailField: Identifiable, Equatable {
    let name: String
    let value: String

    var id: String { name }
}

@MainActor
final class DatabaseQueryEditorViewModel: ObservableObject {
    @Published var sqlText: String {
        didSet {
            guard !isApplyingHistoryEntry else { return }
            resetHistoryNavigation()
        }
    }
    @Published private(set) var isExecuting: Bool = false
    @Published private(set) var result: DatabaseQueryResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isHistorySearchPresented: Bool = false
    @Published var historySearchQuery: String = "" {
        didSet {
            scheduleHistorySearch(resetSelection: true)
        }
    }
    @Published private(set) var historySearchResults: [String] = []
    @Published private(set) var historySearchPreview: String?
    @Published private(set) var lastExecutionDuration: Duration?
    @Published private(set) var resultColumns: [String] = []
    @Published var isRowDetailPresented: Bool = false
    @Published private(set) var rowDetailSelection: RowDetailSelection?
    @Published var rowDetailCopyFormat: RowCopyFormat = .tsv

    private let executor: @Sendable (DatabaseQueryRequest) async throws -> DatabaseQueryResult
    private let history: DatabaseQueryHistory
    private var queuedExecutionReadOnly: Bool?
    private var historyNavigationIndex: Int?
    private var historyRestoreBuffer: String?
    private var historyCache: [String] = []
    private var historySearchSelectionIndex: Int?
    private var isApplyingHistoryEntry = false
    private var historySearchTask: Task<Void, Never>?

    init(
        sqlText: String = "SELECT * FROM artists LIMIT 50",
        history: DatabaseQueryHistory = DatabaseQueryHistory(),
        executor: @escaping @Sendable (DatabaseQueryRequest) async throws -> DatabaseQueryResult
    ) {
        self.sqlText = sqlText
        self.history = history
        self.executor = executor

        Task { await self.reloadHistory() }
    }

    func requestExecute(isReadOnly: Bool) {
        queuedExecutionReadOnly = isReadOnly
        Task { @MainActor in
            await self.runQueuedExecutesIfNeeded()
        }
    }

    func execute(isReadOnly: Bool) async {
        let sql = sqlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sql.isEmpty else { return }

        if isReadOnly && !allowsReadOnlyExecution(for: sql) {
            errorMessage = "Read-only mode prevents running this statement."
            lastExecutionDuration = nil
            return
        }

        isExecuting = true
        errorMessage = nil
        defer {
            isExecuting = false
            if queuedExecutionReadOnly != nil {
                Task { @MainActor in
                    await self.runQueuedExecutesIfNeeded()
                }
            }
        }

        do {
            let request = DatabaseQueryRequest(sql: sql)
            let clock = ContinuousClock()
            let start = clock.now
            let queryResult = try await executor(request)
            lastExecutionDuration = start.duration(to: clock.now)
            applyResult(queryResult)
        } catch {
            clearResultState()
            lastExecutionDuration = nil
            errorMessage = error.localizedDescription
        }

        await recordHistoryEntry(sql)
    }

    private func runQueuedExecutesIfNeeded() async {
        guard !isExecuting else { return }
        while let readOnly = queuedExecutionReadOnly {
            queuedExecutionReadOnly = nil
            await execute(isReadOnly: readOnly)
        }
    }

    // MARK: - Row detail

    func presentRowDetail(forRowAt index: Int) {
        guard let result, result.rows.indices.contains(index) else { return }
        let focused = validatedColumn(rowDetailSelection?.focusedColumn)
        rowDetailSelection = RowDetailSelection(rowIndex: index, focusedColumn: focused)
        isRowDetailPresented = true
    }

    func selectRowForDetail(_ index: Int) {
        guard let result, result.rows.indices.contains(index) else { return }
        let focused = validatedColumn(rowDetailSelection?.focusedColumn)
        rowDetailSelection = RowDetailSelection(rowIndex: index, focusedColumn: focused)
    }

    func toggleRowDetail(forRowAt index: Int? = nil) {
        guard let result, !result.rows.isEmpty else { return }
        guard !isRowDetailPresented else {
            isRowDetailPresented = false
            return
        }

        if let index {
            presentRowDetail(forRowAt: index)
        } else if let selection = rowDetailSelection {
            presentRowDetail(forRowAt: selection.rowIndex)
        } else {
            presentRowDetail(forRowAt: 0)
        }
    }

    func focusRowDetailField(_ column: String?) {
        guard let selection = rowDetailSelection else { return }
        let columnName = validatedColumn(column) ?? selection.focusedColumn
        rowDetailSelection = RowDetailSelection(rowIndex: selection.rowIndex, focusedColumn: columnName)
    }

    func detailFields(for selection: RowDetailSelection) -> [RowDetailField] {
        guard let result, result.rows.indices.contains(selection.rowIndex) else { return [] }
        let row = result.rows[selection.rowIndex]
        return resultColumns.map { column in
            let value = DatabaseTableContentViewModel.displayText(from: row.values[column])
            return RowDetailField(name: column, value: value)
        }
    }

    func copyCurrentDetailSelectionToClipboard() {
        guard isRowDetailPresented, let selection = rowDetailSelection else { return }
        if let column = selection.focusedColumn {
            copyField(column, inRow: selection.rowIndex)
            return
        }
        copyRow(at: selection.rowIndex, format: rowDetailCopyFormat)
    }

    func copyField(_ column: String, inRow rowIndex: Int? = nil) {
        guard let index = rowIndex ?? rowDetailSelection?.rowIndex else { return }
        guard let payload = fieldString(column, rowIndex: index) else { return }
        writeToClipboard(payload)
    }

    func copyRow(at rowIndex: Int, format: RowCopyFormat) {
        guard let payload = rowString(forRowAt: rowIndex, format: format) else { return }
        writeToClipboard(payload)
    }

    func rowString(forRowAt rowIndex: Int, format: RowCopyFormat) -> String? {
        guard let result, result.rows.indices.contains(rowIndex) else { return nil }
        let row = result.rows[rowIndex]
        switch format {
        case .tsv:
            let values = resultColumns.map { column in
                DatabaseTableContentViewModel.displayText(from: row.values[column])
            }
            return values.joined(separator: "\t")
        case .json:
            let object = Dictionary(uniqueKeysWithValues: resultColumns.map { column in
                (column, jsonValue(from: row.values[column]))
            })
            guard JSONSerialization.isValidJSONObject(object) else { return nil }
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return data.flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    func fieldString(_ column: String, rowIndex: Int) -> String? {
        guard let result, result.rows.indices.contains(rowIndex) else { return nil }
        guard resultColumns.contains(column) else { return nil }
        let row = result.rows[rowIndex]
        return DatabaseTableContentViewModel.displayText(from: row.values[column])
    }

    private func applyResult(_ queryResult: DatabaseQueryResult) {
        result = queryResult
        resultColumns = Self.columns(from: queryResult)
        if isRowDetailPresented && rowDetailSelection == nil, !queryResult.rows.isEmpty {
            rowDetailSelection = RowDetailSelection(rowIndex: 0, focusedColumn: nil)
        }
        clampRowDetailSelection(rowCount: queryResult.rows.count)
    }

    private func clearResultState() {
        result = nil
        resultColumns = []
        clearRowDetail()
    }

    private func clampRowDetailSelection(rowCount: Int) {
        guard let selection = rowDetailSelection else { return }
        guard rowCount > 0 else {
            clearRowDetail()
            return
        }
        let rowIndex = min(selection.rowIndex, max(rowCount - 1, 0))
        let focusedColumn = validatedColumn(selection.focusedColumn)
        rowDetailSelection = RowDetailSelection(rowIndex: rowIndex, focusedColumn: focusedColumn)
    }

    private func clearRowDetail() {
        rowDetailSelection = nil
        isRowDetailPresented = false
    }

    private func jsonValue(from value: DatabaseQueryValue?) -> Any {
        guard let value else { return NSNull() }
        switch value {
        case .null:
            return NSNull()
        case .bool(let bool):
            return bool
        case .int(let int):
            return int
        case .decimal(let decimal):
            return NSDecimalNumber(decimal: decimal)
        case .double(let double):
            return double
        case .string(let string):
            return string
        case .date(let date):
            return Self.iso8601Formatter.string(from: date)
        case .data(let data):
            return data.base64EncodedString()
        case .uuid(let uuid):
            return uuid.uuidString
        }
    }

    private func validatedColumn(_ column: String?) -> String? {
        guard let column, resultColumns.contains(column) else { return nil }
        return column
    }

    private func writeToClipboard(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    func allowsReadOnlyExecution(for sql: String? = nil) -> Bool {
        let trimmed = (sql ?? sqlText).trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed
            .lowercased()
            .split { !$0.isLetter }
            .map(String.init)

        guard let first = tokens.first else { return false }

        let readOnlyKeywords: Set<String> = ["select", "with", "show", "describe", "desc", "explain", "pragma"]
        let mutationKeywords: Set<String> = [
            "insert",
            "update",
            "delete",
            "drop",
            "alter",
            "truncate",
            "create",
            "replace",
            "merge",
            "grant",
            "revoke",
            "call",
            "execute"
        ]

        if tokens.contains(where: { mutationKeywords.contains($0) }) {
            return false
        }

        return readOnlyKeywords.contains(first)
    }

    func loadPreviousHistoryEntry() {
        guard !historyCache.isEmpty else { return }

        if historyNavigationIndex == nil {
            historyRestoreBuffer = sqlText
            historyNavigationIndex = 0
        } else if let index = historyNavigationIndex, index + 1 < historyCache.count {
            historyNavigationIndex = index + 1
        }

        guard let index = historyNavigationIndex,
              historyCache.indices.contains(index) else { return }
        applyHistoryEntry(historyCache[index])
    }

    func loadNextHistoryEntry() {
        guard let index = historyNavigationIndex else { return }
        let nextIndex = index - 1

        if nextIndex >= 0, historyCache.indices.contains(nextIndex) {
            historyNavigationIndex = nextIndex
            applyHistoryEntry(historyCache[nextIndex])
            return
        }

        historyNavigationIndex = nil
        let restored = historyRestoreBuffer ?? sqlText
        historyRestoreBuffer = nil
        applyHistoryEntry(restored)
    }

    func beginHistorySearch() {
        isHistorySearchPresented = true
        historySearchSelectionIndex = nil
        historySearchQuery = ""
        scheduleHistorySearch(resetSelection: true)
    }

    func cancelHistorySearch() {
        historySearchTask?.cancel()
        historySearchTask = nil
        isHistorySearchPresented = false
        historySearchSelectionIndex = nil
        historySearchResults = []
        historySearchPreview = nil
        historySearchQuery = ""
    }

    func acceptHistorySearchMatch() -> String? {
        guard let match = currentHistorySearchMatch else { return nil }
        applyHistoryEntry(match)
        cancelHistorySearch()
        return match
    }

    func selectNextHistorySearchMatch() {
        guard !historySearchResults.isEmpty else { return }
        let nextIndex: Int
        if let selection = historySearchSelectionIndex {
            nextIndex = max(selection - 1, 0)
        } else {
            nextIndex = 0
        }
        historySearchSelectionIndex = nextIndex
        updateHistorySearchPreview()
    }

    func selectPreviousHistorySearchMatch() {
        guard !historySearchResults.isEmpty else { return }
        let nextIndex: Int
        if let selection = historySearchSelectionIndex {
            nextIndex = min(selection + 1, historySearchResults.count - 1)
        } else {
            nextIndex = 0
        }
        historySearchSelectionIndex = nextIndex
        updateHistorySearchPreview()
    }

    private func applyHistoryEntry(_ sql: String) {
        isApplyingHistoryEntry = true
        sqlText = sql
        isApplyingHistoryEntry = false
    }

    private func resetHistoryNavigation() {
        historyNavigationIndex = nil
        historyRestoreBuffer = nil
    }

    private func recordHistoryEntry(_ sql: String) async {
        await history.append(sql)
        await reloadHistory()
        resetHistoryNavigation()
    }

    private func reloadHistory() async {
        historyCache = await history.snapshot()
        if let index = historyNavigationIndex, index >= historyCache.count {
            resetHistoryNavigation()
        }
        if isHistorySearchPresented {
            await refreshHistorySearch(resetSelection: historySearchSelectionIndex == nil)
        }
    }

    private func scheduleHistorySearch(resetSelection: Bool) {
        historySearchTask?.cancel()
        historySearchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            await self?.refreshHistorySearch(resetSelection: resetSelection)
        }
    }

    private func refreshHistorySearch(resetSelection: Bool = false) async {
        guard isHistorySearchPresented else { return }
        historySearchTask = nil
        historySearchResults = await history.search(containing: historySearchQuery)

        if resetSelection {
            historySearchSelectionIndex = historySearchResults.isEmpty ? nil : 0
        } else if let selection = historySearchSelectionIndex,
                  selection >= historySearchResults.count {
            historySearchSelectionIndex = historySearchResults.isEmpty ? nil : historySearchResults.count - 1
        }

        updateHistorySearchPreview()
    }

    private func updateHistorySearchPreview() {
        historySearchPreview = currentHistorySearchMatch
    }

    private var currentHistorySearchMatch: String? {
        if let index = historySearchSelectionIndex,
           historySearchResults.indices.contains(index) {
            return historySearchResults[index]
        }
        return historySearchResults.first
    }

    private static func columns(from result: DatabaseQueryResult) -> [String] {
        let keys = result.rows.flatMap { $0.values.keys }
        return Array(Set(keys)).sorted()
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
