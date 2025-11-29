import SwiftUI
import OSLog
#if os(macOS)
import AppKit
#endif
import TableGlassKit

struct DatabaseBrowserWindow: View {
    @StateObject private var viewModel: DatabaseBrowserViewModel
    private var isBrowserUITest: Bool {
        ProcessInfo.processInfo.arguments.contains(UITestArguments.databaseBrowser.rawValue)
    }

    init(viewModel: DatabaseBrowserViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
#if os(macOS)
            if viewModel.sessions.isEmpty {
                DatabaseBrowserPlaceholderView()
            } else {
                DatabaseBrowserTabView(viewModel: viewModel)
            }
#else
            if viewModel.sessions.isEmpty {
                DatabaseBrowserPlaceholderView()
            } else {
                TabView(selection: $viewModel.selectedSessionID) {
                    ForEach(viewModel.sessions) { session in
                        DatabaseBrowserSessionView(
                            session: session,
                            onConfirmAccessMode: { mode in
                                await viewModel.setAccessMode(mode, for: session.id)
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
        }
#endif
        }
        .task {
            await viewModel.bootstrap()
        }
#if os(macOS)
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains(UITestArguments.databaseBrowser.rawValue) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
#endif
    }

}

private struct DatabaseBrowserSessionView: View {
    @ObservedObject var session: DatabaseBrowserSessionViewModel
    let onConfirmAccessMode: @Sendable (DatabaseAccessMode) async -> Void

    @StateObject private var logViewModel: DatabaseSessionLogViewModel
    @StateObject private var tableContentViewModel: DatabaseTableContentViewModel
    @StateObject private var queryEditorViewModel: DatabaseQueryEditorViewModel
    @State private var isShowingLog = false
    @State private var isShowingModeConfirmation = false
    @State private var modeConfirmation = ModeChangeConfirmationState()
    @State private var requestedAccessMode: DatabaseAccessMode?
    @State private var toggleState: Bool
    @State private var detailDisplayMode: DetailDisplayMode = .results
    private let logger = Logger(subsystem: "com.tableglass", category: "DatabaseBrowser.SessionView")
    private let defaultSelectLimit = 50

    init(
        session: DatabaseBrowserSessionViewModel,
        onConfirmAccessMode: @escaping @Sendable (DatabaseAccessMode) async -> Void
    ) {
        _session = ObservedObject(initialValue: session)
        self.onConfirmAccessMode = onConfirmAccessMode
        _logViewModel = StateObject(wrappedValue: DatabaseSessionLogViewModel(
            databaseName: session.databaseName,
            log: session.queryLog
        ))
        _tableContentViewModel = StateObject(wrappedValue: session.makeTableContentViewModel())
        _queryEditorViewModel = StateObject(wrappedValue: session.makeQueryEditorViewModel())
        _toggleState = State(initialValue: session.isReadOnly)
    }

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
        .sheet(isPresented: $isShowingLog) {
            DatabaseSessionLogView(viewModel: logViewModel)
        }
        .sheet(isPresented: $isShowingModeConfirmation, onDismiss: { modeConfirmation.reset() }) {
            ModeChangeConfirmationView(
                state: $modeConfirmation,
                databaseName: session.databaseName,
                onConfirm: applyPendingModeChange,
                onCancel: cancelPendingModeChange
            )
        }
        .task {
            await session.loadIfNeeded()
        }
        .onChange(of: session.isReadOnly) { _, newValue in
            toggleState = newValue
        }
        .onChange(of: session.selectedNodeID) { _, _ in
            handleSelectionChange()
        }
    }

    private func prepareModeChange(for mode: DatabaseAccessMode) {
        requestedAccessMode = mode
        modeConfirmation.prepare(for: mode)
        isShowingModeConfirmation = true
    }

    private func cancelPendingModeChange() {
        modeConfirmation.reset()
        isShowingModeConfirmation = false
        requestedAccessMode = nil
        toggleState = session.isReadOnly
    }

    private func applyPendingModeChange() {
        guard let mode = requestedAccessMode ?? modeConfirmation.pendingMode else {
            cancelPendingModeChange()
            return
        }

        modeConfirmation.beginApplying()

        Task { @MainActor in
            logger.debug("Applying pending access mode \(mode.logDescription) for \(self.session.databaseName, privacy: .public)")
            await session.setAccessMode(mode)
            modeConfirmation.finish()
            isShowingModeConfirmation = false
            requestedAccessMode = nil
        }
    }

    private func handleSelectionChange() {
        if selectedTableIdentifier == nil && detailDisplayMode == .tableEditor {
            detailDisplayMode = .results
        }

        guard let table = selectedTableIdentifier else { return }
        let sql = table.defaultSelectSQL(limit: defaultSelectLimit)
        queryEditorViewModel.sqlText = sql
        detailDisplayMode = .results

        Task {
            await queryEditorViewModel.execute(isReadOnly: session.isReadOnly)
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
                isShowingLog = true
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(DatabaseBrowserAccessibility.showLogButton.rawValue)

            Toggle("Read-Only", isOn: Binding(
                get: { toggleState },
                set: { newValue in
                    toggleState = newValue
                    logger.debug("User toggled Read-Only switch for \(self.session.databaseName, privacy: .public) to \(newValue ? "on" : "off") (current: \(self.session.isReadOnly ? "on" : "off"))")
                    let targetMode: DatabaseAccessMode = newValue ? .readOnly : .writable
                    logger.debug("User requested access mode change for \(self.session.databaseName, privacy: .public) to \(targetMode.logDescription)")
                    prepareModeChange(for: targetMode)
                }
            ))
            .toggleStyle(.switch)
            .accessibilityIdentifier(DatabaseBrowserAccessibility.readOnlyToggle.rawValue)
            .disabled(session.isUpdatingMode)
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
            DatabaseQueryEditorView(
                viewModel: queryEditorViewModel,
                isReadOnly: session.isReadOnly,
                showsResultsInline: false,
                onExecute: { detailDisplayMode = .results }
            )
            Divider()
            detailHeader
            Divider()
            detailContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .background(.background)
    }

    private var detailHeader: some View {
        Group {
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
        }
    }

    private var detailContent: some View {
        let isTableSelected = selectedTableIdentifier != nil

        return VStack(alignment: .leading, spacing: 12) {
            if isTableSelected {
                detailModePicker
            }

            switch effectiveDetailMode {
            case .results:
                DatabaseQueryResultSection(
                    viewModel: queryEditorViewModel,
                    isReadOnly: session.isReadOnly,
                    onExecute: { detailDisplayMode = .results }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .tableEditor:
                if let table = selectedTableIdentifier {
                    DatabaseTableContentView(
                        viewModel: tableContentViewModel,
                        table: table,
                        columns: selectedTableColumns,
                        isReadOnly: session.isReadOnly
                    )
                    .accessibilityIdentifier(DatabaseBrowserAccessibility.tableDetail.rawValue)
                } else {
                    Text("Select a table to view and edit its data.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private var selectedTableIdentifier: DatabaseTableIdentifier? {
        session.selectedNode?.tableIdentifier
    }

    private var selectedTableColumns: [DatabaseColumn] {
        session.selectedNode?.table?.columns ?? []
    }

    private var effectiveDetailMode: DetailDisplayMode {
        if selectedTableIdentifier == nil && detailDisplayMode == .tableEditor {
            return .results
        }
        return detailDisplayMode
    }

    private var detailModePicker: some View {
        Picker("Detail Mode", selection: $detailDisplayMode) {
            Text("Results").tag(DetailDisplayMode.results)
            Text("Table Editor").tag(DetailDisplayMode.tableEditor)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 320)
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

private enum DetailDisplayMode: Hashable {
    case results
    case tableEditor
}

struct ModeChangeConfirmationState {
    var pendingMode: DatabaseAccessMode?
    var hasAcknowledged: Bool = false
    var isApplying: Bool = false

    var canConfirm: Bool { hasAcknowledged && pendingMode != nil && !isApplying }

    mutating func prepare(for mode: DatabaseAccessMode) {
        pendingMode = mode
        hasAcknowledged = false
        isApplying = false
    }

    mutating func beginApplying() {
        isApplying = true
    }

    mutating func finish() {
        pendingMode = nil
        hasAcknowledged = false
        isApplying = false
    }

    mutating func reset() {
        finish()
    }
}

private struct ModeChangeConfirmationView: View {
    @Binding var state: ModeChangeConfirmationState
    let databaseName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var modeDescription: String {
        guard let mode = state.pendingMode else { return "" }
        switch mode {
        case .readOnly:
            return "Read-Only"
        case .writable:
            return "Writable"
        }
    }

    private var detailMessage: String {
        guard let mode = state.pendingMode else { return "" }
        switch mode {
        case .writable:
            return "Switching to writable mode can modify data. Confirm to continue."
        case .readOnly:
            return "Read-only mode prevents accidental writes for this session."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Change Access Mode")
                .font(.title3)
                .bold()

            Text("\(databaseName) will switch to \(modeDescription) mode.")
                .accessibilityIdentifier(DatabaseBrowserAccessibility.modeChangeMessage.rawValue)
                .fixedSize(horizontal: false, vertical: true)

            Text(detailMessage)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Confirm", isOn: $state.hasAcknowledged)
                .toggleStyle(.checkbox)
                .accessibilityIdentifier(DatabaseBrowserAccessibility.modeChangeConfirmToggle.rawValue)

            HStack {
                if state.isApplying {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .accessibilityIdentifier(DatabaseBrowserAccessibility.modeChangeCancel.rawValue)

                Button("OK") {
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!state.canConfirm)
                .accessibilityIdentifier(DatabaseBrowserAccessibility.modeChangeConfirm.rawValue)
            }
        }
        .padding()
        .frame(minWidth: 420)
    }
}

#if DEBUG
// Helper for logging readable mode names in this file.
#endif
private extension DatabaseAccessMode {
    var logDescription: String {
        switch self {
        case .readOnly:
            return "read-only"
        case .writable:
            return "writable"
        }
    }
}

private struct DatabaseBrowserPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No database sessions")
                .font(.headline)
            Text("Create or select a connection in Connection Management to browse a database.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(.systemBackground))
        #endif
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
                    .allowsHitTesting(false)
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
                .allowsHitTesting(false)
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
                .allowsHitTesting(false)
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
                onConfirmAccessMode: { mode in
                    await self.viewModel.setAccessMode(mode, for: session.id)
                }
            )
        }
    }
}
#endif

enum DatabaseBrowserAccessibility: String {
    case tabGroup = "databaseBrowser.tabGroup"
    case showLogButton = "databaseBrowser.showLogButton"
    case readOnlyToggle = "databaseBrowser.readOnlyToggle"
    case detailTitle = "databaseBrowser.detailTitle"
    case refreshButton = "databaseBrowser.refreshButton"
    case expandAllButton = "databaseBrowser.expandAll"
    case expandAllProgress = "databaseBrowser.expandAllProgress"
    case collapseAllButton = "databaseBrowser.collapseAll"
    case sidebarList = "databaseBrowser.sidebarList"
    case dataGrid = "databaseBrowser.table.grid"
    case addRowButton = "databaseBrowser.table.addRow"
    case deleteRowButton = "databaseBrowser.table.deleteRow"
    case tableDetail = "databaseBrowser.table.detail"
    case modeChangeConfirmToggle = "databaseBrowser.modeChange.confirmToggle"
    case modeChangeConfirm = "databaseBrowser.modeChange.confirmButton"
    case modeChangeCancel = "databaseBrowser.modeChange.cancelButton"
    case modeChangeMessage = "databaseBrowser.modeChange.message"
    case queryEditor = "databaseBrowser.query.editor"
    case queryRunButton = "databaseBrowser.query.runButton"
    case queryResultGrid = "databaseBrowser.query.resultGrid"
    case queryErrorMessage = "databaseBrowser.query.error"

    static func sidebarRow(for name: String) -> String {
        "databaseBrowser.sidebar.\(name)"
    }
}

#Preview("Database Browser Window") {
    DatabaseBrowserWindow(viewModel: DatabaseBrowserViewModel())
}
