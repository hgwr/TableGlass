import Combine
import Foundation
import TableGlassKit

@MainActor
final class ConnectionManagementViewModel: ObservableObject {
    @Published private(set) var connections: [ConnectionProfile] = []
    @Published var selection: ConnectionProfile.ID?
    @Published var draft: ConnectionDraft = .empty()
    @Published private(set) var isNewConnection: Bool = false
    @Published private(set) var isSaving: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var sshAliases: [String] = []
    @Published private(set) var isLoadingSSHAliases: Bool = false
    @Published private(set) var sshAliasError: String?
    @Published private(set) var availableSSHIdentities: [SSHKeychainIdentityReference] = []
    @Published private(set) var isLoadingSSHIdentities: Bool = false
    @Published private(set) var sshIdentityError: String?

    private let connectionStore: any ConnectionStore
    private let sshAliasProvider: any SSHConfigAliasProvider
    private let sshKeychainService: any SSHKeychainService
    private var hasLoadedSSHAliases = false
    private var hasLoadedSSHIdentities = false

    init(
        connectionStore: some ConnectionStore,
        sshAliasProvider: some SSHConfigAliasProvider = DefaultSSHConfigAliasProvider(),
        sshKeychainService: some SSHKeychainService = DefaultSSHKeychainService()
    ) {
        self.connectionStore = connectionStore
        self.sshAliasProvider = sshAliasProvider
        self.sshKeychainService = sshKeychainService
    }

    var sshAliasOptions: [String] {
        var options = sshAliases
        let current = draft.sshConfigAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, !options.contains(current) {
            options.insert(current, at: 0)
        }
        return options
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
            lastError = error.localizedDescription
            connections = []
            startCreatingConnection()
        }
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
        sshIdentityError = nil
    }

    private func handleSSHTunnelMutation(
        previousUseSSH: Bool,
        previousAlias: String,
        newUseSSH: Bool,
        newAlias: String
    ) {
        if !newUseSSH {
            resetDraftSSHIdentity()
            return
        }

        if !previousUseSSH {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.ensureSSHAliasesLoaded()
                await self.ensureSSHIdentitiesLoaded()
            }
        } else if previousAlias != newAlias {
            includeAliasInList(newAlias)
            synchronizeDraftIdentity()
        } else {
            synchronizeDraftIdentity()
        }
    }

    func applySelection(id: ConnectionProfile.ID) {
        guard let connection = connections.first(where: { $0.id == id }) else {
            return
        }
        selection = connection.id
        draft = ConnectionDraft(connection: connection)
        if !draft.sshConfigAlias.isEmpty {
            includeAliasInList(draft.sshConfigAlias)
        }
        if draft.useSSHTunnel {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.ensureSSHIdentitiesLoaded()
            }
            synchronizeDraftIdentity()
        } else {
            resetDraftSSHIdentity()
        }
        isNewConnection = false
        lastError = nil
    }

    func startCreatingConnection(kind: ConnectionProfile.DatabaseKind = .postgreSQL) {
        selection = nil
        draft = .empty(kind: kind)
        isNewConnection = true
        lastError = nil
        resetDraftSSHIdentity()
    }

    func clearSelection() {
        selection = nil
        isNewConnection = false
        resetDraftSSHIdentity()
    }

    func updateDraft(_ transform: (inout ConnectionDraft) -> Void) {
        let previousKind = draft.kind
        let previousPassword = draft.password
        let previousUseSSH = draft.useSSHTunnel
        let previousAlias = draft.sshConfigAlias
        transform(&draft)
        if draft.kind != previousKind {
            draft.normalizeAfterKindChange(previousKind: previousKind)
        }
        if draft.password != previousPassword, !draft.password.isEmpty {
            draft.passwordKeychainIdentifier = nil
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
    }

    func selectSSHIdentity(_ identity: SSHKeychainIdentityReference?) {
        updateDraft { draft in
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

    func saveCurrentConnection() async {
        guard draft.isValid else {
            lastError = "Please complete the required fields."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            if isNewConnection {
                let profile = draft.makeProfile()
                try await connectionStore.saveConnection(profile)
                connections.append(profile)
                applySelection(id: profile.id)
            } else if let selection {
                let updated = draft.makeProfile(id: selection)
                try await connectionStore.saveConnection(updated)
                if let index = connections.firstIndex(where: { $0.id == selection }) {
                    connections[index] = updated
                }
                applySelection(id: updated.id)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteSelectedConnection() async {
        guard let selection else {
            return
        }

        do {
            try await connectionStore.deleteConnection(id: selection)
            connections.removeAll { $0.id == selection }
            if let next = connections.first {
                applySelection(id: next.id)
            } else {
                startCreatingConnection(kind: draft.kind)
            }
        } catch {
            lastError = error.localizedDescription
        }
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
    var sshKeychainIdentityLabel: String?
    var sshKeychainIdentityReference: Data?

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
            sshKeychainIdentityLabel: nil,
            sshKeychainIdentityReference: nil
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
        sshKeychainIdentityLabel: String?,
        sshKeychainIdentityReference: Data?
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
        self.sshKeychainIdentityLabel = sshKeychainIdentityLabel
        self.sshKeychainIdentityReference = sshKeychainIdentityReference
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
            sshKeychainIdentityLabel: connection.sshConfiguration.keychainIdentityLabel,
            sshKeychainIdentityReference: connection.sshConfiguration.keychainIdentityReference
        )
    }

    private static func isBlank(_ string: String) -> Bool {
        string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isValid: Bool {
        let requiresNetworking = kind != .sqlite

        if useSSHTunnel {
            if Self.isBlank(sshConfigAlias) || Self.isBlank(sshUsername)
                || sshKeychainIdentityReference == nil
            {
                return false
            }
        }

        return !Self.isBlank(name) && !Self.isBlank(host) && (!requiresNetworking || port > 0)
            && (kind == .sqlite || !Self.isBlank(username))
    }

    func makeProfile(id: ConnectionProfile.ID = ConnectionProfile.ID()) -> ConnectionProfile {
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
                keychainIdentityLabel: sshKeychainIdentityLabel,
                keychainIdentityReference: sshKeychainIdentityReference
            ),
            passwordKeychainIdentifier: passwordKeychainIdentifier
        )
    }

    mutating func normalizeAfterKindChange(previousKind: ConnectionProfile.DatabaseKind) {
        let previousDefault = ConnectionDraft.defaultPort(for: previousKind)
        if port == previousDefault || port == 0 {
            port = ConnectionDraft.defaultPort(for: kind)
        }
    }

    private static func defaultPort(for kind: ConnectionProfile.DatabaseKind) -> Int {
        switch kind {
        case .postgreSQL:
            return 5432
        case .mySQL:
            return 3306
        case .sqlite:
            return 0
        }
    }
}
