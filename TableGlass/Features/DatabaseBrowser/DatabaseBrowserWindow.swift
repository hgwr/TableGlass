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
                .tag(session.id as DatabaseBrowserSessionViewState.ID?)
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
    let session: DatabaseBrowserSessionViewState
    let onShowLog: () -> Void
    let onToggleReadOnly: (Bool) -> Void

    @State private var selectedSidebarItemID: DatabaseBrowserSidebarItem.ID?

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
        List(selection: $selectedSidebarItemID) {
            ForEach(session.sidebarSections) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        Label {
                            Text(item.name)
                                .accessibilityIdentifier(DatabaseBrowserAccessibility.sidebarRow(for: item.name))
                        } icon: {
                            Image(systemName: iconName(for: item.kind))
                        }
                        .tag(item.id as DatabaseBrowserSidebarItem.ID?)
                    }
                }
            }
        }
        .frame(minWidth: 220)
    }

    private var detailView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item = session.sidebarItem(with: selectedSidebarItemID) {
                Text(verbatim: item.name)
                    .font(.title2)
                    .bold()
                    .accessibilityIdentifier(DatabaseBrowserAccessibility.detailTitle.rawValue)
                    .accessibilityLabel(item.name)
                    .accessibilityValue(item.name)
                Text("Detail view placeholder for \(item.kind.rawValue).").foregroundStyle(.secondary)
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

    private func iconName(for kind: DatabaseBrowserSidebarItem.Kind) -> String {
        switch kind {
        case .table:
            return "tablecells"
        case .view:
            return "eye"
        case .storedProcedure:
            return "gear"
        }
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
        private var items: [DatabaseBrowserSessionViewState.ID: NSTabViewItem] = [:]

        init(viewModel: DatabaseBrowserViewModel) {
            self.viewModel = viewModel
        }

        func updateTabs(sessions: [DatabaseBrowserSessionViewState], selectedID: DatabaseBrowserSessionViewState.ID?) {
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
            guard let id = tabViewItem?.identifier as? DatabaseBrowserSessionViewState.ID else { return }
            if viewModel.selectedSessionID != id {
                viewModel.selectedSessionID = id
            }
        }

        private func makeHostingView(for session: DatabaseBrowserSessionViewState) -> NSHostingView<DatabaseBrowserSessionView> {
            NSHostingView(rootView: makeSessionView(for: session))
        }

        private func makeSessionView(for session: DatabaseBrowserSessionViewState) -> DatabaseBrowserSessionView {
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

    static func sidebarRow(for name: String) -> String {
        "databaseBrowser.sidebar.\(name)"
    }
}

#Preview("Database Browser Window") {
    DatabaseBrowserWindow(viewModel: DatabaseBrowserViewModel())
}
