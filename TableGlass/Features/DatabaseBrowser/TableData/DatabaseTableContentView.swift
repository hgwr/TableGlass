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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .task {
            await viewModel.loadIfNeeded(for: table, columns: columns)
        }
        .onChange(of: table) { _, newValue in
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
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)

                Divider()

                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.rows) { row in
                        dataRow(for: row)
                    }

                    if viewModel.hasMorePages && !viewModel.rows.isEmpty {
                        loadMoreRow
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier(DatabaseBrowserAccessibility.dataGrid.rawValue)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            ForEach(viewModel.columns, id: \.name) { column in
                VStack(alignment: .leading, spacing: 2) {
                    Text(column.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(column.dataTypeDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 140, alignment: .leading)
            }

            Text("Status")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 110, alignment: .leading)

            Text("Actions")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 180, alignment: .leading)
        }
    }

    private func dataRow(for row: DatabaseTableContentViewModel.EditableTableRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(viewModel.columns, id: \.name) { column in
                cell(for: row, column: column)
                    .frame(minWidth: 140, alignment: .leading)
            }

            statusCell(for: row)
                .frame(width: 110, alignment: .leading)

            actionsCell(for: row)
                .frame(width: 180, alignment: .leading)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(row.error != nil ? Color.red.opacity(0.06) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            viewModel.selection.contains(row.id) ? Color.accentColor.opacity(0.5) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection(for: row.id)
        }
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
        .task {
            await viewModel.prefetchNextPageIfNeeded(currentRowID: row.id)
        }
    }

    private func actionsCell(for row: DatabaseTableContentViewModel.EditableTableRow) -> some View {
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

    private func toggleSelection(for id: DatabaseTableContentViewModel.EditableTableRow.ID) {
        if viewModel.selection.contains(id) {
            viewModel.selection.remove(id)
        } else {
            viewModel.selection.insert(id)
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
            if viewModel.isLoadingPage {
                ProgressView("Loading next page…")
                    .controlSize(.small)
            } else {
                Button {
                    Task { await viewModel.loadNextPage() }
                } label: {
                    Label("Load More", systemImage: "ellipsis")
                }
                .disabled(viewModel.isLoadingPage)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .onAppear {
            Task { await viewModel.loadNextPage() }
        }
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
