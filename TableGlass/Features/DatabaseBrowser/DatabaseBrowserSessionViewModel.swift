import Combine
import Foundation
import TableGlassKit

@MainActor
final class DatabaseBrowserSessionViewModel: ObservableObject, Identifiable {
    let id: UUID
    let databaseName: String
    @Published var status: DatabaseBrowserSessionStatus
    @Published var isReadOnly: Bool
    @Published private(set) var treeNodes: [DatabaseObjectTreeNode]
    @Published var selectedNodeID: DatabaseObjectTreeNode.ID?
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var isExpandingAll: Bool = false
    @Published private(set) var loadError: String?

    private let metadataProvider: any DatabaseMetadataProvider
    private let metadataScope: DatabaseMetadataScope

    init(
        id: UUID = UUID(),
        databaseName: String,
        status: DatabaseBrowserSessionStatus,
        isReadOnly: Bool,
        metadataProvider: some DatabaseMetadataProvider,
        metadataScope: DatabaseMetadataScope = DatabaseMetadataScope()
    ) {
        self.id = id
        self.databaseName = databaseName
        self.status = status
        self.isReadOnly = isReadOnly
        self.metadataProvider = metadataProvider
        self.metadataScope = metadataScope
        self.treeNodes = []
    }

    func loadIfNeeded() async {
        guard treeNodes.isEmpty, !isRefreshing else { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        loadError = nil

        let provider = metadataProvider
        let scope = metadataScope
        let buildTree = Self.buildTree(from:)

        let result = await Task.detached(priority: .userInitiated) { () async -> Result<[DatabaseObjectTreeNode], Error> in
            do {
                let schema = try await provider.metadata(scope: scope)
                let nodes = buildTree(schema)
                return .success(nodes)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let nodes):
            treeNodes = nodes
            selectedNodeID = nil
            loadError = nil
        case .failure(let error):
            treeNodes = []
            selectedNodeID = nil
            loadError = error.localizedDescription
        }

        isRefreshing = false
    }

    func toggleExpansion(for nodeID: DatabaseObjectTreeNode.ID, isExpanded: Bool) {
        updateNode(nodeID) { node in
            node.isExpanded = isExpanded
        }

        guard isExpanded else { return }

        Task {
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

        let expansionTask = Task.detached(priority: .userInitiated) { () -> [DatabaseObjectTreeNode] in
            var nodes = currentNodes
            Self.expand(nodes: &nodes)
            return nodes
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
}

// MARK: - Tree construction

private extension DatabaseBrowserSessionViewModel {
    nonisolated static func buildTree(from schema: DatabaseSchema) -> [DatabaseObjectTreeNode] {
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

    nonisolated static func buildChildren(from pending: DatabaseObjectTreeNode.PendingChildren) -> [DatabaseObjectTreeNode] {
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
                    kind: .table(catalog: catalog, namespace: namespace.name, name: table.name)
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

    nonisolated static func collapse(nodes: inout [DatabaseObjectTreeNode]) {
        for index in nodes.indices {
            nodes[index].isExpanded = false
            collapse(nodes: &nodes[index].children)
        }
    }

    nonisolated static func expand(nodes: inout [DatabaseObjectTreeNode]) {
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
                status: .connecting,
                isReadOnly: true,
                metadataProvider: metadataProviderFactory()
            ),
            DatabaseBrowserSessionViewModel(
                databaseName: "production",
                status: .online,
                isReadOnly: false,
                metadataProvider: metadataProviderFactory()
            ),
        ]
    }
}
