public struct AppDependencies: Sendable {
    public var connectionStore: any ConnectionStore

    public init(connectionStore: some ConnectionStore) {
        self.connectionStore = connectionStore
    }
}

public extension AppDependencies {
    static var preview: AppDependencies {
        AppDependencies(connectionStore: PreviewConnectionStore())
    }

    static var empty: AppDependencies {
        AppDependencies(connectionStore: EmptyConnectionStore())
    }
}
