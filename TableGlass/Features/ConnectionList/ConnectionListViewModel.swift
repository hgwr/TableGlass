import Core
import Foundation

@MainActor
final class ConnectionListViewModel: ObservableObject {
    @Published private(set) var connections: [ConnectionProfile] = []

    private let connectionStore: any ConnectionStore

    init(connectionStore: some ConnectionStore) {
        self.connectionStore = connectionStore
    }

    func loadConnections() async {
        do {
            let profiles = try await connectionStore.listConnections()
            connections = profiles
        } catch {
            connections = []
        }
    }
}
