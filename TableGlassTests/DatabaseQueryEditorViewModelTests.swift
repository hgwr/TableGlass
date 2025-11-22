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
}

private enum QueryExecutorError: Error, LocalizedError, Sendable {
    case failed

    var errorDescription: String? { "Execution failed" }
}
