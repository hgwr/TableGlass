import Combine
import Foundation
import TableGlassKit

@MainActor
final class DatabaseBrowserSessionViewModel: ObservableObject, Identifiable {
    let id: UUID
    let databaseName: String
    @Published var status: DatabaseBrowserSessionStatus
    @Published var isReadOnly: Bool
    @Published private(set) var isUpdatingMode: Bool = false
    @Published var modeError: String?
    @Published private(set) var treeNodes: [DatabaseObjectTreeNode]
    @Published var selectedNodeID: DatabaseObjectTreeNode.ID?
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var isExpandingAll: Bool = false
    @Published private(set) var loadError: String?
    let queryLog: DatabaseQueryLog

    private let metadataProvider: any DatabaseMetadataProvider
    private let metadataScope: DatabaseMetadataScope
    private let queryExecutor: (any DatabaseQueryExecutor)?
    private let modeController: (any DatabaseSessionModeControlling)?
    private let tableDataService: any DatabaseTableDataService

    init(
        id: UUID = UUID(),
        databaseName: String,
        status: DatabaseBrowserSessionStatus,
        isReadOnly: Bool,
        metadataProvider: some DatabaseMetadataProvider,
        metadataScope: DatabaseMetadataScope = DatabaseMetadataScope(),
        queryExecutor: (any DatabaseQueryExecutor)? = nil,
        queryLog: DatabaseQueryLog = DatabaseQueryLog(),
        modeController: (any DatabaseSessionModeControlling)? = nil,
        tableDataService: (any DatabaseTableDataService)? = nil
    ) {
        self.id = id
        self.databaseName = databaseName
        self.status = status
        self.isReadOnly = isReadOnly
        self.metadataScope = metadataScope
        self.queryLog = queryLog
        let metadata = Self.wrapMetadataProvider(metadataProvider, log: queryLog)
        self.metadataProvider = metadata.provider
        if let queryExecutor {
            self.queryExecutor = Self.wrapQueryExecutor(queryExecutor, log: queryLog)
        } else {
            self.queryExecutor = metadata.queryExecutor
        }
        self.modeController = modeController ?? InMemoryDatabaseSessionModeController(
            initialMode: isReadOnly ? .readOnly : .writable
        )
        self.tableDataService = tableDataService ?? PreviewDatabaseTableDataService()
        self.treeNodes = []
    }

    var accessMode: DatabaseAccessMode { isReadOnly ? .readOnly : .writable }

