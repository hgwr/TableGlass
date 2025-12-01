import Combine
import Foundation
import OSLog
import TableGlassKit

@MainActor
final class DatabaseBrowserViewModel: ObservableObject {
    @Published private(set) var sessions: [DatabaseBrowserSessionViewModel]
    @Published var selectedSessionID: DatabaseBrowserSessionViewModel.ID?

    private let metadataProviderFactory: @Sendable () -> any DatabaseMetadataProvider
    private let connectionStore: (any ConnectionStore)?
    private let connectionProvider: DatabaseConnectionProvider
    private let autoloadSavedConnections: Bool
    private let shouldUsePreviewSessions: Bool
    private var liveConnections: [DatabaseBrowserSessionViewModel.ID: any DatabaseConnection] = [:]
    private var sessionProfiles: [DatabaseBrowserSessionViewModel.ID: ConnectionProfile.ID] = [:]
    private var connectedProfileIDs: Set<ConnectionProfile.ID> = []
    private var connectingProfileIDs: Set<ConnectionProfile.ID> = []
    private var hasLoadedConnections = false
    private let logger = Logger(subsystem: "com.tableglass", category: "DatabaseBrowser")

    init(
        sessions: [DatabaseBrowserSessionViewModel] = [],
        metadataProviderFactory: @escaping @Sendable () -> any DatabaseMetadataProvider = {
            PreviewDatabaseMetadataProvider(schema: .previewBrowserSchema)
        },
        connectionStore: (any ConnectionStore)? = nil,
        connectionProvider: DatabaseConnectionProvider = .placeholderDrivers,
        autoloadSavedConnections: Bool = true
    ) {
        self.metadataProviderFactory = metadataProviderFactory
        self.connectionStore = connectionStore
        self.connectionProvider = connectionProvider
        self.autoloadSavedConnections = autoloadSavedConnections
        self.shouldUsePreviewSessions = ProcessInfo.processInfo.arguments.contains(
            UITestArguments.databaseBrowser.rawValue
        )

        let shouldBootstrapPreviewSessions = sessions.isEmpty && (connectionStore == nil || shouldUsePreviewSessions)
        if shouldBootstrapPreviewSessions {
            self.sessions = DatabaseBrowserSessionViewModel.previewSessions(metadataProviderFactory: metadataProviderFactory)
        } else {
            self.sessions = sessions
        }
        selectedSessionID = self.sessions.first?.id
    }

    deinit {
        let connections = Array(liveConnections.values)
        liveConnections.removeAll()
        sessionProfiles.removeAll()
        connectedProfileIDs.removeAll()

        Task.detached(priority: .background) {
            for connection in connections {
                await connection.disconnect()
            }
        }
    }

    func bootstrap() async {
        guard autoloadSavedConnections else { return }
        await loadSavedConnections()
    }

    func loadSavedConnections() async {
        guard !shouldUsePreviewSessions else { return }
        guard let connectionStore, !hasLoadedConnections else { return }
        hasLoadedConnections = true

        do {
            let profiles = try await connectionStore.listConnections()
            guard !profiles.isEmpty else { return }
            logger.info("Loading \(profiles.count, privacy: .public) saved connection(s) into Database Browser")

            if liveConnections.isEmpty {
                sessions = []
                selectedSessionID = nil
            }

            for profile in profiles where !profile.isDraft && !connectedProfileIDs.contains(profile.id) {
                do {
                    try await connect(profile: profile)
                } catch {
                    logger.error("DB connection failed for saved profile \(profile.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            logger.error("Failed to load saved connections: \(error.localizedDescription, privacy: .public)")
            hasLoadedConnections = false
            sessions = []
            selectedSessionID = nil
        }
    }

    @discardableResult
    func connect(profile: ConnectionProfile) async throws -> DatabaseBrowserSessionViewModel {
        if profile.isDraft {
            throw DatabaseError.connectionFailed("Draft connections cannot be opened.")
        }
        guard !connectingProfileIDs.contains(profile.id),
              !connectedProfileIDs.contains(profile.id) else {
            if let existing = sessions.first(where: { sessionProfiles[$0.id] == profile.id }) {
                return existing
            }
            return sessions.first ?? DatabaseBrowserSessionViewModel(
                databaseName: profile.name,
                status: .error,
                isReadOnly: true,
                metadataProvider: metadataProviderFactory()
            )
        }

        connectingProfileIDs.insert(profile.id)
        let connection = connectionProvider.makeConnection(for: profile)
        let tableService = DatabaseConnectionTableDataService(connection: connection)
        let session = DatabaseBrowserSessionViewModel(
            databaseName: profile.name,
            status: .connecting,
            isReadOnly: true,
            metadataProvider: connection,
            queryExecutor: connection,
            tableDataService: tableService
        )
        sessions.append(session)
        selectedSessionID = session.id
        liveConnections[session.id] = connection
        sessionProfiles[session.id] = profile.id

        do {
            logger.info("Attempting DB connection for profile \(profile.name, privacy: .public)")
            try await connection.connect()
            connectedProfileIDs.insert(profile.id)
            await MainActor.run {
                session.status = .readOnly
            }
            await session.refresh()
            connectingProfileIDs.remove(profile.id)
            return session
        } catch {
            connectingProfileIDs.remove(profile.id)
            await MainActor.run {
                session.status = .error
                session.setLoadError(error.localizedDescription)
            }
            await connection.disconnect()
            liveConnections.removeValue(forKey: session.id)
            sessionProfiles.removeValue(forKey: session.id)
            connectedProfileIDs.remove(profile.id)
            throw error
        }
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

    func setAccessMode(_ mode: DatabaseAccessMode, for sessionID: DatabaseBrowserSessionViewModel.ID) async {
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            logger.error("Requested access mode change for missing session \(sessionID.uuidString, privacy: .public)")
            return
        }
        logger.info("Applying access mode \(mode.logDescription) to session \(session.databaseName, privacy: .public)")
        await session.setAccessMode(mode)
    }

    func markStatus(_ status: DatabaseBrowserSessionStatus, for sessionID: DatabaseBrowserSessionViewModel.ID) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        session.status = status
    }

    func removeSession(_ sessionID: DatabaseBrowserSessionViewModel.ID) {
        if let connection = liveConnections.removeValue(forKey: sessionID) {
            Task {
                await connection.disconnect()
            }
        }
        if let profileID = sessionProfiles.removeValue(forKey: sessionID) {
            connectedProfileIDs.remove(profileID)
        }
        sessions.removeAll { $0.id == sessionID }
        if selectedSessionID == sessionID {
            selectedSessionID = sessions.first?.id
        }
    }

    var windowTitle: String {
        "Database Browser"
    }

}

private extension DatabaseAccessMode {
    var logDescription: String {
        switch self {
        case .readOnly:
            return "read-only"
        case .writable:
            return "writable"
        }
    }
}
