import Combine
import Foundation
import SwiftUI
import TableGlassKit

@MainActor
final class AppEnvironment: ObservableObject {
    let dependencies: AppDependencies
    private let browserWindowCoordinator: DatabaseBrowserWindowCoordinator

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self.browserWindowCoordinator = DatabaseBrowserWindowCoordinator()
    }

    static func makeDefault() -> AppEnvironment {
        AppEnvironment(dependencies: .fromEnvironment())
    }

    static func makePreview() -> AppEnvironment {
        AppEnvironment(dependencies: .preview)
    }

    func makeConnectionListViewModel() -> ConnectionListViewModel {
        ConnectionListViewModel(connectionStore: dependencies.connectionStore)
    }

    func makeConnectionManagementViewModel() -> ConnectionManagementViewModel {
        ConnectionManagementViewModel(
            connectionStore: dependencies.connectionStore,
            sshAliasProvider: dependencies.sshAliasProvider,
            sshKeychainService: dependencies.sshKeychainService
        )
    }

    func makeDatabaseBrowserViewModel(autoloadSavedConnections: Bool = true) -> DatabaseBrowserViewModel {
        DatabaseBrowserViewModel(
            connectionStore: dependencies.connectionStore,
            connectionProvider: dependencies.databaseConnectionProvider,
            autoloadSavedConnections: autoloadSavedConnections
        )
    }

    func connectAndOpenBrowser(for profile: ConnectionProfile) async throws {
        let viewModel = makeDatabaseBrowserViewModel(autoloadSavedConnections: false)
        try await viewModel.connect(profile: profile)
        browserWindowCoordinator.openStandaloneWindow(with: viewModel)
    }

    func openPreviewDatabaseBrowserWindow() {
        let viewModel = DatabaseBrowserViewModel()
        browserWindowCoordinator.openStandaloneWindow(with: viewModel)
    }
}
