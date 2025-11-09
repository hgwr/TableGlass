//
//  TableGlassTests.swift
//  TableGlassTests
//
//  Created by Shigeru Hagiwara on 2025/11/09.
//

import Testing
@testable import TableGlass
import TableGlassKit

struct TableGlassTests {

    @Test func connectionListViewModelLoadsConnections() async throws {
        let sample = ConnectionProfile(
            name: "Fixture",
            kind: .postgreSQL,
            host: "localhost",
            port: 5432,
            username: "postgres"
        )
        let store = StubConnectionStore(connections: [sample])
        let viewModel = await MainActor.run {
            ConnectionListViewModel(connectionStore: store)
        }

        await viewModel.loadConnections()

        let loaded = await MainActor.run { viewModel.connections }
        #expect(loaded == [sample])
    }

}

private struct StubConnectionStore: ConnectionStore {
    var connections: [ConnectionProfile]

    func listConnections() async throws -> [ConnectionProfile] {
        connections
    }

    /// No-op stub for testing: does not persist the connection.
    func saveConnection(_ connection: ConnectionProfile) async throws {
        _ = connection
    }

    /// No-op stub for testing: does not delete any connection.
    func deleteConnection(id: ConnectionProfile.ID) async throws {
        _ = id
    }
}
