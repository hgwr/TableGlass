import Combine
import Foundation
import TableGlassKit

@MainActor
final class DatabaseQueryEditorViewModel: ObservableObject {
    @Published var sqlText: String
    @Published private(set) var isExecuting: Bool = false
    @Published private(set) var result: DatabaseQueryResult?
    @Published private(set) var errorMessage: String?

    private let executor: @Sendable (DatabaseQueryRequest) async throws -> DatabaseQueryResult

    init(sqlText: String = "SELECT * FROM artists LIMIT 50", executor: @escaping @Sendable (DatabaseQueryRequest) async throws -> DatabaseQueryResult) {
        self.sqlText = sqlText
        self.executor = executor
    }

    func execute(isReadOnly: Bool) async {
        let sql = sqlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sql.isEmpty else { return }

        if isReadOnly && !allowsReadOnlyExecution(for: sql) {
            errorMessage = "Read-only mode prevents running this statement."
            return
        }

        isExecuting = true
        errorMessage = nil
        defer { isExecuting = false }

        do {
            let request = DatabaseQueryRequest(sql: sql)
            result = try await executor(request)
        } catch {
            result = nil
            errorMessage = error.localizedDescription
        }
    }

    func allowsReadOnlyExecution(for sql: String? = nil) -> Bool {
        let trimmed = (sql ?? sqlText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let keyword = trimmed.split(separator: " ", maxSplits: 1).first?.lowercased() else { return false }

        let readOnlyKeywords: Set<String> = ["select", "with", "show", "describe", "desc", "explain", "pragma"]
        return readOnlyKeywords.contains(keyword)
    }
}
