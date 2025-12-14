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
    let placeholderText: String
    @FocusState private var isEditorFocused: Bool

    init(
        viewModel: DatabaseQueryEditorViewModel,
        isReadOnly: Bool,
        showsResultsInline: Bool = true,
        onExecute: (() -> Void)? = nil,
        placeholderText: String = "Results will appear here after you run a query."
    ) {
        self.viewModel = viewModel
        self.isReadOnly = isReadOnly
        self.showsResultsInline = showsResultsInline
        self.onExecute = onExecute
        self.placeholderText = placeholderText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            editor
            if showsResultsInline {
                DatabaseQueryResultSection(
                    viewModel: viewModel,
                    isReadOnly: isReadOnly,
                    onExecute: onExecute,
                    placeholderText: placeholderText
                )
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            Text("</> SQL")
                .font(.headline)
                .fontWeight(.semibold)
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
        .buttonBorderShape(.roundedRectangle)
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
                DatabaseSearchTextField(
                    prompt: "Search history",
                    text: $viewModel.historySearchQuery,
                    onSubmit: handleAccept,
                    autoFocus: true,
                    focusBinding: $isSearchFieldFocused
                )

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

struct DatabaseSearchTextField: View {
    let prompt: String
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil
    var autoFocus: Bool = false
    var focusBinding: FocusState<Bool>.Binding? = nil

    @FocusState private var isFocused: Bool

    private var effectiveFocus: FocusState<Bool>.Binding {
        focusBinding ?? $isFocused
    }

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.roundedBorder)
            .focused(effectiveFocus)
            .submitLabel(.search)
            .onAppear {
                if autoFocus {
                    effectiveFocus.wrappedValue = true
                }
            }
            .onSubmit {
                onSubmit?()
            }
    }
}

private struct DatabaseQueryResultView: View {
    @ObservedObject var viewModel: DatabaseQueryEditorViewModel
    let result: DatabaseQueryResult
    let columns: [String]
    let executionDuration: Duration?

    private var selectedRowIndex: Int? {
        viewModel.rowDetailSelection?.rowIndex
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

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

                if viewModel.isRowDetailPresented, let selection = viewModel.rowDetailSelection {
                    RowDetailView(
                        fields: viewModel.detailFields(for: selection),
                        selection: selection,
                        rowCount: result.rows.count,
                        copyFormat: $viewModel.rowDetailCopyFormat,
                        onCopy: { viewModel.copyCurrentDetailSelectionToClipboard() },
                        onCopyField: { column in viewModel.copyField(column) },
                        onSelectField: { column in viewModel.focusRowDetailField(column) },
                        onClose: { viewModel.isRowDetailPresented = false }
                    )
                    .padding(.top, 8)
                    .transition(.opacity)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("Rows: \(result.rows.count)", systemImage: "tablecells")
            if let affected = result.affectedRowCount {
                Label("Affected: \(affected)", systemImage: "number")
            }
            if let executionTimeDescription {
                Label("Time: \(executionTimeDescription)", systemImage: "clock")
            }
            Spacer()
            Button {
                viewModel.toggleRowDetail(forRowAt: selectedRowIndex)
            } label: {
                Label(
                    viewModel.isRowDetailPresented ? "Hide Row Detail" : "Row Detail",
                    systemImage: "list.bullet.rectangle"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier(DatabaseBrowserAccessibility.rowDetailToggle.rawValue)
            .help("Toggle an expanded row view")
            .disabled(result.rows.isEmpty)
        }
        .font(.subheadline)
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
        let isSelected = viewModel.rowDetailSelection?.rowIndex == index
        return HStack(alignment: .center, spacing: 12) {
            ForEach(columns, id: \.self) { column in
                let text = DatabaseTableContentViewModel.displayText(from: row.values[column])
                Text(text)
                    .font(.caption)
                    .frame(minWidth: 120, alignment: .leading)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.14)
                : index % 2 == 0 ? Color(nsColor: .controlBackgroundColor) : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectRowForDetail(index)
        }
        .onTapGesture(count: 2) {
            viewModel.presentRowDetail(forRowAt: index)
        }
    }
}

private struct RowDetailView: View {
    let fields: [RowDetailField]
    let selection: RowDetailSelection
    let rowCount: Int
    @Binding var copyFormat: RowCopyFormat
    let onCopy: () -> Void
    let onCopyField: (String) -> Void
    let onSelectField: (String) -> Void
    let onClose: () -> Void

    private var panelBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Row Detail", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Text("Row \(selection.rowIndex + 1) of \(rowCount)")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Copy format", selection: $copyFormat) {
                    ForEach(RowCopyFormat.allCases, id: \.self) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                Button {
                    onCopy()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command])
                .accessibilityIdentifier(DatabaseBrowserAccessibility.rowDetailCopyButton.rawValue)

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier(DatabaseBrowserAccessibility.rowDetailClose.rawValue)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(fields) { field in
                        RowDetailFieldRow(
                            field: field,
                            isSelected: selection.focusedColumn == field.name,
                            onSelect: {
                                onSelectField(field.name)
                            },
                            onCopy: {
                                onSelectField(field.name)
                                onCopyField(field.name)
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityIdentifier(DatabaseBrowserAccessibility.rowDetailPanel.rawValue)
        }
        .padding(12)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(radius: 2, y: 1)
    }
}

private struct RowDetailFieldRow: View {
    let field: RowDetailField
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(field.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy \(field.name)")
                .accessibilityIdentifier(DatabaseBrowserAccessibility.rowDetailCopyField.rawValue)
            }

            Text(field.value.isEmpty ? " " : field.value)
                .font(.callout.monospaced())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

struct DatabaseQueryResultSection: View {
    @ObservedObject var viewModel: DatabaseQueryEditorViewModel
    let isReadOnly: Bool
    let onExecute: (() -> Void)?
    let placeholderText: String

    init(
        viewModel: DatabaseQueryEditorViewModel,
        isReadOnly: Bool,
        onExecute: (() -> Void)?,
        placeholderText: String = "Results will appear here after you run a query."
    ) {
        self.viewModel = viewModel
        self.isReadOnly = isReadOnly
        self.onExecute = onExecute
        self.placeholderText = placeholderText
    }

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
                viewModel: viewModel,
                result: result,
                columns: viewModel.resultColumns,
                executionDuration: viewModel.lastExecutionDuration
            )
        } else {
            Text(placeholderText)
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
