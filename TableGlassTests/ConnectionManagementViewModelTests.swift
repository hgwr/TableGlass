import Foundation
import TableGlassKit
import Testing

@testable import TableGlass

@MainActor
struct ConnectionManagementViewModelTests {

    @Test func loadConnectionsSetsInitialSelection() async throws {
        let profiles = [
            ConnectionProfile(
                name: "Fixture",
                kind: .postgreSQL,
                host: "localhost",
                port: 5432,
                username: "postgres",
                sshConfiguration: .init(
                    isEnabled: true, configAlias: "bastion", username: "sshuser"),
                passwordKeychainIdentifier: "fixture.keychain"
            )
        ]
        let store = MockConnectionStore(connections: profiles)
        let viewModel = makeViewModel(
            store: store,
            aliases: ["bastion"],
            keychainResult: .none
        )

        await viewModel.loadConnections()

        #expect(viewModel.connections == profiles)
        #expect(viewModel.selection == profiles.first?.id)
        #expect(!viewModel.isNewConnection)
        #expect(viewModel.lastError == nil)
        #expect(viewModel.draft.useSSHTunnel)
        #expect(viewModel.draft.sshConfigAlias == "bastion")
        #expect(viewModel.draft.sshUsername == "sshuser")
        #expect(viewModel.draft.passwordKeychainIdentifier == "fixture.keychain")
    }

    @Test func startCreatingConnectionResetsDraft() async throws {
        let profiles = [
            ConnectionProfile(
                name: "Fixture",
                kind: .postgreSQL,
                host: "localhost",
                port: 5432,
                username: "postgres"
            )
        ]
        let store = MockConnectionStore(connections: profiles)
        let viewModel = makeViewModel(store: store)
        await viewModel.loadConnections()

        viewModel.startCreatingConnection(kind: .sqlite)

        #expect(viewModel.selection == nil)
        #expect(viewModel.isNewConnection)
        #expect(viewModel.draft.kind == .sqlite)
        #expect(viewModel.draft.port == 0)
    }

    @Test func clearingSelectionExitsEditingMode() async throws {
        let connection = ConnectionProfile(
            name: "Fixture",
            kind: .postgreSQL,
            host: "localhost",
            port: 5432,
            username: "postgres"
        )
        let store = MockConnectionStore(connections: [connection])
        let viewModel = makeViewModel(store: store)
        await viewModel.loadConnections()

        viewModel.clearSelection()

        #expect(viewModel.selection == nil)
        #expect(!viewModel.isNewConnection)
    }

    @Test func sqliteDraftAllowsZeroPort() async throws {
        let store = MockConnectionStore(connections: [])
        let viewModel = makeViewModel(store: store)

        viewModel.startCreatingConnection(kind: .sqlite)
        viewModel.updateDraft {
            $0.name = "Local SQLite"
            $0.host = "/tmp/app.db"
        }

        #expect(viewModel.draft.isValid)

        await viewModel.saveCurrentConnection()

        let saved = await store.savedConnections()
        #expect(saved.count == 1)
        #expect(saved.first?.port == 0)
        #expect(saved.first?.username.isEmpty == true)
    }

    @Test func saveNewConnectionPersistsThroughStore() async throws {
        let store = MockConnectionStore(connections: [])
        let viewModel = makeViewModel(
            store: store,
            aliases: ["bastion"],
            keychainResult: .none
        )

        viewModel.startCreatingConnection(kind: .mySQL)
        viewModel.updateDraft {
            $0.name = "New Connection"
            $0.host = "db.internal"
            $0.port = 3306
            $0.username = "app"
            $0.password = "secret"
        }
        viewModel.updateDraft {
            $0.passwordKeychainIdentifier = "tableglass.connection.new"
            $0.useSSHTunnel = true
            $0.sshConfigAlias = "bastion"
            $0.sshUsername = "sshapp"
        }

        await viewModel.saveCurrentConnection()

        let saved = await store.savedConnections()
        #expect(saved.count == 1)
        guard let savedProfile = saved.first else {
            #expect(Bool(false), "Expected saved connection to be present")
            return
        }
        #expect(savedProfile.name == "New Connection")
        #expect(savedProfile.sshConfiguration.isEnabled)
        #expect(savedProfile.sshConfiguration.configAlias == "bastion")
        #expect(savedProfile.sshConfiguration.username == "sshapp")
        #expect(savedProfile.passwordKeychainIdentifier == "tableglass.connection.new")
        #expect(viewModel.connections.count == 1)
        #expect(viewModel.selection == savedProfile.id)
        #expect(!viewModel.isNewConnection)
    }

