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

    func makeDatabaseBrowserViewModel() -> DatabaseBrowserViewModel {
        DatabaseBrowserViewModel()
    }

    func openStandaloneDatabaseBrowserWindow() {
        let viewModel = makeDatabaseBrowserViewModel()
        browserWindowCoordinator.openStandaloneWindow(with: viewModel)
    }
}
