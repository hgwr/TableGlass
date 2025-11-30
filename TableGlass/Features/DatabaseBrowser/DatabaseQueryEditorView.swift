#if os(macOS)
import AppKit
#endif
import SwiftUI
import TableGlassKit

struct DatabaseQueryEditorView: View {
    @ObservedObject var viewModel: DatabaseQueryEditorViewModel
    let isReadOnly: Bool
    let showsResultsInline: Bool
    let onExecute: (() -> Void)?
    @FocusState private var isEditorFocused: Bool

    init(
        viewModel: DatabaseQueryEditorViewModel,
        isReadOnly: Bool,
        showsResultsInline: Bool = true,
        onExecute: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.isReadOnly = isReadOnly
        self.showsResultsInline = showsResultsInline
        self.onExecute = onExecute
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            editor
            if showsResultsInline {
                DatabaseQueryResultSection(
                    viewModel: viewModel,
                    isReadOnly: isReadOnly,
                    onExecute: onExecute
                )
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topLeading) {
            keyboardShortcuts
        }
        .onChange(of: viewModel.isHistorySearchPresented) { _, isPresented in
            if !isPresented {
                isEditorFocused = true
            }
        }
        .onAppear {
            isEditorFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("SQL", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.headline)
            Spacer()
            if viewModel.isExecuting {
                ProgressView()
                    .controlSize(.small)
            }
            executeButton
        }
    }

    private var executeButton: some View {
        Button {
            onExecute?()
            viewModel.requestExecute(isReadOnly: isReadOnly)
        } label: {
            Label("Run", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canExecute)
        .help(isReadOnly && !viewModel.allowsReadOnlyExecution() ? "Read-only mode blocks this statement" : "Execute SQL")
        .accessibilityIdentifier(DatabaseBrowserAccessibility.queryRunButton.rawValue)
    }

    private var keyboardShortcuts: some View {
        Group {
            Button {
                viewModel.loadPreviousHistoryEntry()
                isEditorFocused = true
            } label: {
                EmptyView()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])

            Button {
                viewModel.loadNextHistoryEntry()
                isEditorFocused = true
            } label: {
                EmptyView()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])

            Button {
                viewModel.beginHistorySearch()
            } label: {
                EmptyView()
            }
            .keyboardShortcut("r", modifiers: [.control])
        }
        .frame(width: 0, height: 0)
        .opacity(0.0001)
        .allowsHitTesting(false)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.sqlText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .focused($isEditorFocused)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
                    .accessibilityIdentifier(DatabaseBrowserAccessibility.queryEditor.rawValue)

                if viewModel.sqlText.isEmpty {
                    Text("Type a SQL query here, or select a table from the sidebar to auto-generate a SELECT.")
                        .foregroundStyle(.secondary)
                        .padding(14)
                }

                if viewModel.isHistorySearchPresented {
                    HistorySearchOverlay(
                        viewModel: viewModel,
                        focusEditor: { isEditorFocused = true }
                    )
                    .padding(12)
                }
            }

            if isReadOnly && !viewModel.allowsReadOnlyExecution() {
                Label("Read-only mode allows SELECT, WITH, SHOW, DESCRIBE, and EXPLAIN statements.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canExecute: Bool {
        let trimmed = viewModel.sqlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !viewModel.isExecuting, !trimmed.isEmpty else { return false }
        if isReadOnly {
            return viewModel.allowsReadOnlyExecution(for: trimmed)
        }
        return true
    }
}

private struct HistorySearchOverlay: View {
    @ObservedObject var viewModel: DatabaseQueryEditorViewModel
    let focusEditor: () -> Void
    @FocusState private var isSearchFieldFocused: Bool
    #if os(macOS)
    @State private var keyMonitor: Any?
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Search history", text: $viewModel.historySearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFieldFocused)
                    .onSubmit(handleAccept)

                Button(action: handleAccept) {
                    Label("Use", systemImage: "arrow.down.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.defaultAction)

                Button("Cancel") {
                    handleCancel()
                }
                .keyboardShortcut(.cancelAction)
            }

            if let preview = viewModel.historySearchPreview {
                Text(preview)
                    .font(.caption.monospaced())
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No history matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Ctrl-R to search history. ↑/↓ to browse, Enter to insert, Esc to cancel.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 2)
        .onAppear {
            isSearchFieldFocused = true
            startMonitoringKeys()
        }
        .onDisappear {
            stopMonitoringKeys()
        }
    }

