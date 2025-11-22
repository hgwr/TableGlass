import SwiftUI
#if os(macOS)
import AppKit
#endif

struct DatabaseBrowserWindow: View {
    @StateObject private var viewModel: DatabaseBrowserViewModel

    init(viewModel: DatabaseBrowserViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
#if os(macOS)
        DatabaseBrowserTabView(viewModel: viewModel)
#else
        TabView(selection: $viewModel.selectedSessionID) {
            ForEach(viewModel.sessions) { session in
                DatabaseBrowserSessionView(
                    session: session,
                    onShowLog: { /* Placeholder for log presentation */ },
                    onToggleReadOnly: { value in
                        viewModel.setReadOnly(value, for: session.id)
                    }
                )
                .tag(session.id as DatabaseBrowserSessionViewModel.ID?)
                .tabItem {
                    Label(session.databaseName, systemImage: "server.rack")
                }
            }
        }
        .tabViewStyle(.automatic)
        .accessibilityIdentifier(DatabaseBrowserAccessibility.tabGroup.rawValue)
#endif
    }
}

private struct DatabaseBrowserSessionView: View {
    @ObservedObject var session: DatabaseBrowserSessionViewModel
    let onShowLog: () -> Void
    let onToggleReadOnly: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            NavigationSplitView {
                sidebar
            } detail: {
                detailView
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .task {
            await session.loadIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Circle()
                    .fill(session.status.indicatorColor)
                    .frame(width: 10, height: 10)
                Text(session.databaseName)
                    .font(.headline)
                    .bold()
                Text(session.status.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Show Log") {
                onShowLog()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(DatabaseBrowserAccessibility.showLogButton.rawValue)

            Toggle("Read-Only", isOn: Binding(
                get: { session.isReadOnly },
                set: { newValue in
                    onToggleReadOnly(newValue)
                }
            ))
            .toggleStyle(.switch)
            .accessibilityIdentifier(DatabaseBrowserAccessibility.readOnlyToggle.rawValue)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.thickMaterial)
    }

    private var sidebar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Objects")
                    .font(.subheadline)
                    .bold()
                if session.isExpandingAll {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityIdentifier(DatabaseBrowserAccessibility.expandAllProgress.rawValue)
                }
                Spacer()
                Button {
                    Task {
                        await session.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh schema metadata")
                .accessibilityIdentifier(DatabaseBrowserAccessibility.refreshButton.rawValue)

                Button {
                    session.expandAll()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .help("Expand all nodes")
                .accessibilityIdentifier(DatabaseBrowserAccessibility.expandAllButton.rawValue)
                .disabled(session.isExpandingAll)

                Button {
                    session.collapseAll()
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                }
                .buttonStyle(.borderless)
                .help("Collapse all nodes")
                .accessibilityIdentifier(DatabaseBrowserAccessibility.collapseAllButton.rawValue)
                .disabled(session.isExpandingAll)
            }
            .padding(.horizontal, 8)

            DatabaseObjectTreeList(session: session)
        }
        .frame(minWidth: 240)
    }

    private var detailView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let node = session.selectedNode {
                Text(verbatim: node.title)
                    .font(.title2)
                    .bold()
                    .accessibilityIdentifier(DatabaseBrowserAccessibility.detailTitle.rawValue)
                    // Explicit label/value helps UI tests read the selected object's title.
                    .accessibilityLabel(node.title)
                    .accessibilityValue(node.title)
                Label(node.kindDisplayName, systemImage: node.kind.systemImageName)
                    .foregroundStyle(.secondary)
                Text(pathDescription(for: node))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Select an object to view details")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .background(.background)
    }

    private func pathDescription(for node: DatabaseObjectTreeNode) -> String {
        switch node.kind {
        case .catalog(let name):
            return "Catalog \(name)"
        case .namespace(let catalog, let name):
            return "\(catalog).\(name)"
        case .table(let catalog, let namespace, let name):
            return "\(catalog).\(namespace).\(name)"
        case .view(let catalog, let namespace, let name):
            return "\(catalog).\(namespace).\(name)"
        case .storedProcedure(let catalog, let namespace, let name):
            return "\(catalog).\(namespace).\(name)"
        }
    }
}

private struct DatabaseObjectTreeList: View {
    @ObservedObject var session: DatabaseBrowserSessionViewModel

