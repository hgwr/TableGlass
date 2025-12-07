import SwiftUI

struct QuickResourcePaletteView: View {
    @ObservedObject var viewModel: QuickResourcePaletteViewModel
    let onSelect: (QuickResourceMatch) -> Void
    let onDismiss: () -> Void

    @State private var selection: QuickResourceMatch.ID?
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            header
            searchBar
            scopePicker
            resultsList
            footer
        }
        .frame(maxWidth: 720, maxHeight: 520, alignment: .topLeading)
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(radius: 12)
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.scheduleSearch()
        }
        .onChange(of: viewModel.selectedScope) { _, _ in
            viewModel.handleScopeChange()
        }
        .onAppear {
            viewModel.scheduleSearch()
            isSearchFieldFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Quick Open", systemImage: "command")
                .font(.headline)
            Spacer()
            if viewModel.isRefreshingMetadata {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Refreshing metadata")
            } else if let timestamp = viewModel.lastUpdated {
                Text("Updated \(timestamp.formatted(.relative(presentation: .numeric)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    private var searchBar: some View {
        DatabaseSearchTextField(
            prompt: "Search tables, views, or procedures",
            text: $viewModel.searchText,
            onSubmit: submitFirstMatch,
            autoFocus: true,
            focusBinding: $isSearchFieldFocused
        )
    }

    private var scopePicker: some View {
        Picker("Scope", selection: $viewModel.selectedScope) {
            Text("All").tag(QuickResourceKind?.none)
            ForEach(QuickResourceKind.allCases, id: \.self) { scope in
                Text(scope.displayName).tag(Optional(scope))
            }
        }
        .pickerStyle(.segmented)
    }

    private var resultsList: some View {
        List(selection: $selection) {
            ForEach(viewModel.matches) { match in
                Button {
                    selection = match.id
                    onSelect(match)
                } label: {
                    QuickResourceRow(match: match)
                }
                .buttonStyle(.plain)
                .tag(match.id)
            }
        }
        .listStyle(.inset)
        .overlay {
            if viewModel.isIndexEmpty {
                ContentUnavailableView(
                    "No metadata yet",
                    systemImage: "shippingbox",
                    description: Text("Connect to a database or wait for metadata to finish loading.")
                )
            } else if viewModel.matches.isEmpty {
                ContentUnavailableView(
                    "No matches",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Try a different query or scope.")
                )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label("⌘P to open, Enter to focus selection, Esc to close", systemImage: "keyboard")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let scope = viewModel.selectedScope {
                Text(scope.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}

private struct QuickResourceRow: View {
    let match: QuickResourceMatch

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: match.item.kind.systemImageName)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: match.item.name)
                    .font(.headline)
                Text("\(match.item.catalog).\(match.item.namespace)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(match.item.sessionName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private extension QuickResourcePaletteView {
    func submitFirstMatch() {
        guard let first = viewModel.matches.first else { return }
        selection = first.id
        onSelect(first)
    }
}
