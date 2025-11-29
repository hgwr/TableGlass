import Combine
import Foundation
import TableGlassKit

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
            Task { await self.refreshHistorySearch(resetSelection: true) }
        }
    }
    @Published private(set) var historySearchResults: [String] = []
    @Published private(set) var historySearchPreview: String?

    private let executor: @Sendable (DatabaseQueryRequest) async throws -> DatabaseQueryResult
    private let history: DatabaseQueryHistory
    private var queuedExecutionReadOnly: Bool?
    private var historyNavigationIndex: Int?
    private var historyRestoreBuffer: String?
    private var historyCache: [String] = []
    private var historySearchSelectionIndex: Int?
    private var isApplyingHistoryEntry = false

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
            result = try await executor(request)
        } catch {
            result = nil
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
        Task { await self.refreshHistorySearch(resetSelection: true) }
    }

    func cancelHistorySearch() {
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

    private func refreshHistorySearch(resetSelection: Bool = false) async {
        guard isHistorySearchPresented else { return }
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
}