    private func handleAccept() {
        let accepted = viewModel.acceptHistorySearchMatch() != nil
        if accepted {
            focusEditor()
        }
    }

    private func handleCancel() {
        viewModel.cancelHistorySearch()
        focusEditor()
    }

    private func startMonitoringKeys() {
        #if os(macOS)
        stopMonitoringKeys()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard viewModel.isHistorySearchPresented else { return event }
            switch event.specialKey {
            case .upArrow?:
                viewModel.selectPreviousHistorySearchMatch()
                return nil
            case .downArrow?:
                viewModel.selectNextHistorySearchMatch()
                return nil
            default:
                return event
            }
        }
        #endif
    }

    private func stopMonitoringKeys() {
        #if os(macOS)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        #endif
    }
}

private struct DatabaseQueryResultView: View {
    let result: DatabaseQueryResult
    let executionDuration: Duration?

    private var columns: [String] {
        let keys = result.rows.flatMap { $0.values.keys }
        return Array(Set(keys)).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("Rows: \(result.rows.count)", systemImage: "tablecells")
                if let affected = result.affectedRowCount {
                    Label("Affected: \(affected)", systemImage: "number")
                }
                if let executionTimeDescription {
                    Label("Time: \(executionTimeDescription)", systemImage: "clock")
                }
            }
            .font(.subheadline)

            if result.rows.isEmpty {
                ContentUnavailableView(
                    "No rows returned",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Run a query that returns rows to see them here.")
                )
            } else {
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 6) {
                        headerRow
                        Divider()
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(result.rows.enumerated()), id: \.offset) { index, row in
                                dataRow(index: index, row: row)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier(DatabaseBrowserAccessibility.queryResultGrid.rawValue)
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            ForEach(columns, id: \.self) { column in
                Text(column)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(minWidth: 120, alignment: .leading)
            }
        }
    }

    private func dataRow(index: Int, row: DatabaseQueryRow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ForEach(columns, id: \.self) { column in
                let text = DatabaseTableContentViewModel.displayText(from: row.values[column])
                Text(text)
                    .font(.caption)
                    .frame(minWidth: 120, alignment: .leading)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .background(index % 2 == 0 ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var executionTimeDescription: String? {
        guard let executionDuration else { return nil }
        let components = executionDuration.components
        let millisecondsFromSeconds = Double(components.seconds) * 1_000
        let millisecondsFromAttoseconds = Double(components.attoseconds) / 1_000_000_000_000_000
        let total = millisecondsFromSeconds + millisecondsFromAttoseconds
        let rounded = Int(total.rounded())
        return "\(rounded) ms"
    }
}

struct DatabaseQueryResultSection: View {
    @ObservedObject var viewModel: DatabaseQueryEditorViewModel
    let isReadOnly: Bool
    let onExecute: (() -> Void)?

    var body: some View {
        if let error = viewModel.errorMessage {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(error)
                    .foregroundStyle(.primary)
                    .font(.callout)
                Spacer()
                Button("Retry") {
                    onExecute?()
                    viewModel.requestExecute(isReadOnly: isReadOnly)
                }
                .buttonStyle(.bordered)
            }
            .padding(10)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier(DatabaseBrowserAccessibility.queryErrorMessage.rawValue)
        } else if let result = viewModel.result {
            DatabaseQueryResultView(
                result: result,
                executionDuration: viewModel.lastExecutionDuration
            )
        } else {
            Text("Results will appear here after you run a query.")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }
}

#Preview("Query Editor") {
    DatabaseQueryEditorView(
        viewModel: DatabaseQueryEditorViewModel(
            executor: { _ in
                DatabaseQueryResult(rows: [
                    DatabaseQueryRow(values: ["id": .int(1), "name": .string("Alice")]),
                    DatabaseQueryRow(values: ["id": .int(2), "name": .string("Bob")]),
                ])
            }
        ),
        isReadOnly: false
    )
    .padding()
}
