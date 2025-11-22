import TableGlassKit
import Testing

@testable import TableGlass

@MainActor
struct DatabaseQueryEditorViewModelTests {

    @Test
    func executesQueriesAndPublishesResults() async throws {
        let executor = RecordingQueryExecutor(result: DatabaseQueryResult(rows: [DatabaseQueryRow(values: ["id": .int(1)])]))
        let viewModel = DatabaseQueryEditorViewModel(executor: executor.execute)
        viewModel.sqlText = "SELECT 1"

        await viewModel.execute(isReadOnly: false)

        #expect(viewModel.result?.rows.first?.values["id"] == .int(1))
        let requests = await executor.recordedRequests()
        #expect(requests == [DatabaseQueryRequest(sql: "SELECT 1")])
    }

    @Test
    func readOnlyModeBlocksMutations() async throws {
        let executor = RecordingQueryExecutor(result: DatabaseQueryResult())
        let viewModel = DatabaseQueryEditorViewModel(executor: executor.execute)
        viewModel.sqlText = "DELETE FROM artists"

        await viewModel.execute(isReadOnly: true)

        #expect(viewModel.errorMessage?.contains("Read-only") == true)
        let requests = await executor.recordedRequests()
        #expect(requests.isEmpty)
    }

    @Test
    func errorsSurfaceWithRetryOption() async throws {
        let executor = RecordingQueryExecutor(error: SampleError.failed)
        let viewModel = DatabaseQueryEditorViewModel(executor: executor.execute)
        viewModel.sqlText = "SELECT * FROM broken"

        await viewModel.execute(isReadOnly: false)

        #expect(viewModel.result == nil)
        #expect(viewModel.errorMessage == SampleError.failed.localizedDescription)

        executor.error = nil
        executor.result = DatabaseQueryResult(rows: [DatabaseQueryRow(values: ["name": .string("ok")])])

        await viewModel.execute(isReadOnly: false)

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.result?.rows.first?.values["name"] == .string("ok"))
        let requests = await executor.recordedRequests()
        #expect(requests.count == 2)
    }

    @Test
    func executionAppendsToSessionLog() async throws {
        let log = DatabaseQueryLog(capacity: 5)
        let executor = RecordingQueryExecutor(result: DatabaseQueryResult(rows: [DatabaseQueryRow(values: ["ok": .bool(true)])]))

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

private actor RecordingQueryExecutor: DatabaseQueryExecutor {
    var result: DatabaseQueryResult?
    var error: Error?
    private var requests: [DatabaseQueryRequest] = []

    init(result: DatabaseQueryResult? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func execute(_ request: DatabaseQueryRequest) async throws -> DatabaseQueryResult {
        requests.append(request)
        if let error {
            throw error
        }
        return result ?? DatabaseQueryResult()
    }

    func recordedRequests() async -> [DatabaseQueryRequest] {
        requests
    }
}

private enum SampleError: Error, LocalizedError {
    case failed

    var errorDescription: String? { "Execution failed" }
}
