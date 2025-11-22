import Foundation

public struct MockDatabaseLatency: Sendable, Equatable {
    public var connect: Duration
    public var metadata: Duration
    public var execute: Duration
    public var transaction: Duration

    public init(connect: Duration = .zero, metadata: Duration = .zero, execute: Duration = .zero, transaction: Duration = .zero) {
        self.connect = connect
        self.metadata = metadata
        self.execute = execute
        self.transaction = transaction
    }

    public static let none = MockDatabaseLatency()
}

public enum MockDatabaseResponse: Sendable {
    case result(DatabaseQueryResult, delay: Duration? = nil)
    case failure(any Error & Sendable, delay: Duration? = nil)

    var delay: Duration? {
        switch self {
        case .result(_, let delay), .failure(_, let delay):
            return delay
        }
    }
}

public enum MockMetadataResponse: Sendable {
    case schema(DatabaseSchema, delay: Duration? = nil)
    case failure(any Error & Sendable, delay: Duration? = nil)

    var delay: Duration? {
        switch self {
        case .schema(_, let delay), .failure(_, let delay):
            return delay
        }
    }
}

public struct MockDatabaseQueryRoute: Sendable {
    public let matcher: @Sendable (DatabaseQueryRequest) -> Bool
    public let responder: @Sendable (DatabaseQueryRequest) -> MockDatabaseResponse

    public init(
        matcher: @escaping @Sendable (DatabaseQueryRequest) -> Bool,
        responder: @escaping @Sendable (DatabaseQueryRequest) -> MockDatabaseResponse
    ) {
        self.matcher = matcher
        self.responder = responder
    }
}

public extension MockDatabaseQueryRoute {
    static func sqlEquals(_ sql: String, response: MockDatabaseResponse) -> MockDatabaseQueryRoute {
        let normalized = Self.normalize(sql)
        return MockDatabaseQueryRoute(
            matcher: { Self.normalize($0.sql) == normalized },
            responder: { _ in response }
        )
    }

    static func sqlContains(_ fragment: String, response: MockDatabaseResponse) -> MockDatabaseQueryRoute {
        let normalized = Self.normalize(fragment)
        return MockDatabaseQueryRoute(
            matcher: { Self.normalize($0.sql).contains(normalized) },
            responder: { _ in response }
        )
    }

    static func any(_ response: MockDatabaseResponse) -> MockDatabaseQueryRoute {
        MockDatabaseQueryRoute(
            matcher: { _ in true },
            responder: { _ in response }
        )
    }

