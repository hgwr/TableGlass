import Combine
import Foundation
import SwiftUI
import TableGlassKit

@MainActor
final class AppEnvironment: ObservableObject {
    let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    static func makeDefault() -> AppEnvironment {
        // TODO: Replace with a real implementation of ConnectionStore.
        AppEnvironment(dependencies: .empty)
    }

    static func makePreview() -> AppEnvironment {
        AppEnvironment(dependencies: .preview)
    }

    func makeConnectionListViewModel() -> ConnectionListViewModel {
        ConnectionListViewModel(connectionStore: dependencies.connectionStore)
    }
}