    func loadIfNeeded() async {
        guard treeNodes.isEmpty, !isRefreshing else { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        loadError = nil

        do {
            let schema = try await metadataProvider.metadata(scope: metadataScope)
            treeNodes = Self.buildTree(from: schema)
            selectedNodeID = nil
            loadError = nil
        } catch {
            treeNodes = []
            selectedNodeID = nil
            loadError = error.localizedDescription
        }

        isRefreshing = false
    }

    @discardableResult
    func execute(_ request: DatabaseQueryRequest) async throws -> DatabaseQueryResult {
        guard let queryExecutor else {
            throw DatabaseConnectionError.notConnected
        }
        return try await queryExecutor.execute(request)
    }

    func setAccessMode(_ mode: DatabaseAccessMode) async {
        guard mode != accessMode else { return }
        isUpdatingMode = true
        modeError = nil
        defer { isUpdatingMode = false }

        do {
            try await modeController?.setMode(mode)
            isReadOnly = mode == .readOnly
            if status == .online || status == .readOnly {
                status = mode == .readOnly ? .readOnly : .online
            }
        } catch {
            modeError = error.localizedDescription
        }
    }

    @discardableResult
    func toggleExpansion(for nodeID: DatabaseObjectTreeNode.ID, isExpanded: Bool) -> Task<Void, Never>? {
        Task { @MainActor in
            await Task.yield()

            updateNode(nodeID) { node in
                node.isExpanded = isExpanded
            }

            guard isExpanded else { return }

            await loadChildrenIfNeeded(for: nodeID)
        }
    }

    func selectNode(_ nodeID: DatabaseObjectTreeNode.ID?) {
        selectedNodeID = nodeID
    }

    func collapseAll() {
        var nodes = treeNodes
        Self.collapse(nodes: &nodes)
        treeNodes = nodes
        selectedNodeID = nil
    }

    func expandAll() {
        guard !isExpandingAll else { return }

        isExpandingAll = true
        let currentNodes = treeNodes

        let expansionTask = Task.detached(priority: .userInitiated) { () async -> [DatabaseObjectTreeNode] in
            await MainActor.run { () -> [DatabaseObjectTreeNode] in
                var nodes = currentNodes
                Self.expand(nodes: &nodes)
                return nodes
            }
        }

        Task {
            defer { isExpandingAll = false }
            let expandedNodes = await expansionTask.value
            treeNodes = expandedNodes
        }
    }

    var selectedNode: DatabaseObjectTreeNode? {
        guard let selectedNodeID else { return nil }
        return findNode(with: selectedNodeID, in: treeNodes)
    }

    func makeTableContentViewModel(pageSize: Int = 50) -> DatabaseTableContentViewModel {
        DatabaseTableContentViewModel(tableDataService: tableDataService, pageSize: pageSize)
    }
}

// MARK: - Query logging

private extension DatabaseBrowserSessionViewModel {
    static func wrapMetadataProvider(
        _ provider: any DatabaseMetadataProvider,
        log: DatabaseQueryLog
    ) -> (provider: any DatabaseMetadataProvider, queryExecutor: (any DatabaseQueryExecutor)?) {
        if let connection = provider as? any DatabaseConnection {
            let loggedConnection = wrapConnection(connection, log: log)
            return (loggedConnection, loggedConnection)
        }

        if let executor = provider as? any DatabaseQueryExecutor {
            let loggedExecutor = wrapQueryExecutor(executor, log: log)
            return (provider, loggedExecutor)
        }

        return (provider, nil)
    }

    static func wrapConnection(
        _ connection: any DatabaseConnection,
        log: DatabaseQueryLog
    ) -> any DatabaseConnection {
        if connection is any DatabaseQueryLogging {
            return connection
        }
        return LoggingDatabaseConnection(base: connection, log: log)
    }

    static func wrapQueryExecutor(
        _ executor: any DatabaseQueryExecutor,
        log: DatabaseQueryLog
    ) -> any DatabaseQueryExecutor {
        if executor is any DatabaseQueryLogging {
            return executor
        }
        return LoggingDatabaseQueryExecutor(base: executor, log: log)
    }
}

// MARK: - Tree construction

private extension DatabaseBrowserSessionViewModel {
    static func buildTree(from schema: DatabaseSchema) -> [DatabaseObjectTreeNode] {
        schema.catalogs.sorted { $0.name < $1.name }.map { catalog in
            DatabaseObjectTreeNode(
                title: catalog.name,
                kind: .catalog(name: catalog.name),
                pendingChildren: .namespaces(catalog: catalog.name, namespaces: catalog.namespaces)
            )
        }
    }

    func loadChildrenIfNeeded(for nodeID: DatabaseObjectTreeNode.ID) async {
        guard let pending = pendingChildren(for: nodeID) else { return }

        updateNode(nodeID) { node in
            node.isLoading = true
        }

        await Task.yield()

        let children = Self.buildChildren(from: pending)

        updateNode(nodeID) { node in
            node.children = children
            node.pendingChildren = nil
            node.isLoading = false
        }
    }