    private static func normalize(_ sql: String) -> String {
        sql.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct MockDatabaseTransactionPlan: Sendable {
    public var routes: [MockDatabaseQueryRoute]
    public var defaultResponse: MockDatabaseResponse
    public var latency: Duration
    public var commitError: (any Error & Sendable)?

    public init(
        routes: [MockDatabaseQueryRoute] = [],
        defaultResponse: MockDatabaseResponse = .result(DatabaseQueryResult()),
        latency: Duration = .zero,
        commitError: (any Error & Sendable)? = nil
    ) {
        self.routes = routes
        self.defaultResponse = defaultResponse
        self.latency = latency
        self.commitError = commitError
    }
}

public enum MockDatabaseError: LocalizedError, Sendable, Equatable {
    case unhandledRequest(String)
    case notConnected
    case connectionRejected
    case missingRow
    case deleteRejected(UUID)

    public var errorDescription: String? {
        switch self {
        case .unhandledRequest(let sql):
            return "No mock response registered for \(sql)"
        case .notConnected:
            return "Connection is not open."
        case .connectionRejected:
            return "Connection was rejected by the mock."
        case .missingRow:
            return "Row could not be located."
        case .deleteRejected(let id):
            return "Deletion rejected for row \(id.uuidString)."
        }
    }
}

public actor MockDatabaseConnection: DatabaseConnection {
    public let profile: ConnectionProfile

    private let metadataResponse: MockMetadataResponse
    private let routes: [MockDatabaseQueryRoute]
    private let defaultResponse: MockDatabaseResponse
    private let latency: MockDatabaseLatency
    private let connectError: (any Error & Sendable)?
    private let transactionPlan: MockDatabaseTransactionPlan
    private var connected = false
    private var executedRequests: [DatabaseQueryRequest] = []
    private var metadataScopes: [DatabaseMetadataScope] = []

    public init(
        profile: ConnectionProfile,
        metadata: MockMetadataResponse = .schema(DatabaseSchema(catalogs: [])),
        routes: [MockDatabaseQueryRoute] = [],
        defaultResponse: MockDatabaseResponse = .result(DatabaseQueryResult()),
        latency: MockDatabaseLatency = .none,
        connectError: (any Error & Sendable)? = nil,
        transactionPlan: MockDatabaseTransactionPlan? = nil
    ) {
        self.profile = profile
        self.metadataResponse = metadata
        self.routes = routes
        self.defaultResponse = defaultResponse
        self.latency = latency
        self.connectError = connectError
        self.transactionPlan = transactionPlan ?? MockDatabaseTransactionPlan(
            routes: routes,
            defaultResponse: defaultResponse,
            latency: latency.transaction
        )
    }

    public func connect() async throws {
        try await sleepIfNeeded(latency.connect)
        if let connectError {
            throw connectError
        }
        connected = true
    }

    public func disconnect() async {
        connected = false
    }

    public func isConnected() async -> Bool {
        connected
    }

    public func beginTransaction(options _: DatabaseTransactionOptions) async throws -> any DatabaseTransaction {
        guard connected else { throw DatabaseConnectionError.notConnected }
        try await sleepIfNeeded(latency.transaction)
        return MockDatabaseTransaction(plan: transactionPlan)
    }

    public func metadata(scope: DatabaseMetadataScope) async throws -> DatabaseSchema {
        guard connected else { throw DatabaseConnectionError.notConnected }
        metadataScopes.append(scope)
        return try await resolve(metadataResponse, defaultDelay: latency.metadata)
    }

    @discardableResult
    public func execute(_ request: DatabaseQueryRequest) async throws -> DatabaseQueryResult {
        guard connected else { throw DatabaseConnectionError.notConnected }
        executedRequests.append(request)
        let response = routes.first(where: { $0.matcher(request) })?.responder(request) ?? defaultResponse
        return try await resolve(response, defaultDelay: latency.execute)
    }

    public func recordedRequests() async -> [DatabaseQueryRequest] {
        executedRequests
    }

    public func recordedMetadataScopes() async -> [DatabaseMetadataScope] {
        metadataScopes
    }

    private func resolve(_ response: MockMetadataResponse, defaultDelay: Duration) async throws -> DatabaseSchema {
        try await sleepIfNeeded(response.delay ?? defaultDelay)
        switch response {
        case .schema(let schema, _):
            return schema
        case .failure(let error, _):
            throw error
        }
    }

    private func resolve(_ response: MockDatabaseResponse, defaultDelay: Duration) async throws -> DatabaseQueryResult {
        try await sleepIfNeeded(response.delay ?? defaultDelay)
        switch response {
        case .result(let result, _):
            return result
        case .failure(let error, _):
            throw error
        }
    }

    private func sleepIfNeeded(_ delay: Duration) async throws {
        guard delay != .zero else { return }
        try await Task.sleep(for: delay)
    }
}

public actor MockDatabaseTransaction: DatabaseTransaction {
    private let routes: [MockDatabaseQueryRoute]
    private let defaultResponse: MockDatabaseResponse
    private let latency: Duration
    private let commitError: (any Error & Sendable)?
    private var executedRequests: [DatabaseQueryRequest] = []
    private var committed = false
    private var rolledBack = false

    init(plan: MockDatabaseTransactionPlan) {
        self.routes = plan.routes
        self.defaultResponse = plan.defaultResponse
        self.latency = plan.latency
        self.commitError = plan.commitError
    }

    @discardableResult
    public func execute(_ request: DatabaseQueryRequest) async throws -> DatabaseQueryResult {
        executedRequests.append(request)
        let response = routes.first(where: { $0.matcher(request) })?.responder(request) ?? defaultResponse
        return try await resolve(response)
    }

    public func commit() async throws {
        try await sleepIfNeeded(latency)
        if let commitError {
            throw commitError
        }
        committed = true
    }

    public func rollback() async {
        if latency != .zero {
            try? await Task.sleep(for: latency)
        }
        rolledBack = true
    }

    public func executedRequestsSnapshot() async -> [DatabaseQueryRequest] {
        executedRequests
    }

    public func didCommit() async -> Bool {
        committed
    }

    public func didRollback() async -> Bool {
        rolledBack
    }

    private func resolve(_ response: MockDatabaseResponse) async throws -> DatabaseQueryResult {
        try await sleepIfNeeded(response.delay ?? latency)
        switch response {
        case .result(let result, _):
            return result
        case .failure(let error, _):
            throw error
        }
    }

    private func sleepIfNeeded(_ delay: Duration) async throws {
        guard delay != .zero else { return }
        try await Task.sleep(for: delay)
    }
}

public actor MockDatabaseQueryExecutor: DatabaseQueryExecutor {
    private var routes: [MockDatabaseQueryRoute]
    private var defaultResponse: MockDatabaseResponse
    private var latency: Duration
    private var executedRequests: [DatabaseQueryRequest] = []

    public init(
        routes: [MockDatabaseQueryRoute] = [],
        defaultResponse: MockDatabaseResponse = .result(DatabaseQueryResult()),
        latency: Duration = .zero
    ) {
        self.routes = routes
        self.defaultResponse = defaultResponse
        self.latency = latency
    }

    @discardableResult
    public func execute(_ request: DatabaseQueryRequest) async throws -> DatabaseQueryResult {
        executedRequests.append(request)
        let response = routes.first(where: { $0.matcher(request) })?.responder(request) ?? defaultResponse
        return try await resolve(response)
    }

    public func recordedRequests() async -> [DatabaseQueryRequest] {
        executedRequests
    }

    public func updateDefaultResponse(_ response: MockDatabaseResponse) {
        defaultResponse = response
    }

    public func replaceRoutes(_ routes: [MockDatabaseQueryRoute]) {
        self.routes = routes
    }

    public func updateLatency(_ latency: Duration) {
        self.latency = latency
    }

    private func resolve(_ response: MockDatabaseResponse) async throws -> DatabaseQueryResult {
        let delay = response.delay ?? latency
        if delay != .zero {
            try await Task.sleep(for: delay)
        }
        switch response {
        case .result(let result, _):
            return result
        case .failure(let error, _):
            throw error
        }
    }
}
