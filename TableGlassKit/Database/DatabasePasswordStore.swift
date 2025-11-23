public protocol DatabasePasswordStoring: Sendable {
    func store(password: String, identifier: String) async throws -> String
    func deletePassword(identifier: String) async throws
}

public struct KeychainDatabasePasswordStore: DatabasePasswordStoring {
    public init() {}

    public func store(password: String, identifier: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try DatabasePasswordKeychain.store(password: password, identifier: identifier)
        }.value
    }

    public func deletePassword(identifier: String) async throws {
        try await Task.detached(priority: .utility) {
            try DatabasePasswordKeychain.deletePassword(identifier: identifier)
        }.value
    }
}
