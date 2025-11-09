import SwiftUI
import TableGlassKit

#if os(macOS)
import AppKit
#endif

struct ConnectionManagementView: View {
    @StateObject private var viewModel: ConnectionManagementViewModel
    @State private var isDeleteConfirmationPresented = false

    init(viewModel: ConnectionManagementViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var selectionBinding: Binding<ConnectionProfile.ID?> {
        Binding(
            get: { viewModel.selection },
            set: { newValue in
                if let id = newValue {
                    viewModel.applySelection(id: id)
                } else {
                    viewModel.clearSelection()
                }
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading) {
                List(selection: selectionBinding) {
                    Section("Connections") {
                        ForEach(viewModel.connections) { connection in
                            Label(connection.name, systemImage: iconName(for: connection.kind))
                                .tag(connection.id)
                        }
                    }
                }
                .listStyle(.sidebar)

                Button {
                    viewModel.startCreatingConnection()
                } label: {
                    Label("New Connection", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        } detail: {
            detailContent
        }
        .task {
            await viewModel.loadConnections()
        }
        .alert("Error", isPresented: errorBinding) {
            Button("Dismiss", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            if let message = viewModel.lastError {
                Text(message)
            }
        }
    }

    private var detailContent: some View {
        Group {
            if viewModel.isNewConnection || viewModel.selection != nil {
                ScrollView(.vertical) {
                    connectionDetail
                        .frame(maxWidth: 520)
                        .padding(.vertical, 24)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                placeholderDetail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var connectionDetail: some View {
        Form {
            Section(header: Text("General")) {
                TextField("Display Name", text: draftBinding(\.name))

                Picker("Database", selection: draftBinding(\.kind)) {
                    ForEach(ConnectionProfile.DatabaseKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }

                TextField("Host", text: draftBinding(\.host))
                Stepper(value: draftBinding(\.port), in: 0...65_535) {
                    HStack {
                        Text("Port")
                        Spacer()
                        Text("\(viewModel.draft.port)")
                    }
                }
            }

            Section(header: Text("Credentials")) {
                TextField("Username", text: draftBinding(\.username))
                SecureField("Password", text: draftBinding(\.password))
                if viewModel.draft.passwordKeychainIdentifier != nil
                    && viewModel.draft.password.isEmpty
                {
                    Text("Password stored securely")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: Text("SSH Tunnel")) {
                Toggle("Use SSH", isOn: draftBinding(\.useSSHTunnel))
                if viewModel.draft.useSSHTunnel {
                    TextField("SSH Config Alias", text: draftBinding(\.sshConfigAlias))
                    TextField("SSH User", text: draftBinding(\.sshUsername))
                }
            }

            footerButtons
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var placeholderDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.person.crop")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select a connection")
                .font(.title3)
            Text("Choose a connection from the list or create a new one to configure it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footerButtons: some View {
        HStack {
            Button(role: .destructive) {
                isDeleteConfirmationPresented = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(viewModel.isNewConnection || viewModel.selection == nil)

            Spacer()

            Button {
                Task {
                    await viewModel.saveCurrentConnection()
                }
            } label: {
                Label(
                    viewModel.isNewConnection ? "Create" : "Save",
                    systemImage: "tray.and.arrow.down")
            }
            .disabled(!viewModel.draft.isValid || viewModel.isSaving)
        }
        .alert("Delete Connection?", isPresented: $isDeleteConfirmationPresented) {
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteSelectedConnection()
                }
            }
            Button("Cancel", role: .cancel) {
                isDeleteConfirmationPresented = false
            }
        } message: {
            Text("This action removes the selected connection and cannot be undone.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.lastError != nil },
            set: { presented in
                if !presented {
                    viewModel.clearError()
                }
            }
        )
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<ConnectionDraft, Value>) -> Binding<
        Value
    > {
        Binding(
            get: { viewModel.draft[keyPath: keyPath] },
            set: { newValue in viewModel.updateDraft { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func iconName(for kind: ConnectionProfile.DatabaseKind) -> String {
        switch kind {
        case .postgreSQL:
            return "leaf"
        case .mySQL:
            return "tortoise"
        case .sqlite:
            return "externaldrive"
        }
    }
}

extension ConnectionProfile.DatabaseKind {
    fileprivate var label: String {
        switch self {
        case .postgreSQL:
            return "PostgreSQL"
        case .mySQL:
            return "MySQL"
        case .sqlite:
            return "SQLite"
        }
    }
}

#if DEBUG
private struct ConnectionManagementPreviewContainer: View {
    let configure: @MainActor (ConnectionManagementViewModel) async -> Void
    @StateObject private var viewModel: ConnectionManagementViewModel

    init(
        store: some ConnectionStore,
        configure: @escaping @MainActor (ConnectionManagementViewModel) async -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ConnectionManagementViewModel(connectionStore: store))
        self.configure = configure
    }

    var body: some View {
        ConnectionManagementView(viewModel: viewModel)
            .task {
                await configure(viewModel)
            }
    }
}
#endif

#Preview("Connection Management – Populated") {
    ConnectionManagementPreviewContainer(store: PreviewConnectionStore()) { viewModel in
        await viewModel.loadConnections()
    }
}

#Preview("Connection Management – Placeholder") {
    ConnectionManagementPreviewContainer(store: PreviewConnectionStore()) { viewModel in
        await viewModel.loadConnections()
        viewModel.clearSelection()
    }
}
