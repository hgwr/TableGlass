import Combine
import Core
import Foundation
import SwiftUI

@MainActor
final class AppEnvironment: ObservableObject {
    let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    static func makeDefault() -> AppEnvironment {
        AppEnvironment(dependencies: .preview)
    }

    static func makePreview() -> AppEnvironment {
        AppEnvironment(dependencies: .preview)
    }

    func makeConnectionListViewModel() -> ConnectionListViewModel {
        ConnectionListViewModel(connectionStore: dependencies.connectionStore)
    }
}
