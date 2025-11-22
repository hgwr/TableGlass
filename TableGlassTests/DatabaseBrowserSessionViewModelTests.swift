import TableGlassKit
import Testing

@testable import TableGlass

@MainActor
struct DatabaseBrowserSessionViewModelTests {

    @Test
    func refreshBuildsTreeFromMetadata() async throws {
        let session = DatabaseBrowserSessionViewModel(
            databaseName: "preview",
            status: .online,
            isReadOnly: false,
            metadataProvider: PreviewDatabaseMetadataProvider(schema: .previewBrowserSchema)
        )

        await session.refresh()

        #expect(session.treeNodes.count == 2)
        let catalogNames = Set(session.treeNodes.map(\.title))
        #expect(catalogNames.contains("main"))
        #expect(catalogNames.contains("archive"))
        #expect(session.selectedNode == nil)
    }

    @Test
    func expandingLoadsChildrenLazily() async throws {
        let session = DatabaseBrowserSessionViewModel(
            databaseName: "preview",
            status: .online,
            isReadOnly: false,
            metadataProvider: PreviewDatabaseMetadataProvider(schema: .previewBrowserSchema)
        )

        await session.refresh()

        guard let mainCatalog = session.treeNodes.first(where: { $0.title == "main" }) else {
            #expect(Bool(false), "Expected main catalog to be present")
            return
        }

        let loadNamespaceTask = session.toggleExpansion(for: mainCatalog.id, isExpanded: true)
        await loadNamespaceTask?.value

        guard let publicNamespace = session.treeNodes
            .first(where: { $0.title == "main" })?
            .children
            .first(where: { $0.title == "public" }) else {
            #expect(Bool(false), "Expected public namespace after expanding main")
            return
        }

        let loadObjectsTask = session.toggleExpansion(for: publicNamespace.id, isExpanded: true)
        await loadObjectsTask?.value

        let objectNames = session.treeNodes
            .first(where: { $0.title == "main" })?
            .children
            .first(where: { $0.title == "public" })?
            .children
            .map(\.title) ?? []

        #expect(objectNames.contains("artists"))
        #expect(objectNames.contains("albums"))
        #expect(objectNames.contains("top_artists"))
    }

    @Test
    func executeQueriesAppendToLog() async throws {
        let profile = ConnectionProfile(
            name: "stub",
            kind: .sqlite,
            host: ":memory:",
            port: 0,
            username: "tester"
        )
        let connection = LoggingStubConnection(profile: profile)
        let log = DatabaseQueryLog(capacity: 5)

        let session = DatabaseBrowserSessionViewModel(
            databaseName: "stub",
            status: .online,
            isReadOnly: false,
            metadataProvider: connection,
            queryLog: log
        )

        let request = DatabaseQueryRequest(sql: "SELECT 1")
        _ = try await session.execute(request)

        let entries = await log.entriesSnapshot()
        #expect(entries.count == 1)
        #expect(entries.first?.sql == request.sql)
        #expect(entries.first?.outcome == .success)

        let recorded = await connection.recordedRequests()
        #expect(recorded == [request])
    }
}

private actor LoggingStubConnection: DatabaseConnection {
    let profile: ConnectionProfile
    private var recorded: [DatabaseQueryRequest] = []

    init(profile: ConnectionProfile) {
        self.profile = profile
    }

    func connect() async throws {}

    func disconnect() async {}

    func isConnected() async -> Bool { true }

    func beginTransaction(options: DatabaseTransactionOptions) async throws -> any DatabaseTransaction {
        throw DatabaseDriverUnavailable(driverKind: profile.kind, reason: "Not implemented")
    }

    func metadata(scope: DatabaseMetadataScope) async throws -> DatabaseSchema {
        DatabaseSchema(catalogs: [])
    }

    func execute(_ request: DatabaseQueryRequest) async throws -> DatabaseQueryResult {
        recorded.append(request)
        return DatabaseQueryResult(rows: [], affectedRowCount: 0)
    }

    func recordedRequests() async -> [DatabaseQueryRequest] {
        recorded
    }
}
