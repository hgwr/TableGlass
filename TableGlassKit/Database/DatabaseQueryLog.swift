import Foundation

public enum DatabaseQueryOutcome: Sendable, Equatable {
    case success
    case failure(String)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

public struct DatabaseQueryLogEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let sql: String
    public let outcome: DatabaseQueryOutcome

    public init(id: UUID = UUID(), timestamp: Date = .now, sql: String, outcome: DatabaseQueryOutcome) {
        self.id = id
        self.timestamp = timestamp
        self.sql = sql
        self.outcome = outcome
    }
}

public actor DatabaseQueryLog {
    public let capacity: Int

    private var entries: [DatabaseQueryLogEntry]
    private var continuations: [UUID: AsyncStream<[DatabaseQueryLogEntry]>.Continuation]

    public init(capacity: Int = 500) {
        self.capacity = max(1, capacity)
        entries = []
        continuations = [:]
    }

    deinit {
        continuations.values.forEach { $0.finish() }
    }

    public func append(_ entry: DatabaseQueryLogEntry) {
        var updatedEntries = entries
        updatedEntries.append(entry)
        if updatedEntries.count > capacity {
            updatedEntries.removeFirst(updatedEntries.count - capacity)
        }
        entries = updatedEntries
        continuations.values.forEach { $0.yield(entries) }
    }

    public func append(sql: String, outcome: DatabaseQueryOutcome, timestamp: Date = .now) {
        let entry = DatabaseQueryLogEntry(timestamp: timestamp, sql: sql, outcome: outcome)
        append(entry)
    }

    public func entriesSnapshot() -> [DatabaseQueryLogEntry] {
        entries
    }

    public func entriesStream() -> AsyncStream<[DatabaseQueryLogEntry]> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.yield(entries)
            continuations[id] = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id]?.finish()
        continuations[id] = nil
    }
}

public struct LoggingDatabaseQueryExecutor<Base: DatabaseQueryExecutor>: DatabaseQueryExecutor {
    private let base: Base
    private let log: DatabaseQueryLog

    public init(base: Base, log: DatabaseQueryLog) {
        self.base = base
        self.log = log
    }

    public func execute(_ request: DatabaseQueryRequest) async throws -> DatabaseQueryResult {
        do {
            let result = try await base.execute(request)
            await log.append(sql: request.sql, outcome: .success)
            return result
        } catch {
            await log.append(sql: request.sql, outcome: .failure(error.localizedDescription))
            throw error
        }
    }
}

public struct LoggingDatabaseTransaction<Base: DatabaseTransaction>: DatabaseTransaction {
    private var base: Base
    private let log: DatabaseQueryLog

    public init(base: Base, log: DatabaseQueryLog) {
        self.base = base
        self.log = log
    }

    public func commit() async throws {
        try await base.commit()
    }

    public func rollback() async {
        await base.rollback()
    }

    public func execute(_ request: DatabaseQueryRequest) async throws -> DatabaseQueryResult {
        try await LoggingDatabaseQueryExecutor(base: base, log: log).execute(request)
    }
}

public struct LoggingDatabaseConnection<Base: DatabaseConnection>: DatabaseConnection {
    private var base: Base
    private let log: DatabaseQueryLog

    public init(base: Base, log: DatabaseQueryLog) {
        self.base = base
        self.log = log
    }

    public var profile: ConnectionProfile { base.profile }

    public func connect() async throws {
        try await base.connect()
    }

    public func disconnect() async {
        await base.disconnect()
    }

    public func isConnected() async -> Bool {
        await base.isConnected()
    }

    public func beginTransaction(options: DatabaseTransactionOptions) async throws -> any DatabaseTransaction {
        let transaction = try await base.beginTransaction(options: options)
        return LoggingDatabaseTransaction(base: transaction, log: log)
    }

    public func metadata(scope: DatabaseMetadataScope) async throws -> DatabaseSchema {
        try await base.metadata(scope: scope)
    }

    public func execute(_ request: DatabaseQueryRequest) async throws -> DatabaseQueryResult {
        try await LoggingDatabaseQueryExecutor(base: base, log: log).execute(request)
    }
}

public extension DatabaseQueryLog {
    static func preview(with entries: [DatabaseQueryLogEntry]) -> DatabaseQueryLog {
        let log = DatabaseQueryLog(capacity: max(entries.count, 1))
        Task {
            for entry in entries {
                await log.append(entry)
            }
        }
        return log
    }
}
