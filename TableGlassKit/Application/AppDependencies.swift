public struct AppDependencies: Sendable {
    public var connectionStore: any ConnectionStore
    public var sshAliasProvider: any SSHConfigAliasProvider
    public var sshKeychainService: any SSHKeychainService
    public var sshTunnelManager: any SSHTunnelManager
    public var sshAgentService: any SSHAgentService
    public var databaseConnectionProvider: DatabaseConnectionProvider

    public init(
        connectionStore: some ConnectionStore,
        sshAliasProvider: some SSHConfigAliasProvider = DefaultSSHConfigAliasProvider(),
        sshKeychainService: some SSHKeychainService = DefaultSSHKeychainService(),
        sshTunnelManager: some SSHTunnelManager = NoopSSHTunnelManager(),
        sshAgentService: some SSHAgentService = DefaultSSHAgentService(),
        databaseConnectionProvider: DatabaseConnectionProvider = .placeholderDrivers
    ) {
        self.connectionStore = connectionStore
        self.sshAliasProvider = sshAliasProvider
        self.sshKeychainService = sshKeychainService
        self.sshTunnelManager = sshTunnelManager
        self.sshAgentService = sshAgentService
        self.databaseConnectionProvider = databaseConnectionProvider
    }
}

public extension AppDependencies {
    static var preview: AppDependencies {
        AppDependencies(connectionStore: PreviewConnectionStore())
    }

    static var empty: AppDependencies {
        AppDependencies(connectionStore: EmptyConnectionStore())
    }

    static func fromEnvironment(
        passwordResolver: some DatabasePasswordResolver = KeychainDatabasePasswordResolver()
    ) -> AppDependencies {
        .live(passwordResolver: passwordResolver)
    }

    static func live(passwordResolver: some DatabasePasswordResolver = KeychainDatabasePasswordResolver()) -> AppDependencies {
        AppDependencies(
            connectionStore: UserDefaultsConnectionStore(),
            databaseConnectionProvider: .placeholderDrivers.withPostgresNIO(passwordResolver: passwordResolver)
        )
    }

    #if canImport(PostgresNIO)
    static func localDebug(passwordResolver: some DatabasePasswordResolver = KeychainDatabasePasswordResolver()) -> AppDependencies {
        .live(passwordResolver: passwordResolver)
    }
    #endif
}
