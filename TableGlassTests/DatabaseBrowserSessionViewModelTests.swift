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
        let connection = MockDatabaseConnection(
            profile: profile,
            metadata: .schema(DatabaseSchema(catalogs: [])),
            routes: [
                .sqlEquals(
                    "SELECT 1",
                    response: .result(DatabaseQueryResult(rows: [], affectedRowCount: 0))
                )
            ]
        )
        try await connection.connect()
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

    @Test
    func setAccessModeUpdatesStateAsynchronously() async throws {
        let controller = RecordingModeController(initialMode: .readOnly)
        let session = DatabaseBrowserSessionViewModel(
            databaseName: "preview",
            status: .readOnly,
            isReadOnly: true,
            metadataProvider: PreviewDatabaseMetadataProvider(schema: .previewBrowserSchema),
            modeController: controller
        )

        await session.setAccessMode(.writable)

        let recordedModes = await controller.recordedModes()
        #expect(recordedModes == [.writable])
        #expect(session.isReadOnly == false)
        #expect(session.status == .online)
        #expect(session.modeError == nil)
        #expect(session.isUpdatingMode == false)
    }

    @Test
    func setAccessModeDoesNotOverridePendingOrErrorStatus() async throws {
        let connectingController = RecordingModeController(initialMode: .readOnly)
        let connectingSession = DatabaseBrowserSessionViewModel(
            databaseName: "preview",
            status: .connecting,
            isReadOnly: true,
            metadataProvider: PreviewDatabaseMetadataProvider(schema: .previewBrowserSchema),
            modeController: connectingController
        )

        await connectingSession.setAccessMode(.writable)

        let connectingModes = await connectingController.recordedModes()
        #expect(connectingModes == [.writable])
        #expect(connectingSession.isReadOnly == false)
        #expect(connectingSession.status == .connecting)

        let errorController = RecordingModeController(initialMode: .writable)
        let errorSession = DatabaseBrowserSessionViewModel(
            databaseName: "preview",
            status: .error,
            isReadOnly: false,
            metadataProvider: PreviewDatabaseMetadataProvider(schema: .previewBrowserSchema),
            modeController: errorController
        )

        await errorSession.setAccessMode(.readOnly)

        let errorModes = await errorController.recordedModes()
        #expect(errorModes == [.readOnly])
        #expect(errorSession.isReadOnly == true)
        #expect(errorSession.status == .error)
    }

    @Test
    func modeChangeConfirmationRequiresAcknowledgement() {
        var state = ModeChangeConfirmationState()
        state.prepare(for: .writable)

        #expect(state.canConfirm == false)

        state.hasAcknowledged = true
        #expect(state.canConfirm == true)

        state.beginApplying()
        #expect(state.canConfirm == false)

        state.finish()
        #expect(state.pendingMode == nil)
        #expect(state.hasAcknowledged == false)
        #expect(state.isApplying == false)
    }

    @Test
    func defaultSelectSQLQuotesIdentifiers() {
        let identifier = DatabaseTableIdentifier(
            catalog: "main",
            namespace: "public",
            name: "albums \"live\""
        )

        let sql = identifier.defaultSelectSQL(limit: 50)

        #expect(sql == #"SELECT * FROM "public"."albums ""live""" LIMIT 50;"#)
    }

    @Test
    func defaultSelectSQLHandlesEmptySchemaAndLimit() {
        let identifier = DatabaseTableIdentifier(
            catalog: "main",
            namespace: "",
            name: "artists"
        )

        let sql = identifier.defaultSelectSQL(limit: 0)

        #expect(sql == #"SELECT * FROM "artists" LIMIT 1;"#)
    }
}

private actor RecordingModeController: DatabaseSessionModeControlling {
    private var mode: DatabaseAccessMode
    private var updates: [DatabaseAccessMode] = []

    init(initialMode: DatabaseAccessMode) {
        self.mode = initialMode
    }

    var currentMode: DatabaseAccessMode {
        mode
    }

    func setMode(_ mode: DatabaseAccessMode) async throws {
        try await Task.sleep(for: .milliseconds(10))
        self.mode = mode
        updates.append(mode)
    }

    func recordedModes() async -> [DatabaseAccessMode] {
        updates
    }
}
