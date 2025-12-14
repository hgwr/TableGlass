import SwiftUI
import OSLog
#if os(macOS)
import AppKit
#endif
import TableGlassKit

struct DatabaseBrowserWindow: View {
    @StateObject private var viewModel: DatabaseBrowserViewModel
    @StateObject private var quickPaletteViewModel: QuickResourcePaletteViewModel
#if os(macOS)
    @State private var hostingWindow: NSWindow?
    @State private var quickOpenKeyMonitor: Any?
#endif
    private var isBrowserUITest: Bool {
        ProcessInfo.processInfo.arguments.contains(UITestArguments.databaseBrowser.rawValue)
    }

    init(viewModel: DatabaseBrowserViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _quickPaletteViewModel = StateObject(wrappedValue: QuickResourcePaletteViewModel(browserViewModel: viewModel))
    }

    var body: some View {
        ZStack {
#if os(macOS)
            if viewModel.sessions.isEmpty {
                DatabaseBrowserPlaceholderView()
            } else {
                DatabaseBrowserTabView(
                    viewModel: viewModel,
                    onShowQuickOpenPalette: {
                        Task { @MainActor in
                            quickPaletteViewModel.present()
                        }
                    }
                )
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
                            },
                            onShowQuickOpenPalette: {
                                Task { @MainActor in
                                    quickPaletteViewModel.present()
                                }
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
            quickPaletteOverlay
        }
        .animation(.easeInOut(duration: 0.12), value: quickPaletteViewModel.isPresented)
#if os(macOS)
        .background(WindowAccessor { window in
            hostingWindow = window
            installQuickOpenMonitor(for: window)
        })
        .onReceive(NotificationCenter.default.publisher(for: .databaseBrowserQuickOpenRequested)) { notification in
            guard let hostingWindow,
                  let senderWindow = notification.object as? NSWindow,
                  hostingWindow == senderWindow else { return }
            Task { @MainActor in
                quickPaletteViewModel.present()
            }
        }
        .onDisappear {
            removeQuickOpenMonitor()
        }
#endif
        .task {
            await viewModel.bootstrap()
        }
        .onChange(of: viewModel.sessions.count) { _, _ in
            if quickPaletteViewModel.isPresented {
                Task {
                    await quickPaletteViewModel.refreshIndices()
                }
            }
        }
#if os(macOS)
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains(UITestArguments.databaseBrowser.rawValue) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
#endif
    }

    @ViewBuilder
    private var quickPaletteOverlay: some View {
        if quickPaletteViewModel.isPresented {
            ZStack {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture {
                        quickPaletteViewModel.dismiss()
                    }

                QuickResourcePaletteView(
                    viewModel: quickPaletteViewModel,
                    onSelect: { match in
                        Task {
                            await viewModel.focus(resource: match.item)
                        }
                        quickPaletteViewModel.dismiss()
                    },
                    onDismiss: {
                        quickPaletteViewModel.dismiss()
                    }
                )
                .frame(maxWidth: 780)
                .padding(.horizontal, 80)
                .padding(.vertical, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }
            .transition(.opacity)
        }
    }

}

private struct DatabaseBrowserSessionView: View {
    @ObservedObject var session: DatabaseBrowserSessionViewModel
    let onConfirmAccessMode: @Sendable (DatabaseAccessMode) async -> Void
    let onShowQuickOpenPalette: @MainActor @Sendable () -> Void

    @StateObject private var logViewModel: DatabaseSessionLogViewModel
    @StateObject private var tableContentViewModel: DatabaseTableContentViewModel
    @StateObject private var queryEditorViewModel: DatabaseQueryEditorViewModel
    @State private var isShowingLog = false
    @State private var isShowingModeConfirmation = false
    @State private var modeConfirmation = ModeChangeConfirmationState()
    @State private var requestedAccessMode: DatabaseAccessMode?
    @State private var toggleState: Bool
    @State private var detailDisplayMode: DetailDisplayMode = .results
    @State private var editorHeightRatio: CGFloat = 0.55
    private let logger = Logger(subsystem: "com.tableglass", category: "DatabaseBrowser.SessionView")
    private let defaultSelectLimit = 50

    init(
        session: DatabaseBrowserSessionViewModel,
        onConfirmAccessMode: @escaping @Sendable (DatabaseAccessMode) async -> Void,
        onShowQuickOpenPalette: @escaping @Sendable () -> Void
    ) {
        _session = ObservedObject(initialValue: session)
        self.onConfirmAccessMode = onConfirmAccessMode
        self.onShowQuickOpenPalette = onShowQuickOpenPalette
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
            connectionToolbar
            NavigationSplitView {
                sidebar
            } detail: {
                detailView
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .focusedSceneValue(\.databaseBrowserCommandActions, commandActions)
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

        queryEditorViewModel.requestExecute(isReadOnly: session.isReadOnly)
    }

    private var connectionToolbar: some View {
        ConnectionToolbar(
            databaseName: session.databaseName,
            status: session.status,
            statusDescription: session.status.description,
            toggleState: Binding(
                get: { toggleState },
                set: { newValue in
                    toggleState = newValue
                    logger.debug("User toggled Read-Only switch for \(self.session.databaseName, privacy: .public) to \(newValue ? "on" : "off") (current: \(self.session.isReadOnly ? "on" : "off"))")
                    let targetMode: DatabaseAccessMode = newValue ? .readOnly : .writable
                    logger.debug("User requested access mode change for \(self.session.databaseName, privacy: .public) to \(targetMode.logDescription)")
                    prepareModeChange(for: targetMode)
                }
            ),
            isUpdatingMode: session.isUpdatingMode,
            onShowLog: { isShowingLog = true }
        )
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                Divider()
                    .padding(.leading, -8)
                    .padding(.trailing, -8)
            }

            DatabaseObjectTreeList(session: session)
        }
        .frame(minWidth: 240)
    }

    private var detailView: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                queryEditorSection
                    .frame(height: max(180, proxy.size.height * editorHeightRatio))
                dragHandle(totalHeight: proxy.size.height)
                resultsCard
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .background(detailBackgroundColor)
        }
    }

    private var detailBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    private var queryEditorSection: some View {
        DatabaseQueryEditorView(
            viewModel: queryEditorViewModel,
            isReadOnly: session.isReadOnly,
            showsResultsInline: false,
            onExecute: { detailDisplayMode = .results }
        )
    }

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Results")
                    .font(.headline)
                Spacer()
                if selectedTableIdentifier != nil {
                    detailModePicker
                }
            }

            detailSummary
            resultsContent
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var detailSummary: some View {
        Group {
            if let node = session.selectedNode {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: node.title)
                        .font(.title3)
                        .bold()
                        .accessibilityIdentifier(DatabaseBrowserAccessibility.detailTitle.rawValue)
                        .accessibilityLabel(node.title)
                        .accessibilityValue(node.title)
                    Label(node.kindDisplayName, systemImage: node.kind.systemImageName)
                        .foregroundStyle(.secondary)
                    Text(pathDescription(for: node))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Select an object to view details")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        switch effectiveDetailMode {
        case .results:
            DatabaseQueryResultSection(
                viewModel: queryEditorViewModel,
                isReadOnly: session.isReadOnly,
                onExecute: { detailDisplayMode = .results },
                placeholderText: "Run a query to see results here."
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

    @ViewBuilder
    private func dragHandle(totalHeight: CGFloat) -> some View {
        let minimumHeight: CGFloat = 150
        let maximumHeight: CGFloat = max(minimumHeight, totalHeight - minimumHeight)

        Rectangle()
            .foregroundStyle(.clear)
            .frame(height: 10)
            .overlay {
                Capsule()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 80, height: 4)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let proposed = (totalHeight * editorHeightRatio) + value.translation.height
                        let clamped = min(max(proposed, minimumHeight), maximumHeight)
                        editorHeightRatio = clamped / totalHeight
                    }
            )
            .padding(.vertical, 8)
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

    @MainActor
    private var commandActions: DatabaseBrowserCommandActions {
        DatabaseBrowserCommandActions(
            runQuery: {
                detailDisplayMode = .results
                queryEditorViewModel.requestExecute(isReadOnly: session.isReadOnly)
            },
            showHistory: {
                detailDisplayMode = .results
                queryEditorViewModel.beginHistorySearch()
            },
            showQuickOpen: {
                onShowQuickOpenPalette()
            }
        )
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

private struct ConnectionToolbar: View {
    let databaseName: String
    let status: DatabaseBrowserSessionStatus
    let statusDescription: String
    let toggleState: Binding<Bool>
    let isUpdatingMode: Bool
    let onShowLog: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(status.indicatorColor)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(databaseName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text(statusDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Show Log", action: onShowLog)
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .accessibilityIdentifier(DatabaseBrowserAccessibility.showLogButton.rawValue)

            Toggle("Read-Only", isOn: toggleState)
                .toggleStyle(.switch)
                .accessibilityIdentifier(DatabaseBrowserAccessibility.readOnlyToggle.rawValue)
                .disabled(isUpdatingMode)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
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
private extension DatabaseBrowserWindow {
    func installQuickOpenMonitor(for window: NSWindow?) {
        removeQuickOpenMonitor()
        guard let window else { return }

        quickOpenKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window == window else { return event }
            let isCommandP = event.modifierFlags.contains(.command)
                && event.charactersIgnoringModifiers?.lowercased() == "p"
            if isCommandP {
                Task { @MainActor in
                    quickPaletteViewModel.present()
                }
                return nil
            }
            return event
        }
    }

    func removeQuickOpenMonitor() {
        if let quickOpenKeyMonitor {
            NSEvent.removeMonitor(quickOpenKeyMonitor)
        }
        quickOpenKeyMonitor = nil
    }
}

private struct DatabaseBrowserTabView: NSViewRepresentable {
    @ObservedObject var viewModel: DatabaseBrowserViewModel
    let onShowQuickOpenPalette: @MainActor @Sendable () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            viewModel: viewModel,
            onShowQuickOpenPalette: onShowQuickOpenPalette
        )
    }

    func makeNSView(context: Context) -> NSTabView {
        let tabView = NSTabView()
        tabView.delegate = context.coordinator
        tabView.identifier = NSUserInterfaceItemIdentifier(DatabaseBrowserAccessibility.tabGroup.rawValue)
        tabView.setAccessibilityIdentifier(DatabaseBrowserAccessibility.tabGroup.rawValue)
        tabView.setAccessibilityRole(.tabGroup)
        context.coordinator.configureTabView(tabView, forSessionCount: viewModel.sessions.count)
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
        private let onShowQuickOpenPalette: @MainActor @Sendable () -> Void
        weak var tabView: NSTabView?
        private var items: [DatabaseBrowserSessionViewModel.ID: NSTabViewItem] = [:]

        init(
            viewModel: DatabaseBrowserViewModel,
            onShowQuickOpenPalette: @escaping @Sendable () -> Void
        ) {
            self.viewModel = viewModel
            self.onShowQuickOpenPalette = onShowQuickOpenPalette
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
            configureTabView(tabView, forSessionCount: sessions.count)

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

        func configureTabView(_ tabView: NSTabView, forSessionCount count: Int) {
            if count > 1 {
                tabView.tabViewType = .topTabsBezelBorder
                tabView.tabPosition = .top
            } else {
                tabView.tabViewType = .noTabsNoBorder
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
                },
                onShowQuickOpenPalette: onShowQuickOpenPalette
            )
        }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            onResolve(view?.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            onResolve(nsView?.window)
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
    case rowDetailToggle = "databaseBrowser.rowDetail.toggle"
    case rowDetailPanel = "databaseBrowser.rowDetail.panel"
    case rowDetailCopyButton = "databaseBrowser.rowDetail.copy"
    case rowDetailCopyField = "databaseBrowser.rowDetail.copyField"
    case rowDetailClose = "databaseBrowser.rowDetail.close"

    static func sidebarRow(for name: String) -> String {
        "databaseBrowser.sidebar.\(name)"
    }
}

#Preview("Database Browser Window") {
    DatabaseBrowserWindow(viewModel: DatabaseBrowserViewModel())
}
