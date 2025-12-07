import Combine
import Foundation
import OSLog
import TableGlassKit

@MainActor
final class ConnectionManagementViewModel: ObservableObject {
    @Published private(set) var connections: [ConnectionProfile] = []
    @Published var selection: ConnectionProfile.ID?
    @Published var draft: ConnectionDraft = .empty()
    @Published var portInput: String = ""
    @Published private(set) var portValidationMessage: String? = nil
    @Published private(set) var isNewConnection: Bool = false
    @Published private(set) var isSaving: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var sshAliases: [String] = []
    @Published private(set) var isLoadingSSHAliases: Bool = false
    @Published private(set) var sshAliasError: String?
    @Published private(set) var availableSSHIdentities: [SSHKeychainIdentityReference] = []
    @Published private(set) var isLoadingSSHIdentities: Bool = false
    @Published private(set) var sshIdentityError: String?
    @Published private(set) var isSSHAgentReachable: Bool = false

    private let connectionStore: any ConnectionStore
    private let sshAliasProvider: any SSHConfigAliasProvider
    private let sshKeychainService: any SSHKeychainService
    private let sshAgentService: any SSHAgentService
    private let databasePasswordStore: any DatabasePasswordStoring
    private let portFormatter: NumberFormatter
    private var hasLoadedSSHAliases = false
    private var hasLoadedSSHIdentities = false
    private let logger = Logger(subsystem: "com.tableglass", category: "ConnectionManagement")

    init(
        connectionStore: some ConnectionStore,
        sshAliasProvider: some SSHConfigAliasProvider = DefaultSSHConfigAliasProvider(),
        sshKeychainService: some SSHKeychainService = DefaultSSHKeychainService(),
        sshAgentService: some SSHAgentService = DefaultSSHAgentService(),
        databasePasswordStore: some DatabasePasswordStoring = KeychainDatabasePasswordStore()
    ) {
        self.connectionStore = connectionStore
        self.sshAliasProvider = sshAliasProvider
        self.sshKeychainService = sshKeychainService
        self.sshAgentService = sshAgentService
        self.databasePasswordStore = databasePasswordStore
        self.isSSHAgentReachable = sshAgentService.isAgentReachable()
        portFormatter = Self.makePortFormatter()
        resetPortInput(to: draft.port, clearValidation: true)
    }

