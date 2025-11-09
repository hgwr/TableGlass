import Foundation
import Testing
@testable import TableGlass
import TableGlassKit

@MainActor
struct ConnectionManagementViewModelTests {

    @Test func loadConnectionsSetsInitialSelection() async throws {
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
        let viewModel = ConnectionManagementViewModel(connectionStore: store)

        await viewModel.loadConnections()

        #expect(viewModel.connections == profiles)
        #expect(viewModel.selection == profiles.first?.id)
        #expect(!viewModel.isNewConnection)
        #expect(viewModel.lastError == nil)
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
        let viewModel = ConnectionManagementViewModel(connectionStore: store)
        await viewModel.loadConnections()

        viewModel.startCreatingConnection(kind: .sqlite)

        #expect(viewModel.selection == nil)
        #expect(viewModel.isNewConnection)
        #expect(viewModel.draft.kind == .sqlite)
        #expect(viewModel.draft.port == 0)
    }

    @Test func saveNewConnectionPersistsThroughStore() async throws {
        let store = MockConnectionStore(connections: [])
        let viewModel = ConnectionManagementViewModel(connectionStore: store)

        viewModel.startCreatingConnection(kind: .mySQL)
        viewModel.updateDraft {
            $0.name = "New Connection"
            $0.host = "db.internal"
            $0.port = 3306
            $0.username = "app"
        }

        await viewModel.saveCurrentConnection()

        let saved = await store.savedConnections()
        #expect(saved.count == 1)
        #expect(saved.first?.name == "New Connection")
        #expect(viewModel.connections.count == 1)
        #expect(viewModel.selection == saved.first?.id)
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
        let viewModel = ConnectionManagementViewModel(connectionStore: store)
        await viewModel.loadConnections()
        viewModel.applySelection(id: connectionA.id)

        await viewModel.deleteSelectedConnection()

        let deleted = await store.deletedIDs()
        #expect(deleted == [connectionA.id])
        #expect(viewModel.connections == [connectionB])
        #expect(viewModel.selection == connectionB.id)
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
