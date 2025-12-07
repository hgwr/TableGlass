import Foundation
import SwiftUI
import TableGlassKit
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct ConnectionManagementView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var viewModel: ConnectionManagementViewModel
    @State private var isDeleteConfirmationPresented = false
    @State private var isSSHKeyFileImporterPresented = false
    @State private var isConnecting = false
    @FocusState private var focusedField: FieldFocus?

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

    private var draftConnections: [ConnectionProfile] {
        viewModel.connections.filter(\.isDraft)
    }

    private var finalizedConnections: [ConnectionProfile] {
        viewModel.connections.filter { !$0.isDraft }
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading) {
                List(selection: selectionBinding) {
                    if !draftConnections.isEmpty {
                        Section("Drafts") {
                            ForEach(draftConnections) { connection in
                                connectionRow(for: connection)
                            }
                        }
                    }
                    if !finalizedConnections.isEmpty {
                        Section("Connections") {
                            ForEach(finalizedConnections) { connection in
                                connectionRow(for: connection)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)

                Button {
                    viewModel.startCreatingConnection()
                } label: {
                    Label("New Connection", systemImage: "plus")
                }
                .accessibilityIdentifier("connectionManagement.newConnectionButton")
                .buttonStyle(.borderedProminent)
                .padding()
            }
        } detail: {
            detailContent
        }
        .task {
            await viewModel.loadConnections()
        }
    }

    private var detailContent: some View {
        Group {
            if viewModel.isNewConnection || viewModel.selection != nil {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            connectionDetail(scrollProxy: proxy)
                                .frame(maxWidth: 520)
                                .padding(.vertical, 24)
                                .padding(.horizontal, 32)
                                .frame(maxWidth: .infinity, alignment: .top)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }

                    actionArea
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("connectionManagement.form")
            } else {
                placeholderDetail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func connectionDetail(scrollProxy: ScrollViewProxy) -> some View {
        Form {
            if viewModel.draft.isDraft {
                draftBanner(scrollProxy: scrollProxy)
            }
            Section(header: Text("General")) {
                highlightedField(.name) {
                    TextField("Display Name", text: draftBinding(\.name))
                }
                .id(ConnectionDraft.MissingField.name)
                .focused($focusedField, equals: .name)
                    .accessibilityIdentifier("Display Name")

                Picker("Database", selection: draftBinding(\.kind)) {
                    ForEach(ConnectionProfile.DatabaseKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }

                highlightedField(.host) {
                    TextField("Host", text: draftBinding(\.host))
                }
                .id(ConnectionDraft.MissingField.host)
                .focused($focusedField, equals: .host)
                    .accessibilityIdentifier("Host")
                highlightedField(.port) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(
                            "Port",
                            text: portBinding,
                            prompt: Text("\(ConnectionProfile.defaultPort(for: viewModel.draft.kind))")
                        )
                            .focused($focusedField, equals: .port)
                            .accessibilityIdentifier("Port")
                        if let message = viewModel.portValidationMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .id(ConnectionDraft.MissingField.port)
            }

            Section(header: Text("Credentials")) {
                highlightedField(.username) {
                    TextField("Username", text: draftBinding(\.username))
                }
                .id(ConnectionDraft.MissingField.username)
                .focused($focusedField, equals: .username)
                    .accessibilityIdentifier("Username")
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
                    highlightedField(.sshUsername) {
                        TextField("SSH User", text: draftBinding(\.sshUsername))
                    }
                    .id(ConnectionDraft.MissingField.sshUsername)
                    .focused($focusedField, equals: .sshUsername)
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

        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connectionManagement.form")
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
        highlightedField(.sshAlias) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("SSH Config Alias", text: draftBinding(\.sshConfigAlias))
                        .focused($focusedField, equals: .sshAlias)
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
        .id(ConnectionDraft.MissingField.sshAlias)
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
        highlightedField(.sshCredential) {
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
        .id(ConnectionDraft.MissingField.sshCredential)
    }

    private var sshKeyFileRow: some View {
        highlightedField(.sshCredential) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("Key File Path", text: draftBinding(\.sshKeyFilePath))
                        .focused($focusedField, equals: .sshKeyFile)
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
        .id(ConnectionDraft.MissingField.sshCredential)
    }

    private var sshPasswordRow: some View {
        highlightedField(.sshCredential) {
            VStack(alignment: .leading, spacing: 6) {
                SecureField("SSH Password", text: draftBinding(\.sshPassword))
                    .focused($focusedField, equals: .sshPassword)
                if viewModel.draft.sshPasswordKeychainIdentifier != nil
                    && viewModel.draft.sshPassword.isEmpty
                {
                    Text("Password stored securely")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .id(ConnectionDraft.MissingField.sshCredential)
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

    private var actionArea: some View {
        VStack(spacing: 12) {
            Divider()
            errorCallout
            footerButtons
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var footerButtons: some View {
        HStack {
            Button(role: .destructive) {
                isDeleteConfirmationPresented = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(viewModel.isNewConnection || viewModel.selection == nil || isConnecting)

            Spacer()

            Button {
                Task {
                    _ = await viewModel.saveDraft()
                }
            } label: {
                Label("Save Draft", systemImage: "doc.badge.clock")
            }
            .help("Store this connection without completing validation.")
            .disabled(
                !viewModel.draft.hasAnyContent
                    || viewModel.portValidationMessage != nil
                    || viewModel.isSaving
                    || isConnecting
            )

            Button {
                Task {
                    _ = await viewModel.saveCurrentConnection()
                }
            } label: {
                Label(
                    viewModel.isNewConnection ? "Create" : "Save",
                    systemImage: "tray.and.arrow.down")
            }
            .accessibilityIdentifier("connectionManagement.saveButton")
            .disabled(!viewModel.isDraftValid || viewModel.isSaving || isConnecting)

            Button {
                let isUITest = ProcessInfo.processInfo.isRunningUITests
                let isBrowserUITest = ProcessInfo.processInfo.arguments.contains(UITestArguments.databaseBrowser.rawValue)
                if isUITest && !isBrowserUITest {
                    viewModel.presentError("Connection failed in test mode.")
                    return
                }
                Task {
                    await connectAndOpenBrowser()
                }
            } label: {
                Label("Connect", systemImage: "link")
            }
            .accessibilityIdentifier("connectionManagement.connectButton")
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(
                !viewModel.isDraftValid
                    || viewModel.draft.isDraft
                    || viewModel.isSaving
                    || isConnecting
            )
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

    private var errorCallout: some View {
        Group {
            if let message = viewModel.lastError {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("connectionManagement.errorMessage")
                    Spacer()
                    Button {
                        viewModel.clearError()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Dismiss error")
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func connectionRow(for connection: ConnectionProfile) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.displayName)
                    Text(connection.kind.label)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: iconName(for: connection.kind))
            }

            Spacer()

            if connection.isDraft {
                Text("Draft")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15), in: Capsule())
            }
        }
        .tag(connection.id)
    }

    private var missingFieldSummary: String? {
        let labels = viewModel.missingRequiredFields.map(\.label)
        guard !labels.isEmpty else { return nil }
        return "Missing: " + labels.joined(separator: ", ")
    }

    private func draftBanner(scrollProxy: ScrollViewProxy) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(
                systemName: viewModel.isDraftValid
                    ? "doc.badge.clock.fill"
                    : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(viewModel.isDraftValid ? Color.accentColor : Color.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Draft in progress")
                    .font(.headline)
                if let summary = missingFieldSummary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("All required fields are filled. Save to promote this draft.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let missing = viewModel.nextMissingField {
                Button {
                    jump(to: missing, using: scrollProxy)
                } label: {
                    Label("Jump to next", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .id("draft-banner")
    }

    private func jump(to missing: ConnectionDraft.MissingField, using proxy: ScrollViewProxy) {
        withAnimation {
            proxy.scrollTo(missing, anchor: .center)
        }
        focusedField = focusTarget(for: missing)
    }

    private func focusTarget(for missing: ConnectionDraft.MissingField) -> FieldFocus? {
        switch missing {
        case .name:
            return .name
        case .host:
            return .host
        case .port:
            return .port
        case .username:
            return .username
        case .sshAlias:
            return .sshAlias
        case .sshUsername:
            return .sshUsername
        case .sshCredential:
            switch viewModel.draft.sshAuthenticationMethod {
            case .keyFile:
                return .sshKeyFile
            case .usernameAndPassword:
                return .sshPassword
            case .sshAgent:
                return .sshUsername
            }
        }
    }

    @ViewBuilder
    private func highlightedField<Content: View>(
        _ missingField: ConnectionDraft.MissingField,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let shouldHighlight = viewModel.draft.hasAnyContent || !viewModel.isNewConnection
        let isMissing = shouldHighlight && viewModel.missingRequiredFields.contains(missingField)
        content()
            .padding(.vertical, isMissing ? 4 : 0)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.orange.opacity(isMissing ? 0.75 : 0), lineWidth: isMissing ? 1 : 0)
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

    private var portBinding: Binding<String> {
        Binding(
            get: { viewModel.portInput },
            set: { newValue in viewModel.updatePortInput(newValue) }
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

    private enum FieldFocus: Hashable {
        case name
        case host
        case port
        case username
        case sshAlias
        case sshUsername
        case sshPassword
        case sshKeyFile
    }

    @MainActor
    private func connectAndOpenBrowser() async {
        guard !isConnecting else { return }

        isConnecting = true
        defer { isConnecting = false }

        let isUITest = ProcessInfo.processInfo.isRunningUITests
        let isBrowserUITest = ProcessInfo.processInfo.arguments.contains(UITestArguments.databaseBrowser.rawValue)
        if isUITest && !isBrowserUITest {
            viewModel.presentError("Connection failed in test mode.")
            return
        }

        if let profile = await viewModel.saveCurrentConnection() {
            do {
                try await environment.connectAndOpenBrowser(for: profile)
                viewModel.clearError()
            } catch {
                let message = error.localizedDescription.isEmpty
                    ? "Failed to connect. Please verify the driver is available."
                    : error.localizedDescription
                viewModel.presentError(message)
            }
        }
    }
}

private extension ConnectionDraft.MissingField {
    var label: String {
        switch self {
        case .name:
            return "Display Name"
        case .host:
            return "Host"
        case .port:
            return "Port"
        case .username:
            return "Username"
        case .sshAlias:
            return "SSH Alias"
        case .sshUsername:
            return "SSH User"
        case .sshCredential:
            return "SSH Credential"
        }
    }
}

extension ConnectionProfile {
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return isDraft ? "Untitled Draft" : "Untitled Connection"
        }
        return trimmed
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
#endif
