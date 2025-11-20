import Combine
import Foundation

@MainActor
final class DatabaseBrowserViewModel: ObservableObject {
    @Published private(set) var sessions: [DatabaseBrowserSessionViewState]
    @Published var selectedSessionID: DatabaseBrowserSessionViewState.ID?

    init(sessions: [DatabaseBrowserSessionViewState] = DatabaseBrowserSessionViewState.previewSessions) {
        if sessions.isEmpty {
            self.sessions = DatabaseBrowserSessionViewState.previewSessions
        } else {
            self.sessions = sessions
        }
        selectedSessionID = self.sessions.first?.id
    }

    func appendSession(named name: String) {
        let newSession = DatabaseBrowserSessionViewState(
            databaseName: name,
            status: .connecting,
            isReadOnly: true
        )
        sessions.append(newSession)
        selectedSessionID = newSession.id
    }

    func setReadOnly(_ isReadOnly: Bool, for sessionID: DatabaseBrowserSessionViewState.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].isReadOnly = isReadOnly
    }

    func markStatus(_ status: DatabaseBrowserSessionStatus, for sessionID: DatabaseBrowserSessionViewState.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].status = status
    }

    func removeSession(_ sessionID: DatabaseBrowserSessionViewState.ID) {
        sessions.removeAll { $0.id == sessionID }
        if selectedSessionID == sessionID {
            selectedSessionID = sessions.first?.id
        }
    }

    var windowTitle: String {
        "Database Browser"
    }
}
