import SwiftUI
import TableGlassKit

struct DatabaseQueryEditorView: View {
    @ObservedObject var viewModel: DatabaseQueryEditorViewModel
    let isReadOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            editor
            footer
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
            Task { await viewModel.execute(isReadOnly: isReadOnly) }
        } label: {
            Label("Run", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canExecute)
        .help(isReadOnly && !viewModel.allowsReadOnlyExecution() ? "Read-only mode blocks this statement" : "Execute SQL")
        .accessibilityIdentifier(DatabaseBrowserAccessibility.queryRunButton.rawValue)
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
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
                    .accessibilityIdentifier(DatabaseBrowserAccessibility.queryEditor.rawValue)

                if viewModel.sqlText.isEmpty {
                    Text("Enter SQL to run against this connection…")
                        .foregroundStyle(.secondary)
                        .padding(14)
                }
            }

            if isReadOnly && !viewModel.allowsReadOnlyExecution() {
                Label("Read-only mode allows SELECT, WITH, SHOW, DESCRIBE, and EXPLAIN statements.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let error = viewModel.errorMessage {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(error)
                    .foregroundStyle(.primary)
                    .font(.callout)
                Spacer()
                Button("Retry") {
                    Task { await viewModel.execute(isReadOnly: isReadOnly) }
                }
                .buttonStyle(.bordered)
            }
            .padding(10)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier(DatabaseBrowserAccessibility.queryErrorMessage.rawValue)
        } else if let result = viewModel.result {
            DatabaseQueryResultView(result: result)
        } else {
            Text("Results will appear here after you run a query.")
                .foregroundStyle(.secondary)
                .font(.callout)
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

private struct DatabaseQueryResultView: View {
    let result: DatabaseQueryResult

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
