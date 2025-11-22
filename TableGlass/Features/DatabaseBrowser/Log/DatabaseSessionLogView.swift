import SwiftUI
import TableGlassKit

struct DatabaseSessionLogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: DatabaseSessionLogViewModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("\(viewModel.databaseName) Log")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        statusFilterPicker
                    }
                }
        }
        .frame(minWidth: 720, minHeight: 480)
        .searchable(text: $viewModel.searchText, placement: .automatic, prompt: "Filter SQL")
    }

    private var content: some View {
        Group {
            if viewModel.displayEntries.isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Queries will appear here as you run them.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(viewModel.displayEntries) { entry in
                    DatabaseSessionLogRow(entry: entry)
                        .padding(.vertical, 4)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }

    private var statusFilterPicker: some View {
        Picker("Outcome", selection: $viewModel.statusFilter) {
            ForEach(StatusFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
        .help("Filter by query outcome")
    }
}

private struct DatabaseSessionLogRow: View {
    let entry: DatabaseSessionLogDisplayEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.outcome.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(entry.outcome.isSuccess ? Color.green : Color.red)
                .accessibilityHidden(true)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.timestampText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.sql)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            Spacer()
        }
    }
}

#Preview("Session Log") {
    DatabaseSessionLogView(viewModel: DatabaseSessionLogViewModel.preview())
}
