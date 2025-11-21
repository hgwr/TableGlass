import Foundation
import SwiftUI
import TableGlassKit

enum DatabaseBrowserSessionStatus: String, Hashable, CaseIterable {
    case connecting
    case online
    case readOnly
    case error

    var description: String {
        switch self {
        case .connecting:
            return "Connecting"
        case .online:
            return "Online"
        case .readOnly:
            return "Read Only"
        case .error:
            return "Error"
        }
    }

    var indicatorColor: Color {
        switch self {
        case .connecting:
            return .yellow
        case .online:
            return .green
        case .readOnly:
            return .blue
        case .error:
            return .red
        }
    }
}

struct DatabaseObjectTreeNode: Identifiable, Hashable, Sendable {
    enum Kind: Hashable {
        case catalog(name: String)
        case namespace(catalog: String, name: String)
        case table(catalog: String, namespace: String, name: String)
        case view(catalog: String, namespace: String, name: String)
        case storedProcedure(catalog: String, namespace: String, name: String)
    }

    enum PendingChildren: Sendable {
        case namespaces(catalog: String, namespaces: [DatabaseNamespace])
        case namespaceObjects(catalog: String, namespace: DatabaseNamespace)
    }

    let id: UUID
    var title: String
    var kind: Kind
    var children: [DatabaseObjectTreeNode]
    var isExpanded: Bool
    var isLoading: Bool
    var pendingChildren: PendingChildren?

    init(
        id: UUID = UUID(),
        title: String,
        kind: Kind,
        children: [DatabaseObjectTreeNode] = [],
        isExpanded: Bool = false,
        isLoading: Bool = false,
        pendingChildren: PendingChildren? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.children = children
        self.isExpanded = isExpanded
        self.isLoading = isLoading
        self.pendingChildren = pendingChildren
    }

    static func == (lhs: DatabaseObjectTreeNode, rhs: DatabaseObjectTreeNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension DatabaseObjectTreeNode {
    var isLeaf: Bool {
        children.isEmpty && pendingChildren == nil
    }

    var isExpandable: Bool {
        pendingChildren != nil || !children.isEmpty
    }

    var accessibilityIdentifier: String {
        switch kind {
        case .catalog(let name):
            return "databaseBrowser.sidebar.catalog.\(name)"
        case .namespace(let catalog, let name):
            return "databaseBrowser.sidebar.namespace.\(catalog).\(name)"
        case .table(let catalog, let namespace, let name):
            return "databaseBrowser.sidebar.table.\(catalog).\(namespace).\(name)"
        case .view(let catalog, let namespace, let name):
            return "databaseBrowser.sidebar.view.\(catalog).\(namespace).\(name)"
        case .storedProcedure(let catalog, let namespace, let name):
            return "databaseBrowser.sidebar.procedure.\(catalog).\(namespace).\(name)"
        }
    }

    var kindDisplayName: String {
        switch kind {
        case .catalog:
            return "Catalog"
        case .namespace:
            return "Schema"
        case .table:
            return "Table"
        case .view:
            return "View"
        case .storedProcedure:
            return "Stored Procedure"
        }
    }
}

extension DatabaseObjectTreeNode.Kind {
    var systemImageName: String {
        switch self {
        case .catalog:
            return "shippingbox"
        case .namespace:
            return "folder.fill"
        case .table:
            return "tablecells"
        case .view:
            return "eye"
        case .storedProcedure:
            return "gear"
        }
    }
}
