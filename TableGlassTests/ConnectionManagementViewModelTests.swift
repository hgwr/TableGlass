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
            aliases: ["bastion"]
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
        let identity = SSHKeychainIdentityReference(
            label: "bastion-key",
            persistentReference: Data([0xAA, 0xBB])
        )
        let viewModel = makeViewModel(
            store: store,
            aliases: ["bastion"],
            identities: [identity]
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

        await viewModel.reloadSSHAliases()
        await viewModel.reloadSSHIdentities()
        viewModel.selectSSHIdentity(identity)

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
        #expect(savedProfile.sshConfiguration.keychainIdentityLabel == identity.label)
        #expect(savedProfile.sshConfiguration.keychainIdentityReference == identity.persistentReference)
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

    @Test func enablingSSHTunnelLoadsKeychainIdentities() async throws {
        let store = MockConnectionStore()
        let identity = SSHKeychainIdentityReference(
            label: "bastion-key",
            persistentReference: Data([0x01, 0x02, 0x03])
        )
        let viewModel = makeViewModel(
            store: store,
            aliases: ["bastion"],
            identities: [identity]
        )

        viewModel.startCreatingConnection(kind: .postgreSQL)
        viewModel.updateDraft {
            $0.name = "Keychain Test"
            $0.host = "db.internal"
            $0.port = 5432
            $0.username = "dbuser"
        }

        await viewModel.reloadSSHAliases()
        await viewModel.reloadSSHIdentities()
        viewModel.updateDraft {
            $0.useSSHTunnel = true
            $0.sshConfigAlias = "bastion"
            $0.sshUsername = "sshuser"
        }

        #expect(viewModel.sshAliases.contains("bastion"))
        #expect(viewModel.availableSSHIdentities == [identity])

        viewModel.selectSSHIdentity(identity)

        #expect(viewModel.draft.sshKeychainIdentityReference == identity.persistentReference)
        #expect(viewModel.draft.sshKeychainIdentityLabel == identity.label)
    }

    @Test func sshTunnelDraftRequiresIdentity() async throws {
        let store = MockConnectionStore()
        let identity = SSHKeychainIdentityReference(
            label: "bastion-key",
            persistentReference: Data([0xAA, 0xCC])
        )
        let viewModel = makeViewModel(
            store: store,
            aliases: ["bastion"],
            identities: [identity]
        )

        viewModel.startCreatingConnection(kind: .postgreSQL)
        viewModel.updateDraft {
            $0.name = "Validation"
            $0.host = "db.internal"
            $0.port = 5432
            $0.username = "dbuser"
            $0.useSSHTunnel = true
            $0.sshConfigAlias = "bastion"
            $0.sshUsername = "sshuser"
        }

        await viewModel.reloadSSHAliases()
        await viewModel.reloadSSHIdentities()

        #expect(!viewModel.draft.isValid)

        viewModel.selectSSHIdentity(identity)

        #expect(viewModel.draft.isValid)
    }

    private func makeViewModel(
        store: MockConnectionStore,
        aliases: [String] = [],
        identities: [SSHKeychainIdentityReference] = []
    ) -> ConnectionManagementViewModel {
        ConnectionManagementViewModel(
            connectionStore: store,
            sshAliasProvider: MockSSHAliasProvider(aliases: aliases),
            sshKeychainService: MockSSHKeychainService(identities: identities)
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
    var identities: [SSHKeychainIdentityReference]

    func allIdentities() async throws -> [SSHKeychainIdentityReference] {
        identities
    }

    func identity(forLabel label: String) async throws -> SSHKeychainIdentityReference? {
        identities.first { $0.label == label }
    }
}