    var body: some View {
        List(selection: Binding(
            get: { session.selectedNodeID },
            set: { session.selectNode($0) }
        )) {
            ForEach(session.treeNodes) { node in
                DatabaseObjectTreeRow(
                    node: node,
                    selection: Binding(
                        get: { session.selectedNodeID },
                        set: { session.selectNode($0) }
                    ),
                    onToggle: { id, isExpanded in
                        session.toggleExpansion(for: id, isExpanded: isExpanded)
                    }
                )
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier(DatabaseBrowserAccessibility.sidebarList.rawValue)
        .overlay {
            if session.isRefreshing && session.treeNodes.isEmpty {
                ProgressView("Loading objects…")
                    .controlSize(.small)
                    .padding()
            } else if let message = session.loadError {
                VStack(spacing: 8) {
                    Text("Unable to load schema")
                        .font(.subheadline)
                        .bold()
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task {
                            await session.refresh()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding()
            } else if session.treeNodes.isEmpty {
                VStack(spacing: 6) {
                    Text("No objects")
                        .font(.subheadline)
                        .bold()
                    Text("Connect to a database to view tables, views, and procedures.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding()
            }
        }
    }
}

private struct DatabaseObjectTreeRow: View {
    let node: DatabaseObjectTreeNode
    @Binding var selection: DatabaseObjectTreeNode.ID?
    let onToggle: (DatabaseObjectTreeNode.ID, Bool) -> Void

    var body: some View {
        if node.isExpandable {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { node.isExpanded },
                    set: { expanded in onToggle(node.id, expanded) }
                )
            ) {
                if node.isLoading && node.children.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Loading…")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .padding(.leading, 2)
                }
                ForEach(node.children) { child in
                    DatabaseObjectTreeRow(
                        node: child,
                        selection: $selection,
                        onToggle: onToggle
                    )
                    .padding(.leading, 12)
                }
            } label: {
                rowLabel
            }
        } else {
            rowLabel
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: node.kind.systemImageName)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: node.title)
                    .accessibilityIdentifier(node.accessibilityIdentifier)
                Text(node.kindDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(selection == node.id ? Color.accentColor.opacity(0.12) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            selection = node.id
            guard node.isExpandable else { return }
            onToggle(node.id, !node.isExpanded)
        }
        .tag(node.id as DatabaseObjectTreeNode.ID?)
    }
}

#if os(macOS)
private struct DatabaseBrowserTabView: NSViewRepresentable {
    @ObservedObject var viewModel: DatabaseBrowserViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> NSTabView {
        let tabView = NSTabView()
        tabView.delegate = context.coordinator
        tabView.identifier = NSUserInterfaceItemIdentifier(DatabaseBrowserAccessibility.tabGroup.rawValue)
        tabView.setAccessibilityIdentifier(DatabaseBrowserAccessibility.tabGroup.rawValue)
        tabView.setAccessibilityRole(.tabGroup)
        tabView.tabViewType = .topTabsBezelBorder
        tabView.tabPosition = .top
        context.coordinator.tabView = tabView
        context.coordinator.updateTabs(
            sessions: viewModel.sessions,
            selectedID: viewModel.selectedSessionID
        )
        return tabView
    }

    func updateNSView(_ nsView: NSTabView, context: Context) {
        context.coordinator.updateTabs(
            sessions: viewModel.sessions,
            selectedID: viewModel.selectedSessionID
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTabViewDelegate {
        private let viewModel: DatabaseBrowserViewModel
        weak var tabView: NSTabView?
        private var items: [DatabaseBrowserSessionViewModel.ID: NSTabViewItem] = [:]

        init(viewModel: DatabaseBrowserViewModel) {
            self.viewModel = viewModel
        }

        func updateTabs(
            sessions: [DatabaseBrowserSessionViewModel],
            selectedID: DatabaseBrowserSessionViewModel.ID?
        ) {
            guard let tabView else { return }

            let sessionIDs = Set(sessions.map { $0.id })
            for (id, item) in items where !sessionIDs.contains(id) {
                tabView.removeTabViewItem(item)
                items.removeValue(forKey: id)
            }

            for session in sessions {
                if let item = items[session.id] {
                    if let hosting = item.view as? NSHostingView<DatabaseBrowserSessionView> {
                        hosting.rootView = makeSessionView(for: session)
                    } else {
                        item.view = makeHostingView(for: session)
                    }
                    if item.label != session.databaseName {
                        item.label = session.databaseName
                    }
                } else {
                    let item = NSTabViewItem(identifier: session.id)
                    item.label = session.databaseName
                    item.view = makeHostingView(for: session)
                    items[session.id] = item
                    tabView.addTabViewItem(item)
                }
            }

            for (index, session) in sessions.enumerated() {
                guard let item = items[session.id] else { continue }
                let currentIndex = tabView.indexOfTabViewItem(item)
                if currentIndex != index {
                    tabView.removeTabViewItem(item)
                    tabView.insertTabViewItem(item, at: index)
                }
            }

            tabView.identifier = NSUserInterfaceItemIdentifier(DatabaseBrowserAccessibility.tabGroup.rawValue)
            tabView.setAccessibilityIdentifier(DatabaseBrowserAccessibility.tabGroup.rawValue)
            tabView.setAccessibilityRole(.tabGroup)
            tabView.tabViewType = .topTabsBezelBorder
            tabView.tabPosition = .top

            if let selectedID,
               let item = items[selectedID] {
                if tabView.selectedTabViewItem != item {
                    tabView.selectTabViewItem(item)
                }
            } else if let firstSession = sessions.first,
                      let item = items[firstSession.id] {
                tabView.selectTabViewItem(item)
                if viewModel.selectedSessionID != firstSession.id {
                    viewModel.selectedSessionID = firstSession.id
                }
            }
        }

        func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
            guard let id = tabViewItem?.identifier as? DatabaseBrowserSessionViewModel.ID else { return }
            if viewModel.selectedSessionID != id {
                viewModel.selectedSessionID = id
            }
        }

        private func makeHostingView(for session: DatabaseBrowserSessionViewModel) -> NSHostingView<DatabaseBrowserSessionView> {
            NSHostingView(rootView: makeSessionView(for: session))
        }

        private func makeSessionView(for session: DatabaseBrowserSessionViewModel) -> DatabaseBrowserSessionView {
            DatabaseBrowserSessionView(
                session: session,
                onShowLog: { /* Placeholder for log presentation */ },
                onToggleReadOnly: { value in
                    self.viewModel.setReadOnly(value, for: session.id)
                }
            )
        }
    }
}
#endif

private enum DatabaseBrowserAccessibility: String {
    case tabGroup = "databaseBrowser.tabGroup"
    case showLogButton = "databaseBrowser.showLogButton"
    case readOnlyToggle = "databaseBrowser.readOnlyToggle"
    case detailTitle = "databaseBrowser.detailTitle"
    case refreshButton = "databaseBrowser.refreshButton"
    case expandAllButton = "databaseBrowser.expandAll"
    case expandAllProgress = "databaseBrowser.expandAllProgress"
    case collapseAllButton = "databaseBrowser.collapseAll"
    case sidebarList = "databaseBrowser.sidebarList"

    static func sidebarRow(for name: String) -> String {
        "databaseBrowser.sidebar.\(name)"
    }
}

#Preview("Database Browser Window") {
    DatabaseBrowserWindow(viewModel: DatabaseBrowserViewModel())
}
