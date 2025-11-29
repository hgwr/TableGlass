import Foundation
import TableGlassKit
import Testing

@testable import TableGlass

@MainActor
struct DatabaseQueryEditorViewModelTests {

    @Test
    func executesQueriesAndPublishesResults() async throws {
        let executor = MockDatabaseQueryExecutor(
            routes: [
                .sqlEquals(
                    "SELECT 1",
                    response: .result(DatabaseQueryResult(rows: [DatabaseQueryRow(values: ["id": .int(1)])]))
                )
            ]
        )
        let viewModel = DatabaseQueryEditorViewModel(executor: executor.execute)
        viewModel.sqlText = "SELECT 1"

        await viewModel.execute(isReadOnly: false)

        #expect(viewModel.result?.rows.first?.values["id"] == .int(1))
        let requests = await executor.recordedRequests()
        #expect(requests == [DatabaseQueryRequest(sql: "SELECT 1")])
    }

    @Test
    func readOnlyModeBlocksMutations() async throws {
        let executor = MockDatabaseQueryExecutor()
        let viewModel = DatabaseQueryEditorViewModel(executor: executor.execute)
        viewModel.sqlText = "DELETE FROM artists"

        await viewModel.execute(isReadOnly: true)

        #expect(viewModel.errorMessage?.contains("Read-only") == true)
        let requests = await executor.recordedRequests()
        #expect(requests.isEmpty)
    }

    @Test
    func readOnlyModeBlocksCTEMutations() async throws {
        let executor = MockDatabaseQueryExecutor()
        let viewModel = DatabaseQueryEditorViewModel(executor: executor.execute)
        viewModel.sqlText = """
        WITH cte AS (
            SELECT * FROM artists
        )
        DELETE FROM artists WHERE id IN (SELECT id FROM cte)
        """

        await viewModel.execute(isReadOnly: true)

        #expect(viewModel.errorMessage?.contains("Read-only") == true)
        let requests = await executor.recordedRequests()
        #expect(requests.isEmpty)
    }