    private static func makePortFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = 0
        formatter.maximum = 65_535
        formatter.usesGroupingSeparator = false
        return formatter
    }

    var sshAliasOptions: [String] {
        var options = sshAliases
        let current = draft.sshConfigAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, !options.contains(current) {
            options.insert(current, at: 0)
        }
        return options
    }

    var missingRequiredFields: [ConnectionDraft.MissingField] {
        var missing = draft.missingRequiredFields
        if portValidationMessage != nil && !missing.contains(.port) {
            missing.append(.port)
        }
        return missing
    }

    var nextMissingField: ConnectionDraft.MissingField? {
        missingRequiredFields.first
    }

    var isDraftValid: Bool {
        portValidationMessage == nil && missingRequiredFields.isEmpty
    }

    func loadConnections() async {
        await ensureSSHAliasesLoaded()
        await ensureSSHIdentitiesLoaded()
        do {
            connections = try await connectionStore.listConnections()
            for connection in connections {
                includeAliasInList(connection.sshConfiguration.configAlias)
            }
            if let first = connections.first {
                applySelection(id: first.id)
            } else {
                startCreatingConnection()
            }
        } catch {
            logger.error("Failed to load connections: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            connections = []
            startCreatingConnection()
        }
    }

    func updatePortInput(_ newValue: String) {
        portInput = newValue
        validatePortInput(newValue)
    }

    private func validatePortInput(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if draft.kind == .sqlite {
                portValidationMessage = nil
                updateDraft { $0.port = ConnectionProfile.defaultPort(for: .sqlite) }
            } else {
                portValidationMessage = "Enter a port number."
            }
            return
        }

        guard let number = portFormatter.number(from: trimmed) else {
            portValidationMessage = "Port must be a number."
            return
        }

        let intValue = number.intValue
        if intValue < 0 || intValue > 65_535 {
            portValidationMessage = "Port must be between 0 and 65535."
            return
        }

        portValidationMessage = nil
        updateDraft { $0.port = intValue }
        portInput = portFormatter.string(from: NSNumber(value: intValue)) ?? "\(intValue)"
    }

    private func resetPortInput(to port: Int, clearValidation: Bool = false) {
        if clearValidation {
            portValidationMessage = nil
        }
        portInput = portFormatter.string(from: NSNumber(value: port)) ?? "\(port)"
    }

    func reloadSSHAliases() async {
        isLoadingSSHAliases = true
        defer { isLoadingSSHAliases = false }

        do {
            let aliases = try await sshAliasProvider.availableAliases()
            hasLoadedSSHAliases = true
            sshAliasError = nil
            applySSHAliasList(aliases)
        } catch {
            hasLoadedSSHAliases = true
            sshAliasError = error.localizedDescription
        }
    }

    private func ensureSSHAliasesLoaded() async {
        if hasLoadedSSHAliases {
            if !draft.sshConfigAlias.isEmpty {
                includeAliasInList(draft.sshConfigAlias)
            }
            return
        }

        await reloadSSHAliases()
    }

    private func applySSHAliasList(_ aliases: [String]) {
        var seen = Set<String>()
        var ordered: [String] = []

        for alias in aliases {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                ordered.append(trimmed)
            }
        }

        let current = draft.sshConfigAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, seen.insert(current).inserted {
            ordered.insert(current, at: 0)
        }

        sshAliases = ordered
    }

    private func includeAliasInList(_ alias: String) {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !sshAliases.contains(trimmed) {
            sshAliases.insert(trimmed, at: 0)
        }
    }

    func reloadSSHIdentities() async {
        isLoadingSSHIdentities = true
        defer { isLoadingSSHIdentities = false }

        do {
            let identities = try await sshKeychainService.allIdentities()
            hasLoadedSSHIdentities = true
            sshIdentityError = nil
            applySSHIdentityList(identities)
        } catch {
            hasLoadedSSHIdentities = false
            sshIdentityError = error.localizedDescription
        }
    }

    private func ensureSSHIdentitiesLoaded() async {
        if hasLoadedSSHIdentities {
            synchronizeDraftIdentity()
            return
        }

        await reloadSSHIdentities()
    }

    private func applySSHIdentityList(_ identities: [SSHKeychainIdentityReference]) {
        let sorted = identities.sorted { left, right in
            left.label.localizedCaseInsensitiveCompare(right.label) == .orderedAscending
        }

        availableSSHIdentities = sorted
        synchronizeDraftIdentity()
    }

    private func synchronizeDraftIdentity() {
        guard draft.useSSHTunnel else {
            sshIdentityError = nil
            return
        }

        guard draft.sshAuthenticationMethod == .keyFile else {
            sshIdentityError = nil
            return
        }

        guard let label = draft.sshKeychainIdentityLabel, !label.isEmpty else {
            sshIdentityError = nil
            return
        }

        if let identity = availableSSHIdentities.first(where: { $0.label == label }) {
            if draft.sshKeychainIdentityReference != identity.persistentReference {
                draft.sshKeychainIdentityReference = identity.persistentReference
            }
            sshIdentityError = nil
        } else {
            if draft.sshKeychainIdentityReference == nil {
                sshIdentityError = "Selected Keychain identity is unavailable."
            } else {
                sshIdentityError = nil
            }
        }
    }

    private func resetDraftSSHIdentity() {
        draft.sshKeychainIdentityLabel = nil
        draft.sshKeychainIdentityReference = nil
        draft.sshKeyFilePath = ""
        sshIdentityError = nil
    }

    private func refreshSSHAgentStatus() {
        isSSHAgentReachable = sshAgentService.isAgentReachable()
    }

    private func handleSSHTunnelMutation(
        previousUseSSH: Bool,
        previousAlias: String,
        newUseSSH: Bool,
        newAlias: String
    ) {
        if !newUseSSH {
            resetDraftSSHIdentity()
            draft.sshAuthenticationMethod = .keyFile
            draft.sshPassword = ""
            draft.sshPasswordKeychainIdentifier = nil
            return
        }

        if !previousUseSSH {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.ensureSSHAliasesLoaded()
                if self.draft.sshAuthenticationMethod == .keyFile {
                    await self.ensureSSHIdentitiesLoaded()
                }
            }
        } else if previousAlias != newAlias {
            includeAliasInList(newAlias)
            synchronizeDraftIdentity()
        } else {
            synchronizeDraftIdentity()
        }

        if draft.sshAuthenticationMethod == .sshAgent {
            refreshSSHAgentStatus()
        }
    }

    private func handleSSHAuthenticationMethodChange(
        previous: ConnectionProfile.SSHConfiguration.AuthenticationMethod,
        current: ConnectionProfile.SSHConfiguration.AuthenticationMethod
    ) {
        if current != .keyFile {
            resetDraftSSHIdentity()
        } else if draft.useSSHTunnel {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.ensureSSHIdentitiesLoaded()
            }
        }

        if current != .usernameAndPassword {
            draft.sshPassword = ""
            draft.sshPasswordKeychainIdentifier = nil
        }

        if current != .keyFile {
            draft.sshKeyFilePath = ""
        }

        if current == .sshAgent, draft.useSSHTunnel {
            refreshSSHAgentStatus()
        }

        if previous == .sshAgent, current != .sshAgent {
            isSSHAgentReachable = sshAgentService.isAgentReachable()
        }
    }

    func applySelection(id: ConnectionProfile.ID) {
        guard let connection = connections.first(where: { $0.id == id }) else {
            return
        }
        selection = connection.id
        draft = ConnectionDraft(connection: connection)
        resetPortInput(to: draft.port, clearValidation: true)
        if !draft.sshConfigAlias.isEmpty {
            includeAliasInList(draft.sshConfigAlias)
        }
        if draft.useSSHTunnel {
            if draft.sshAuthenticationMethod == .keyFile {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.ensureSSHIdentitiesLoaded()
                }
            }
            synchronizeDraftIdentity()
            if draft.sshAuthenticationMethod == .sshAgent {
                refreshSSHAgentStatus()
            }
        } else {
            resetDraftSSHIdentity()
        }
        isNewConnection = false
        lastError = nil
    }

    func startCreatingConnection(kind: ConnectionProfile.DatabaseKind = .postgreSQL) {
        selection = nil
        draft = .empty(kind: kind)
        resetPortInput(to: draft.port, clearValidation: true)
        isNewConnection = true
        lastError = nil
        resetDraftSSHIdentity()
        refreshSSHAgentStatus()
    }

    func clearSelection() {
        selection = nil
        isNewConnection = false
        resetPortInput(to: draft.port, clearValidation: true)
        resetDraftSSHIdentity()
        refreshSSHAgentStatus()
    }

    func updateDraft(_ transform: (inout ConnectionDraft) -> Void) {
        let previousKind = draft.kind
        let previousPort = draft.port
        let previousPassword = draft.password
        let previousUseSSH = draft.useSSHTunnel
        let previousAlias = draft.sshConfigAlias
        let previousSSHPassword = draft.sshPassword
        let previousAuthenticationMethod = draft.sshAuthenticationMethod
        transform(&draft)
        if draft.kind != previousKind {
            draft.normalizeAfterKindChange(previousKind: previousKind)
        }
        if draft.port != previousPort || draft.kind != previousKind {
            resetPortInput(to: draft.port, clearValidation: draft.kind != previousKind)
            if draft.kind != previousKind {
                validatePortInput(portInput)
            }
        }
        if draft.password != previousPassword, !draft.password.isEmpty {
            draft.passwordKeychainIdentifier = nil
        }
        if draft.sshPassword != previousSSHPassword, !draft.sshPassword.isEmpty {
            draft.sshPasswordKeychainIdentifier = nil
        }
        if !draft.sshConfigAlias.isEmpty {
            includeAliasInList(draft.sshConfigAlias)
        }

        handleSSHTunnelMutation(
            previousUseSSH: previousUseSSH,
            previousAlias: previousAlias,
            newUseSSH: draft.useSSHTunnel,
            newAlias: draft.sshConfigAlias
        )

        if draft.sshAuthenticationMethod != previousAuthenticationMethod {
            handleSSHAuthenticationMethodChange(
                previous: previousAuthenticationMethod,
                current: draft.sshAuthenticationMethod
            )
        } else if draft.sshAuthenticationMethod == .sshAgent, draft.useSSHTunnel {
            refreshSSHAgentStatus()
        }
    }

    func selectSSHIdentity(_ identity: SSHKeychainIdentityReference?) {
        updateDraft { draft in
            guard draft.sshAuthenticationMethod == .keyFile else {
                draft.sshKeychainIdentityLabel = nil
                draft.sshKeychainIdentityReference = nil
                return
            }
            if let identity {
                draft.sshKeychainIdentityLabel = identity.label
                draft.sshKeychainIdentityReference = identity.persistentReference
            } else {
                draft.sshKeychainIdentityLabel = nil
                draft.sshKeychainIdentityReference = nil
            }
        }
    }

    func clearError() {
        lastError = nil
    }

    func presentError(_ message: String) {
        lastError = message
    }

    @discardableResult
    func saveDraft() async -> ConnectionProfile? {
        await persistCurrentConnection(asDraft: true)
    }

    @discardableResult
    func saveCurrentConnection() async -> ConnectionProfile? {
        await persistCurrentConnection(asDraft: false)
    }

    @discardableResult
    private func persistCurrentConnection(asDraft: Bool) async -> ConnectionProfile? {
        if let portValidationMessage {
            lastError = portValidationMessage
            return nil
        }

        if !asDraft && !isDraftValid {
            lastError = "Please complete the required fields."
            return nil
        }

        if asDraft && !draft.hasAnyContent {
            lastError = "Add at least one field before saving a draft."
            return nil
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let targetID = isNewConnection ? ConnectionProfile.ID() : (selection ?? ConnectionProfile.ID())
            let profileIsDraft = asDraft
            var profile = draft.makeProfile(id: targetID, isDraft: profileIsDraft)
            try await persistDatabasePassword(into: &profile, isDraft: profileIsDraft)

            if isNewConnection {
                try await connectionStore.saveConnection(profile)
                connections.append(profile)
            } else if let selection {
                try await connectionStore.saveConnection(profile)
                if let index = connections.firstIndex(where: { $0.id == selection }) {
                    connections[index] = profile
                }
            }
            applySelection(id: profile.id)
            lastError = nil
            return profile
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func deleteSelectedConnection() async {
        guard let selection else {
            return
        }
        let target = connections.first(where: { $0.id == selection })

        do {
            try await connectionStore.deleteConnection(id: selection)
            connections.removeAll { $0.id == selection }
            if let target {
                await deletePasswordIfNeeded(for: target)
            }
            if let next = connections.first {
                applySelection(id: next.id)
            } else {
                startCreatingConnection(kind: draft.kind)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persistDatabasePassword(
        into profile: inout ConnectionProfile,
        isDraft: Bool
    ) async throws {
        let trimmed = draft.password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let identifier = profile.passwordKeychainIdentifier
            ?? draft.passwordKeychainIdentifier
            ?? passwordKeychainIdentifier(for: profile.id, isDraft: isDraft)
        let stored = try await databasePasswordStore.store(password: trimmed, identifier: identifier)
        profile.passwordKeychainIdentifier = stored
        draft.passwordKeychainIdentifier = stored
        draft.password = ""
    }

    private func deletePasswordIfNeeded(for profile: ConnectionProfile) async {
        var identifiers = Set<String>()
        if let identifier = profile.passwordKeychainIdentifier {
            identifiers.insert(identifier)
        }
        identifiers.insert(passwordKeychainIdentifier(for: profile.id, isDraft: true))
        identifiers.insert(passwordKeychainIdentifier(for: profile.id, isDraft: false))

        for identifier in identifiers {
            _ = try? await databasePasswordStore.deletePassword(identifier: identifier)
        }
    }

    private func passwordKeychainIdentifier(for id: ConnectionProfile.ID, isDraft: Bool) -> String {
        let scope = isDraft ? "draft" : "profile"
        return "tableglass.connection.\(scope).\(id.uuidString)"
    }
}

struct ConnectionDraft: Equatable {
    var name: String
    var kind: ConnectionProfile.DatabaseKind
    var host: String
    var port: Int
    var username: String
    var password: String
    var passwordKeychainIdentifier: String?
    var useSSHTunnel: Bool
    var sshConfigAlias: String
    var sshUsername: String
    var sshAuthenticationMethod: ConnectionProfile.SSHConfiguration.AuthenticationMethod
    var sshKeyFilePath: String
    var sshPassword: String
    var sshPasswordKeychainIdentifier: String?
    var sshKeychainIdentityLabel: String?
    var sshKeychainIdentityReference: Data?
    var isDraft: Bool

    static func empty(kind: ConnectionProfile.DatabaseKind = .postgreSQL) -> ConnectionDraft {
        ConnectionDraft(
            name: "",
            kind: kind,
            host: "",
            port: ConnectionDraft.defaultPort(for: kind),
            username: "",
            password: "",
            passwordKeychainIdentifier: nil,
            useSSHTunnel: false,
            sshConfigAlias: "",
            sshUsername: "",
            sshAuthenticationMethod: .keyFile,
            sshKeyFilePath: "",
            sshPassword: "",
            sshPasswordKeychainIdentifier: nil,
            sshKeychainIdentityLabel: nil,
            sshKeychainIdentityReference: nil,
            isDraft: true
        )
    }

    init(
        name: String,
        kind: ConnectionProfile.DatabaseKind,
        host: String,
        port: Int,
        username: String,
        password: String,
        passwordKeychainIdentifier: String?,
        useSSHTunnel: Bool,
        sshConfigAlias: String,
        sshUsername: String,
        sshAuthenticationMethod: ConnectionProfile.SSHConfiguration.AuthenticationMethod,
        sshKeyFilePath: String,
        sshPassword: String,
        sshPasswordKeychainIdentifier: String?,
        sshKeychainIdentityLabel: String?,
        sshKeychainIdentityReference: Data?,
        isDraft: Bool
    ) {
        self.name = name
        self.kind = kind
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.passwordKeychainIdentifier = passwordKeychainIdentifier
        self.useSSHTunnel = useSSHTunnel
        self.sshConfigAlias = sshConfigAlias
        self.sshUsername = sshUsername
        self.sshAuthenticationMethod = sshAuthenticationMethod
        self.sshKeyFilePath = sshKeyFilePath
        self.sshPassword = sshPassword
        self.sshPasswordKeychainIdentifier = sshPasswordKeychainIdentifier
        self.sshKeychainIdentityLabel = sshKeychainIdentityLabel
        self.sshKeychainIdentityReference = sshKeychainIdentityReference
        self.isDraft = isDraft
    }

    init(connection: ConnectionProfile) {
        self.init(
            name: connection.name,
            kind: connection.kind,
            host: connection.host,
            port: connection.port,
            username: connection.username,
            password: "",
            passwordKeychainIdentifier: connection.passwordKeychainIdentifier,
            useSSHTunnel: connection.sshConfiguration.isEnabled,
            sshConfigAlias: connection.sshConfiguration.configAlias,
            sshUsername: connection.sshConfiguration.username,
            sshAuthenticationMethod: connection.sshConfiguration.authenticationMethod,
            sshKeyFilePath: connection.sshConfiguration.keyFilePath,
            sshPassword: "",
            sshPasswordKeychainIdentifier: connection.sshConfiguration.passwordKeychainIdentifier,
            sshKeychainIdentityLabel: connection.sshConfiguration.keychainIdentityLabel,
            sshKeychainIdentityReference: connection.sshConfiguration.keychainIdentityReference,
            isDraft: connection.isDraft
        )
    }

    private static func isBlank(_ string: String) -> Bool {
        string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    enum MissingField: Hashable {
        case name
        case host
        case port
        case username
        case sshAlias
        case sshUsername
        case sshCredential
    }

    var missingRequiredFields: [MissingField] {
        var missing: [MissingField] = []
        let requiresNetworking = kind != .sqlite

        if Self.isBlank(name) {
            missing.append(.name)
        }

        if Self.isBlank(host) {
            missing.append(.host)
        }

        if requiresNetworking && port <= 0 {
            missing.append(.port)
        }

        if requiresNetworking && Self.isBlank(username) {
            missing.append(.username)
        }

        if useSSHTunnel {
            if Self.isBlank(sshConfigAlias) {
                missing.append(.sshAlias)
            }

            switch sshAuthenticationMethod {
            case .keyFile:
                if Self.isBlank(sshUsername) {
                    missing.append(.sshUsername)
                }
                let hasKeychainIdentity = sshKeychainIdentityReference != nil
                let hasKeyFile = !Self.isBlank(sshKeyFilePath)
                if !hasKeychainIdentity && !hasKeyFile {
                    missing.append(.sshCredential)
                }
            case .usernameAndPassword:
                if Self.isBlank(sshUsername) {
                    missing.append(.sshUsername)
                }
                let hasPasswordReference = sshPasswordKeychainIdentifier != nil
                let hasInlinePassword = !Self.isBlank(sshPassword)
                if !hasPasswordReference && !hasInlinePassword {
                    missing.append(.sshCredential)
                }
            case .sshAgent:
                if Self.isBlank(sshUsername) {
                    missing.append(.sshUsername)
                }
            }
        }

        return missing
    }

    var nextMissingField: MissingField? {
        missingRequiredFields.first
    }

    var isValid: Bool {
        missingRequiredFields.isEmpty
    }

    var hasAnyContent: Bool {
        if !Self.isBlank(name) || !Self.isBlank(host) || !Self.isBlank(username) {
            return true
        }
        if kind != .postgreSQL {
            return true
        }
        if port != ConnectionDraft.defaultPort(for: kind) {
            return true
        }
        if !Self.isBlank(password) || passwordKeychainIdentifier != nil {
            return true
        }
        if useSSHTunnel {
            return true
        }
        if !Self.isBlank(sshConfigAlias) || !Self.isBlank(sshUsername) || !Self.isBlank(sshKeyFilePath) {
            return true
        }
        if sshKeychainIdentityReference != nil || !Self.isBlank(sshPassword) || sshPasswordKeychainIdentifier != nil {
            return true
        }
        return false
    }

    func makeProfile(
        id: ConnectionProfile.ID = ConnectionProfile.ID(),
        isDraft: Bool
    ) -> ConnectionProfile {
        ConnectionProfile(
            id: id,
            name: name,
            kind: kind,
            host: host,
            port: port,
            username: username,
            sshConfiguration: ConnectionProfile.SSHConfiguration(
                isEnabled: useSSHTunnel,
                configAlias: sshConfigAlias,
                username: sshUsername,
                authenticationMethod: sshAuthenticationMethod,
                keychainIdentityLabel: sshKeychainIdentityLabel,
                keychainIdentityReference: sshKeychainIdentityReference,
                keyFilePath: sshKeyFilePath,
                passwordKeychainIdentifier: sshPasswordKeychainIdentifier
            ),
            passwordKeychainIdentifier: passwordKeychainIdentifier,
            isDraft: isDraft
        )
    }

    mutating func normalizeAfterKindChange(previousKind: ConnectionProfile.DatabaseKind) {
        let previousDefault = ConnectionDraft.defaultPort(for: previousKind)
        if port == previousDefault || port == 0 {
            port = ConnectionDraft.defaultPort(for: kind)
        }
    }

    private static func defaultPort(for kind: ConnectionProfile.DatabaseKind) -> Int {
        ConnectionProfile.defaultPort(for: kind)
    }
}
