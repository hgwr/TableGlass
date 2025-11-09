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

    private let connectionStore: any ConnectionStore

    init(connectionStore: some ConnectionStore) {
        self.connectionStore = connectionStore
    }

    func loadConnections() async {
        do {
            connections = try await connectionStore.listConnections()
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

    func applySelection(id: ConnectionProfile.ID) {
        guard let connection = connections.first(where: { $0.id == id }) else {
            return
        }
        selection = connection.id
        draft = ConnectionDraft(connection: connection)
        isNewConnection = false
        lastError = nil
    }

    func startCreatingConnection(kind: ConnectionProfile.DatabaseKind = .postgreSQL) {
        selection = nil
        draft = .empty(kind: kind)
        isNewConnection = true
        lastError = nil
    }

    func updateDraft(_ transform: (inout ConnectionDraft) -> Void) {
        let previousKind = draft.kind
        transform(&draft)
        if draft.kind != previousKind {
            draft.normalizeAfterKindChange(previousKind: previousKind)
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
    var useSSHTunnel: Bool
    var sshConfigAlias: String
    var sshUsername: String

    static func empty(kind: ConnectionProfile.DatabaseKind = .postgreSQL) -> ConnectionDraft {
        ConnectionDraft(
            name: "",
            kind: kind,
            host: "",
            port: ConnectionDraft.defaultPort(for: kind),
            username: "",
            password: "",
            useSSHTunnel: false,
            sshConfigAlias: "",
            sshUsername: ""
        )
    }

    init(
        name: String,
        kind: ConnectionProfile.DatabaseKind,
        host: String,
        port: Int,
        username: String,
        password: String,
        useSSHTunnel: Bool,
        sshConfigAlias: String,
        sshUsername: String
    ) {
        self.name = name
        self.kind = kind
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.useSSHTunnel = useSSHTunnel
        self.sshConfigAlias = sshConfigAlias
        self.sshUsername = sshUsername
    }

    init(connection: ConnectionProfile) {
        self.init(
            name: connection.name,
            kind: connection.kind,
            host: connection.host,
            port: connection.port,
            username: connection.username,
            password: "",
            useSSHTunnel: false,
            sshConfigAlias: "",
            sshUsername: ""
        )
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            port > 0 &&
            !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func makeProfile(id: ConnectionProfile.ID = ConnectionProfile.ID()) -> ConnectionProfile {
        ConnectionProfile(
            id: id,
            name: name,
            kind: kind,
            host: host,
            port: port,
            username: username
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
