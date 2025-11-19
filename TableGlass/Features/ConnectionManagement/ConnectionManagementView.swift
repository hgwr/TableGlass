import Foundation
import SwiftUI
import TableGlassKit
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct ConnectionManagementView: View {
    @StateObject private var viewModel: ConnectionManagementViewModel
    @State private var isDeleteConfirmationPresented = false
    @State private var isSSHKeyFileImporterPresented = false

    init(viewModel: ConnectionManagementViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var selectionBinding: Binding<ConnectionProfile.ID?> {
        Binding(
            get: { viewModel.selection },
            set: { newValue in
                Task { @MainActor [viewModel] in
                    if let id = newValue {
                        viewModel.applySelection(id: id)
                    } else {
                        viewModel.clearSelection()
                    }
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
                    sshAliasRow
                    sshAuthenticationPicker
                    TextField("SSH User", text: draftBinding(\.sshUsername))
                    switch viewModel.draft.sshAuthenticationMethod {
                    case .keyFile:
                        sshIdentityRow
                        sshKeyFileRow
                    case .usernameAndPassword:
                        sshPasswordRow
                    case .sshAgent:
                        sshAgentStatusView
                    }
                }
            }

            footerButtons
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .fileImporter(
            isPresented: $isSSHKeyFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else {
                return
            }
            viewModel.updateDraft { $0.sshKeyFilePath = url.path }
        }
    }

    private var sshAliasRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("SSH Config Alias", text: draftBinding(\.sshConfigAlias))
                Menu {
                    if viewModel.sshAliasOptions.isEmpty {
                        Button("No aliases available") {}
                            .disabled(true)
                    } else {
                        ForEach(viewModel.sshAliasOptions, id: \.self) { alias in
                            Button(alias) {
                                viewModel.updateDraft { $0.sshConfigAlias = alias }
                            }
                        }
                    }
                } label: {
                    Label("Aliases", systemImage: "list.bullet")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 24)
                }
                .disabled(viewModel.sshAliasOptions.isEmpty)
                .help("Choose an alias parsed from ~/.ssh/config")

                Button {
                    Task {
                        await viewModel.reloadSSHAliases()
                    }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Reload aliases from ~/.ssh/config")
                .disabled(viewModel.isLoadingSSHAliases)
            }

            if viewModel.isLoadingSSHAliases {
                ProgressView("Loading aliases…")
                    .controlSize(.small)
            } else if let error = viewModel.sshAliasError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if viewModel.sshAliasOptions.isEmpty {
                Text("No host aliases found in ~/.ssh/config.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sshAuthenticationPicker: some View {
        Picker("SSH Authentication", selection: draftBinding(\.sshAuthenticationMethod)) {
            ForEach(ConnectionProfile.SSHConfiguration.AuthenticationMethod.allCases, id: \.self) { method in
                Text(title(for: method)).tag(method)
            }
        }
        .pickerStyle(.menu)
    }

    private var sshIdentityRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Menu {
                    Button("None") {
                        viewModel.selectSSHIdentity(nil)
                    }

                    if viewModel.availableSSHIdentities.isEmpty {
                        Button("No identities available") {}
                            .disabled(true)
                    } else {
                        ForEach(viewModel.availableSSHIdentities, id: \.persistentReference) { identity in
                            Button(identity.label) {
                                viewModel.selectSSHIdentity(identity)
                            }
                        }
                    }
                } label: {
                    Label(
                        selectedIdentityLabel,
                        systemImage: "key.fill"
                    )
                }
                .menuStyle(.borderlessButton)
                .frame(minWidth: 220, alignment: .leading)
                .help("Choose a Keychain identity for SSH authentication")

                Button {
                    Task {
                        await viewModel.reloadSSHIdentities()
                    }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Reload Keychain identities")
                .disabled(viewModel.isLoadingSSHIdentities)
            }

            if viewModel.isLoadingSSHIdentities {
                ProgressView("Loading identities…")
                    .controlSize(.small)
            } else if let error = viewModel.sshIdentityError {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
            } else if viewModel.availableSSHIdentities.isEmpty {
                Text("No Keychain identities accessible. Use Keychain Access to grant TableGlass permission.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if viewModel.draft.sshKeychainIdentityReference == nil {
                Text("Select a Keychain identity to enable SSH tunneling.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let label = viewModel.draft.sshKeychainIdentityLabel {
                Text("Using Keychain identity: \(label)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sshKeyFileRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("Key File Path", text: draftBinding(\.sshKeyFilePath))
                Button {
                    isSSHKeyFileImporterPresented = true
                } label: {
                    Label("Browse", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .help("Choose a private key file")
            }

            Text("TableGlass stores only secure references to your SSH keys via the macOS Keychain.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var sshPasswordRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            SecureField("SSH Password", text: draftBinding(\.sshPassword))
            if viewModel.draft.sshPasswordKeychainIdentifier != nil
                && viewModel.draft.sshPassword.isEmpty
            {
                Text("Password stored securely")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sshAgentStatusView: some View {
        Text(
            viewModel.isSSHAgentReachable
                ? "We found your SSH Agent. You're good to go!"
                : "SSH Agent is not accessible. Start an agent or ensure TableGlass can reach it."
        )
        .font(.footnote)
        .foregroundStyle(viewModel.isSSHAgentReachable ? Color.green : Color.secondary)
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

    private var selectedIdentityLabel: String {
        if let label = viewModel.draft.sshKeychainIdentityLabel,
            !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return label
        }
        return "Select Keychain Identity"
    }

    private func title(for method: ConnectionProfile.SSHConfiguration.AuthenticationMethod) -> String {
        switch method {
        case .keyFile:
            return "Key File"
        case .usernameAndPassword:
            return "Username & Password"
        case .sshAgent:
            return "SSH Agent"
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
        _viewModel = StateObject(
            wrappedValue: ConnectionManagementViewModel(
                connectionStore: store,
                sshAliasProvider: PreviewSSHAliasProvider(),
                sshKeychainService: PreviewSSHKeychainService()
            )
        )
        self.configure = configure
    }

    var body: some View {
        ConnectionManagementView(viewModel: viewModel)
            .task {
                await configure(viewModel)
            }
    }
}

private struct PreviewSSHAliasProvider: SSHConfigAliasProvider {
    func availableAliases() async throws -> [String] {
        ["bastion", "staging", "analytics"]
    }
}

private struct PreviewSSHKeychainService: SSHKeychainService {
    func allIdentities() async throws -> [SSHKeychainIdentityReference] {
        [
            SSHKeychainIdentityReference(
                label: "bastion-key",
                persistentReference: Data([0x01, 0x02])
            ),
            SSHKeychainIdentityReference(
                label: "analytics-key",
                persistentReference: Data([0x03, 0x04])
            ),
        ]
    }

    func identity(forLabel label: String) async throws -> SSHKeychainIdentityReference? {
        try await allIdentities().first { $0.label == label }
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
