import SwiftUI

struct DatabaseBrowserWindow: View {
    @StateObject private var viewModel: DatabaseBrowserViewModel

    init(viewModel: DatabaseBrowserViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
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
                        Label(item.name, systemImage: iconName(for: item.kind))
                            .accessibilityIdentifier(DatabaseBrowserAccessibility.sidebarRow(for: item.name))
                    }
                }
            }
        }
        .frame(minWidth: 220)
    }

    private var detailView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item = session.sidebarItem(with: selectedSidebarItemID) {
                Text(item.name)
                    .font(.title2)
                    .bold()
                    .accessibilityIdentifier(DatabaseBrowserAccessibility.detailTitle.rawValue)
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
