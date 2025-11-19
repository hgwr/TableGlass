import Foundation
import SwiftUI

struct DatabaseBrowserSessionViewState: Identifiable, Hashable {
    let id: UUID
    var databaseName: String
    var status: DatabaseBrowserSessionStatus
    var isReadOnly: Bool
    var sidebarSections: [DatabaseBrowserSidebarSection]

    init(
        id: UUID = UUID(),
        databaseName: String,
        status: DatabaseBrowserSessionStatus,
        isReadOnly: Bool,
        sidebarSections: [DatabaseBrowserSidebarSection] = DatabaseBrowserSidebarSection.defaults
    ) {
        self.id = id
        self.databaseName = databaseName
        self.status = status
        self.isReadOnly = isReadOnly
        self.sidebarSections = sidebarSections
    }
}

enum DatabaseBrowserSessionStatus: String, Hashable, CaseIterable {
    case connecting
    case online
    case readOnly
    case error

    var description: String {
        switch self {
        case .connecting:
            "Connecting"
        case .online:
            "Online"
        case .readOnly:
            "Read Only"
        case .error:
            "Error"
        }
    }

    var indicatorColor: Color {
        switch self {
        case .connecting:
            .yellow
        case .online:
            .green
        case .readOnly:
            .blue
        case .error:
            .red
        }
    }
}

struct DatabaseBrowserSidebarSection: Identifiable, Hashable {
    let id: UUID
    var title: String
    var items: [DatabaseBrowserSidebarItem]

    init(id: UUID = UUID(), title: String, items: [DatabaseBrowserSidebarItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

struct DatabaseBrowserSidebarItem: Identifiable, Hashable {
    enum Kind: String {
        case table
        case view
        case storedProcedure
    }

    let id: UUID
    var name: String
    var kind: Kind

    init(id: UUID = UUID(), name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

extension DatabaseBrowserSidebarSection {
    static var defaults: [DatabaseBrowserSidebarSection] {
        [
            DatabaseBrowserSidebarSection(
                title: "Tables",
                items: [
                    DatabaseBrowserSidebarItem(name: "users", kind: .table),
                    DatabaseBrowserSidebarItem(name: "orders", kind: .table),
                    DatabaseBrowserSidebarItem(name: "payments", kind: .table)
                ]
            ),
            DatabaseBrowserSidebarSection(
                title: "Views",
                items: [
                    DatabaseBrowserSidebarItem(name: "active_users", kind: .view),
                    DatabaseBrowserSidebarItem(name: "order_summary", kind: .view)
                ]
            ),
            DatabaseBrowserSidebarSection(
                title: "Procedures",
                items: [
                    DatabaseBrowserSidebarItem(name: "update_stats", kind: .storedProcedure)
                ]
            )
        ]
    }
}

extension DatabaseBrowserSessionViewState {
    static var previewSessions: [DatabaseBrowserSessionViewState] {
        [
            DatabaseBrowserSessionViewState(
                databaseName: "analytics",
                status: .connecting,
                isReadOnly: true
            ),
            DatabaseBrowserSessionViewState(
                databaseName: "production",
                status: .online,
                isReadOnly: false
            )
        ]
    }

    func sidebarItem(with identifier: DatabaseBrowserSidebarItem.ID?) -> DatabaseBrowserSidebarItem? {
        guard let identifier else { return nil }
        return sidebarSections.flatMap { $0.items }.first(where: { $0.id == identifier })
    }
}
