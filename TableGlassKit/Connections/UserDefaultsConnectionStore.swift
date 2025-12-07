import Foundation
import OSLog

public actor UserDefaultsConnectionStore: ConnectionStore {
    private let defaults: UserDefaults
    private let storageKey: String
    private let logger = Logger(subsystem: "com.tableglass", category: "ConnectionStore")

    public init(defaults: UserDefaults = .standard, storageKey: String = "com.tableglass.connections") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    public func listConnections() async throws -> [ConnectionProfile] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }
        do {
            let connections = try JSONDecoder().decode([ConnectionProfile].self, from: data)
            do {
                let normalized = try JSONEncoder().encode(connections)
                if normalized != data {
                    defaults.set(normalized, forKey: storageKey)
                    logger.notice("Normalized connection payload for storageKey \(self.storageKey, privacy: .public).")
                }
            } catch {
                logger.error("Failed to normalize migrated connections: \(error.localizedDescription, privacy: .public)")
            }
            return connections
        } catch {
            logger.error("Failed to decode saved connections: \(error.localizedDescription, privacy: .public)")
            defaults.removeObject(forKey: storageKey)
            return []
        }
    }

    public func saveConnection(_ connection: ConnectionProfile) async throws {
        var connections = try await listConnections()
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        do {
            let data = try JSONEncoder().encode(connections)
            defaults.set(data, forKey: storageKey)
            logger.debug("Saved \(connections.count, privacy: .public) connection(s) to UserDefaults.")
        } catch {
            logger.error("Failed to encode connections: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    public func deleteConnection(id: ConnectionProfile.ID) async throws {
        var connections = try await listConnections()
        connections.removeAll { $0.id == id }
        do {
            let data = try JSONEncoder().encode(connections)
            defaults.set(data, forKey: storageKey)
            logger.debug("Deleted connection \(id.uuidString, privacy: .public). Remaining: \(connections.count, privacy: .public)")
        } catch {
            logger.error("Failed to encode connections after delete: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