    static func buildChildren(from pending: DatabaseObjectTreeNode.PendingChildren) -> [DatabaseObjectTreeNode] {
        switch pending {
        case .namespaces(let catalog, let namespaces):
            return namespaces.sorted { $0.name < $1.name }.map { namespace in
                DatabaseObjectTreeNode(
                    title: namespace.name,
                    kind: .namespace(catalog: catalog, name: namespace.name),
                    pendingChildren: .namespaceObjects(catalog: catalog, namespace: namespace)
                )
            }
        case .namespaceObjects(let catalog, let namespace):
            let tableNodes = namespace.tables.sorted { $0.name < $1.name }.map { table in
                DatabaseObjectTreeNode(
                    title: table.name,
                    kind: .table(catalog: catalog, namespace: namespace.name, name: table.name),
                    table: table
                )
            }
            let viewNodes = namespace.views.sorted { $0.name < $1.name }.map { view in
                DatabaseObjectTreeNode(
                    title: view.name,
                    kind: .view(catalog: catalog, namespace: namespace.name, name: view.name)
                )
            }
            let procedureNodes = namespace.procedures.sorted { $0.name < $1.name }.map { procedure in
                DatabaseObjectTreeNode(
                    title: procedure.name,
                    kind: .storedProcedure(catalog: catalog, namespace: namespace.name, name: procedure.name)
                )
            }
            return tableNodes + viewNodes + procedureNodes
        }
    }
}

// MARK: - Tree traversal

private extension DatabaseBrowserSessionViewModel {
    func pendingChildren(for nodeID: DatabaseObjectTreeNode.ID) -> DatabaseObjectTreeNode.PendingChildren? {
        findNode(with: nodeID, in: treeNodes)?.pendingChildren
    }

    func findNode(with id: DatabaseObjectTreeNode.ID, in nodes: [DatabaseObjectTreeNode]) -> DatabaseObjectTreeNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = findNode(with: id, in: node.children) {
                return found
            }
        }
        return nil
    }

    func updateNode(_ id: DatabaseObjectTreeNode.ID, mutation: (inout DatabaseObjectTreeNode) -> Void) {
        var nodes = treeNodes
        _ = updateNode(id, in: &nodes, mutation: mutation)
        treeNodes = nodes
    }

    func updateNode(
        _ id: DatabaseObjectTreeNode.ID,
        in nodes: inout [DatabaseObjectTreeNode],
        mutation: (inout DatabaseObjectTreeNode) -> Void
    ) -> Bool {
        for index in nodes.indices {
            if nodes[index].id == id {
                mutation(&nodes[index])
                return true
            }
            if updateNode(id, in: &nodes[index].children, mutation: mutation) {
                return true
            }
        }
        return false
    }

    static func collapse(nodes: inout [DatabaseObjectTreeNode]) {
        for index in nodes.indices {
            nodes[index].isExpanded = false
            collapse(nodes: &nodes[index].children)
        }
    }

    // TODO: Follow-up: move recursive expansion off the main actor to avoid blocking large schemas.
    static func expand(nodes: inout [DatabaseObjectTreeNode]) {
        for index in nodes.indices {
            if let pending = nodes[index].pendingChildren {
                nodes[index].children = Self.buildChildren(from: pending)
                nodes[index].pendingChildren = nil
            }
            nodes[index].isExpanded = true
            expand(nodes: &nodes[index].children)
        }
    }
}

extension DatabaseBrowserSessionViewModel {
    static func previewSessions(
        metadataProviderFactory: @escaping () -> any DatabaseMetadataProvider = {
            PreviewDatabaseMetadataProvider(schema: .previewBrowserSchema)
        }
    ) -> [DatabaseBrowserSessionViewModel] {
        [
            DatabaseBrowserSessionViewModel(
                databaseName: "analytics",
                status: .readOnly,
                isReadOnly: true,
                metadataProvider: metadataProviderFactory()
            ),
            DatabaseBrowserSessionViewModel(
                databaseName: "production",
                status: .readOnly,
                isReadOnly: true,
                metadataProvider: metadataProviderFactory()
            ),
        ]
    }
}