    @Test
    func errorsSurfaceWithRetryOption() async throws {
        let executor = MockDatabaseQueryExecutor(defaultResponse: .failure(QueryExecutorError.failed))
        let viewModel = DatabaseQueryEditorViewModel(executor: executor.execute)
        viewModel.sqlText = "SELECT * FROM broken"

        await viewModel.execute(isReadOnly: false)

        #expect(viewModel.result == nil)
        #expect(viewModel.errorMessage == QueryExecutorError.failed.localizedDescription)

        await executor.updateDefaultResponse(
            .result(DatabaseQueryResult(rows: [DatabaseQueryRow(values: ["name": .string("ok")])]))
        )

        await viewModel.execute(isReadOnly: false)

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.result?.rows.first?.values["name"] == .string("ok"))
        let requests = await executor.recordedRequests()
        #expect(requests.count == 2)
    }

    @Test
    func executionAppendsToSessionLog() async throws {
        let log = DatabaseQueryLog(capacity: 5)
        let executor = MockDatabaseQueryExecutor(
            routes: [
                .sqlEquals(
                    "SELECT * FROM artists",
                    response: .result(DatabaseQueryResult(rows: [DatabaseQueryRow(values: ["ok": .bool(true)])]))
                )
            ]
        )

        let session = DatabaseBrowserSessionViewModel(
            databaseName: "stub",
            status: .online,
            isReadOnly: false,
            metadataProvider: PreviewDatabaseMetadataProvider(schema: .previewBrowserSchema),
            queryExecutor: executor,
            queryLog: log
        )

        let viewModel = session.makeQueryEditorViewModel()
        viewModel.sqlText = "SELECT * FROM artists"

        await viewModel.execute(isReadOnly: false)

        let entries = await log.entriesSnapshot()
        #expect(entries.count == 1)
        #expect(entries.first?.sql == "SELECT * FROM artists")
        #expect(entries.first?.outcome == .success)
    }

    @Test
    func recordsHistoryEntriesAndDeduplicates() async throws {
        let history = DatabaseQueryHistory()
        let executor = MockDatabaseQueryExecutor(
            routes: [
                .sqlEquals(
                    "SELECT * FROM artists",
                    response: .result(DatabaseQueryResult(rows: [DatabaseQueryRow(values: [:])]))
                ),
                .sqlEquals(
                    "DELETE FROM tracks",
                    response: .result(DatabaseQueryResult(rows: []))
                )
            ],
            defaultResponse: .result(DatabaseQueryResult(rows: []))
        )

        let viewModel = DatabaseQueryEditorViewModel(history: history, executor: executor.execute)
        viewModel.sqlText = "SELECT * FROM artists"
        await viewModel.execute(isReadOnly: false)
        viewModel.sqlText = "SELECT * FROM artists"
        await viewModel.execute(isReadOnly: false)
        viewModel.sqlText = "DELETE FROM tracks"
        await viewModel.execute(isReadOnly: false)

        let snapshot = await history.snapshot()
        #expect(snapshot == ["DELETE FROM tracks", "SELECT * FROM artists"])
    }

    @Test
    func historyNavigationRestoresUnsubmittedText() async throws {
        let history = DatabaseQueryHistory()
        let executor = MockDatabaseQueryExecutor(defaultResponse: .result(DatabaseQueryResult(rows: [])))
        let viewModel = DatabaseQueryEditorViewModel(history: history, executor: executor.execute)
        viewModel.sqlText = "SELECT 1"
        await viewModel.execute(isReadOnly: false)
        viewModel.sqlText = "SELECT 2"
        await viewModel.execute(isReadOnly: false)

        viewModel.sqlText = "draft"
        viewModel.loadPreviousHistoryEntry()
        #expect(viewModel.sqlText == "SELECT 2")
        viewModel.loadPreviousHistoryEntry()
        #expect(viewModel.sqlText == "SELECT 1")
        viewModel.loadNextHistoryEntry()
        #expect(viewModel.sqlText == "SELECT 2")
        viewModel.loadNextHistoryEntry()
        #expect(viewModel.sqlText == "draft")
    }

    @Test
    func incrementalHistorySearchFiltersMatches() async throws {
        let history = DatabaseQueryHistory()
        let executor = MockDatabaseQueryExecutor(defaultResponse: .result(DatabaseQueryResult(rows: [])))
        let viewModel = DatabaseQueryEditorViewModel(history: history, executor: executor.execute)
        viewModel.sqlText = "SELECT * FROM artists"
        await viewModel.execute(isReadOnly: false)
        viewModel.sqlText = "DELETE FROM albums"
        await viewModel.execute(isReadOnly: false)
        viewModel.sqlText = "SELECT * FROM albums WHERE artist_id = 1"
        await viewModel.execute(isReadOnly: false)

        viewModel.beginHistorySearch()
        viewModel.historySearchQuery = "albums"
        try await Task.sleep(for: .milliseconds(10))

        #expect(viewModel.historySearchResults.count == 2)
        #expect(viewModel.historySearchPreview == "SELECT * FROM albums WHERE artist_id = 1")

        viewModel.selectPreviousHistorySearchMatch()
        #expect(viewModel.historySearchPreview == "DELETE FROM albums")
        viewModel.selectNextHistorySearchMatch()
        #expect(viewModel.historySearchPreview == "SELECT * FROM albums WHERE artist_id = 1")
        _ = viewModel.acceptHistorySearchMatch()
        #expect(viewModel.sqlText == "SELECT * FROM albums WHERE artist_id = 1")
        #expect(viewModel.isHistorySearchPresented == false)
    }
}

private enum QueryExecutorError: Error, LocalizedError, Sendable {
    case failed

    var errorDescription: String? { "Execution failed" }
}
