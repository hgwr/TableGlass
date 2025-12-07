import Foundation
import TableGlassKit
import Testing

@testable import TableGlass

struct ConnectionStoreMigrationTests {

    @Test func migratesCommaSeparatedPorts() async throws {
        let suiteName = "ConnectionStoreMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyProfile: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Legacy Ports",
            "kind": "postgreSQL",
            "host": "legacy.internal",
            "port": "5432,6432",
            "username": "postgres",
            "sshConfiguration": [
                "isEnabled": false,
                "configAlias": "",
                "username": "",
                "authenticationMethod": "keyFile",
                "keyFilePath": ""
            ]
        ]
        let payload = try JSONSerialization.data(withJSONObject: [legacyProfile])
        defaults.set(payload, forKey: "connection.migration")

        let store = UserDefaultsConnectionStore(defaults: defaults, storageKey: "connection.migration")
        let connections = try await store.listConnections()

        #expect(connections.count == 1)
        guard let connection = connections.first else { return }
        #expect(connection.port == 5432)
        #expect(connection.host == "legacy.internal")

        if
            let stored = defaults.data(forKey: "connection.migration"),
            let decoded = try JSONSerialization.jsonObject(with: stored) as? [[String: Any]],
            let persistedPort = decoded.first?["port"] as? Int
        {
            #expect(persistedPort == 5432)
        } else {
            #expect(Bool(false), "Expected migrated connections to be re-encoded into UserDefaults")
        }
    }

    @Test func fallsBackToDefaultPortForInvalidEntries() async throws {
        let suiteName = "ConnectionStoreMigration.Invalid.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyProfile: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Broken Port",
            "kind": "mySQL",
            "host": "legacy.internal",
            "port": "abc",
            "username": "mysql",
            "sshConfiguration": [
                "isEnabled": false,
                "configAlias": "",
                "username": "",
                "authenticationMethod": "keyFile",
                "keyFilePath": ""
            ]
        ]
        let payload = try JSONSerialization.data(withJSONObject: [legacyProfile])
        defaults.set(payload, forKey: "connection.migration.invalid")

        let store = UserDefaultsConnectionStore(defaults: defaults, storageKey: "connection.migration.invalid")
        let connections = try await store.listConnections()

        #expect(connections.first?.port == ConnectionProfile.defaultPort(for: .mySQL))
    }
}
