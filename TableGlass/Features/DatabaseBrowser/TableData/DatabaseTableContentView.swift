import SwiftUI
import TableGlassKit

struct DatabaseTableContentView: View {
    @ObservedObject var viewModel: DatabaseTableContentViewModel
    let table: DatabaseTableIdentifier
    let columns: [DatabaseColumn]
    let isReadOnly: Bool

    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            if let error = viewModel.bannerError {
                banner(for: error)
            }
            content
            if viewModel.hasMorePages && !viewModel.rows.isEmpty {
                loadMoreRow
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .task {
            await viewModel.loadIfNeeded(for: table, columns: columns)
        }
        .onChange(of: table) { newValue in
            Task { await viewModel.loadIfNeeded(for: newValue, columns: columns) }
        }
        .alert("Delete selected rows?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteSelectedRows() }
            }
            Button("Cancel", role: .cancel) { isShowingDeleteConfirmation = false }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.addRow()
            } label: {
                Label("Add Row", systemImage: "plus")
            }
            .accessibilityIdentifier(DatabaseBrowserAccessibility.addRowButton.rawValue)
            .disabled(isReadOnly || viewModel.isPerformingMutation)

            Button(role: .destructive) {
                isShowingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityIdentifier(DatabaseBrowserAccessibility.deleteRowButton.rawValue)
            .disabled(isReadOnly || viewModel.selection.isEmpty || viewModel.isPerformingMutation)

            if viewModel.isLoadingPage || viewModel.isPerformingMutation {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()
            if isReadOnly {
                Label("Read-Only", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
        .padding(.horizontal, 4)
    }

    private var content: some View {
        Group {
            if viewModel.rows.isEmpty && viewModel.isLoadingPage {
                VStack(alignment: .center, spacing: 12) {
                    ProgressView("Loading data…")
                    Text("Fetching rows for \(table.name)")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if viewModel.rows.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "tablecells",
                    description: Text("Use Add Row to insert data or adjust filters.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                tableView
            }
        }
    }

    private var tableView: some View {
        Table(viewModel.rows, selection: $viewModel.selection) {
            ForEach(columns, id: \.name) { column in
                TableColumn(column.name) { (row: DatabaseTableContentViewModel.EditableTableRow) in
                    cell(for: row, column: column)
                }
                .width(min: 120)
            }

            TableColumn("Status", content: statusCell)
                .width(90)

            TableColumn("Actions") { row in
                HStack(spacing: 8) {
                    if row.isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("Save") {
                        Task { await viewModel.commitRow(row.id) }
                    }
                    .disabled(isReadOnly || !row.hasChanges || row.isSaving)

                    Button("Delete", role: .destructive) {
                        viewModel.selection = [row.id]
                        isShowingDeleteConfirmation = true
                    }
                    .disabled(isReadOnly || row.isSaving)
                }
            }
            .width(160)
        }
        .tableStyle(.inset)
        .accessibilityIdentifier(DatabaseBrowserAccessibility.dataGrid.rawValue)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func statusCell(for row: DatabaseTableContentViewModel.EditableTableRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = row.error {
                Label("Error", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help(error)
            } else if row.hasChanges {
                Label("Unsaved", systemImage: "pencil")
                    .foregroundStyle(.secondary)
            } else {
                Label("Saved", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        }
    }

    private func banner(for message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout)
            Spacer()
            Button("Dismiss") {
                viewModel.clearBanner()
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(8)
    }

    private func cell(
        for row: DatabaseTableContentViewModel.EditableTableRow,
        column: DatabaseColumn
    ) -> some View {
        let binding = Binding<String>(
            get: { row.cells[column.name]?.text ?? "" },
            set: { newValue in viewModel.updateCell(id: row.id, column: column.name, text: newValue) }
        )

        return TextField(column.name, text: binding)
            .textFieldStyle(.roundedBorder)
            .disabled(isReadOnly || row.isSaving)
            .help(column.dataTypeDescription)
    }

    private var loadMoreRow: some View {
        HStack {
            Spacer()
            Button {
                Task { await viewModel.loadNextPage() }
            } label: {
                Label("Load More", systemImage: "ellipsis")
            }
            .disabled(viewModel.isLoadingPage)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private extension DatabaseColumn {
    var dataTypeDescription: String {
        switch dataType {
        case .integer:
            return "Integer"
        case .numeric(let precision, let scale):
            switch (precision, scale) {
            case (.some(let precision), .some(let scale)):
                return "Numeric(\(precision), \(scale))"
            case (.some(let precision), nil):
                return "Numeric(\(precision))"
            default:
                return "Numeric"
            }
        case .boolean:
            return "Boolean"
        case .text:
            return "Text"
        case .binary:
            return "Binary"
        case .timestamp(let withTimeZone):
            return withTimeZone ? "Timestamp with time zone" : "Timestamp"
        case .date:
            return "Date"
        case .custom(let value):
            return value
        }
    }
}
