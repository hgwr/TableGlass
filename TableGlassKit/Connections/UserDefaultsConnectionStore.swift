import Foundation

public actor UserDefaultsConnectionStore: ConnectionStore {
    private let defaults: UserDefaults
    private let storageKey: String

    public init(defaults: UserDefaults = .standard, storageKey: String = "com.tableglass.connections") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    public func listConnections() async throws -> [ConnectionProfile] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }
        return try JSONDecoder().decode([ConnectionProfile].self, from: data)
    }

    public func saveConnection(_ connection: ConnectionProfile) async throws {
        var connections = try await listConnections()
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        let data = try JSONEncoder().encode(connections)
        defaults.set(data, forKey: storageKey)
    }

    public func deleteConnection(id: ConnectionProfile.ID) async throws {
        var connections = try await listConnections()
        connections.removeAll { $0.id == id }
        let data = try JSONEncoder().encode(connections)
        defaults.set(data, forKey: storageKey)
    }
}
