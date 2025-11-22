import Combine
import Foundation
import TableGlassKit

@MainActor
final class DatabaseBrowserViewModel: ObservableObject {
    @Published private(set) var sessions: [DatabaseBrowserSessionViewModel]
    @Published var selectedSessionID: DatabaseBrowserSessionViewModel.ID?

    private let metadataProviderFactory: @Sendable () -> any DatabaseMetadataProvider

    init(
        sessions: [DatabaseBrowserSessionViewModel] = [],
        metadataProviderFactory: @escaping @Sendable () -> any DatabaseMetadataProvider = {
            PreviewDatabaseMetadataProvider(schema: .previewBrowserSchema)
        }
    ) {
        self.metadataProviderFactory = metadataProviderFactory
        if sessions.isEmpty {
            self.sessions = DatabaseBrowserSessionViewModel.previewSessions(
                metadataProviderFactory: metadataProviderFactory)
        } else {
            self.sessions = sessions
        }
        selectedSessionID = self.sessions.first?.id
    }

    func appendSession(named name: String) {
        let newSession = DatabaseBrowserSessionViewModel(
            databaseName: name,
            status: .connecting,
            isReadOnly: true,
            metadataProvider: metadataProviderFactory()
        )
        sessions.append(newSession)
        selectedSessionID = newSession.id
    }

    func setReadOnly(_ isReadOnly: Bool, for sessionID: DatabaseBrowserSessionViewModel.ID) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        session.isReadOnly = isReadOnly
    }

    func markStatus(_ status: DatabaseBrowserSessionStatus, for sessionID: DatabaseBrowserSessionViewModel.ID) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        session.status = status
    }

    func removeSession(_ sessionID: DatabaseBrowserSessionViewModel.ID) {
        sessions.removeAll { $0.id == sessionID }
        if selectedSessionID == sessionID {
            selectedSessionID = sessions.first?.id
        }
    }

    var windowTitle: String {
        "Database Browser"
    }
}
