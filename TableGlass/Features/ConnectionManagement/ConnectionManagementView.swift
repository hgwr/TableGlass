import SwiftUI
import TableGlassKit

struct ConnectionManagementView: View {
    @StateObject private var viewModel: ConnectionManagementViewModel

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
                    viewModel.startCreatingConnection(kind: viewModel.draft.kind)
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
            connectionDetail
                .padding()
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
                if viewModel.draft.passwordKeychainIdentifier != nil && viewModel.draft.password.isEmpty {
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
    }

    private var footerButtons: some View {
        HStack {
            Button(role: .destructive) {
                Task {
                    await viewModel.deleteSelectedConnection()
                }
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
                Label(viewModel.isNewConnection ? "Create" : "Save", systemImage: "tray.and.arrow.down")
            }
            .disabled(!viewModel.draft.isValid || viewModel.isSaving)
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

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<ConnectionDraft, Value>) -> Binding<Value> {
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

private extension ConnectionProfile.DatabaseKind {
    var label: String {
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

#Preview("Connection Management") {
    ConnectionManagementView(viewModel: ConnectionManagementViewModel(connectionStore: PreviewConnectionStore()))
}