    @Test func deleteConnectionRemovesFromList() async throws {
        let connectionA = ConnectionProfile(
            name: "Primary",
            kind: .postgreSQL,
            host: "primary",
            port: 5432,
            username: "postgres"
        )
        let connectionB = ConnectionProfile(
            name: "Replica",
            kind: .postgreSQL,
            host: "replica",
            port: 5432,
            username: "postgres"
        )
        let store = MockConnectionStore(connections: [connectionA, connectionB])
        let viewModel = makeViewModel(store: store)
        await viewModel.loadConnections()
        viewModel.applySelection(id: connectionA.id)

        await viewModel.deleteSelectedConnection()

        let deleted = await store.deletedIDs()
        #expect(deleted == [connectionA.id])
        #expect(viewModel.connections == [connectionB])
        #expect(viewModel.selection == connectionB.id)
    }

    @Test func enablingSSHTunnelResolvesKeychainIdentity() async throws {
        let store = MockConnectionStore()
        let identityReference = Data([0x01, 0x02, 0x03])
        let viewModel = makeViewModel(
            store: store,
            aliases: ["bastion"],
            keychainResult: .found(label: "bastion-key", reference: identityReference)
        )

        viewModel.startCreatingConnection(kind: .postgreSQL)
        viewModel.updateDraft {
            $0.name = "Keychain Test"
            $0.host = "db.internal"
            $0.port = 5432
            $0.username = "dbuser"
        }

        await viewModel.reloadSSHAliases()
        viewModel.updateDraft {
            $0.useSSHTunnel = true
            $0.sshConfigAlias = "bastion"
            $0.sshUsername = "sshuser"
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.sshAliases.contains("bastion"))
        #expect(viewModel.sshIdentityState == .resolved(label: "bastion-key"))
        #expect(viewModel.draft.sshKeychainIdentityReference == identityReference)
    }

    @Test func missingKeychainIdentityUpdatesState() async throws {
        let store = MockConnectionStore()
        let viewModel = makeViewModel(
            store: store,
            aliases: ["bastion"],
            keychainResult: .none
        )

        viewModel.startCreatingConnection(kind: .postgreSQL)
        viewModel.updateDraft {
            $0.name = "Missing Identity"
            $0.host = "db.internal"
            $0.port = 5432
            $0.username = "dbuser"
        }

        await viewModel.reloadSSHAliases()
        viewModel.updateDraft {
            $0.useSSHTunnel = true
            $0.sshConfigAlias = "bastion"
            $0.sshUsername = "sshuser"
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.sshIdentityState == .missing)
        #expect(viewModel.draft.sshKeychainIdentityReference == nil)
    }

    private func makeViewModel(
        store: MockConnectionStore,
        aliases: [String] = [],
        keychainResult: MockSSHKeychainService.Result = .none
    ) -> ConnectionManagementViewModel {
        ConnectionManagementViewModel(
            connectionStore: store,
            sshAliasProvider: MockSSHAliasProvider(aliases: aliases),
            sshKeychainService: MockSSHKeychainService(result: keychainResult)
        )
    }
}

actor MockConnectionStore: ConnectionStore {
    private var storedConnections: [ConnectionProfile]
    private var saved: [ConnectionProfile] = []
    private var deleted: [ConnectionProfile.ID] = []

    init(connections: [ConnectionProfile] = []) {
        storedConnections = connections
    }

    func listConnections() async throws -> [ConnectionProfile] {
        storedConnections
    }

    func saveConnection(_ connection: ConnectionProfile) async throws {
        saved.append(connection)
        if let index = storedConnections.firstIndex(where: { $0.id == connection.id }) {
            storedConnections[index] = connection
        } else {
            storedConnections.append(connection)
        }
    }

    func deleteConnection(id: ConnectionProfile.ID) async throws {
        deleted.append(id)
        storedConnections.removeAll { $0.id == id }
    }

    func savedConnections() -> [ConnectionProfile] {
        saved
    }

    func deletedIDs() -> [ConnectionProfile.ID] {
        deleted
    }
}

struct MockSSHAliasProvider: SSHConfigAliasProvider, Sendable {
    let aliases: [String]

    func availableAliases() async throws -> [String] {
        aliases
    }
}

struct MockSSHKeychainService: SSHKeychainService, Sendable {
    enum Result: Sendable {
        case none
        case found(label: String, reference: Data)
        case failure(MockSSHKeychainServiceError)
    }

    var result: Result

    func identity(forLabel label: String) async throws -> SSHKeychainIdentityReference? {
        switch result {
        case .none:
            return nil
        case .found(let label, let reference):
            return SSHKeychainIdentityReference(label: label, persistentReference: reference)
        case .failure(let error):
            throw error
        }
    }
}

enum MockSSHKeychainServiceError: Error, Sendable {
    case lookup
}
