public struct AppDependencies: Sendable {
    public var connectionStore: any ConnectionStore
    public var sshAliasProvider: any SSHConfigAliasProvider
    public var sshKeychainService: any SSHKeychainService
    public var sshTunnelManager: any SSHTunnelManager

    public init(
        connectionStore: some ConnectionStore,
        sshAliasProvider: some SSHConfigAliasProvider = DefaultSSHConfigAliasProvider(),
        sshKeychainService: some SSHKeychainService = DefaultSSHKeychainService(),
        sshTunnelManager: some SSHTunnelManager = NoopSSHTunnelManager()
    ) {
        self.connectionStore = connectionStore
        self.sshAliasProvider = sshAliasProvider
        self.sshKeychainService = sshKeychainService
        self.sshTunnelManager = sshTunnelManager
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
