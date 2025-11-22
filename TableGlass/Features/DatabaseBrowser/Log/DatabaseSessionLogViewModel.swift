import Combine
import Foundation
import TableGlassKit

@MainActor
final class DatabaseSessionLogViewModel: ObservableObject {
    struct DisplayEntry: Identifiable, Equatable {
        let id: UUID
        let timestampText: String
        let sql: String
        let outcome: DatabaseQueryOutcome
    }

    @Published var searchText: String = ""
    @Published var statusFilter: StatusFilter = .all
    @Published private(set) var entries: [DatabaseQueryLogEntry]

    let databaseName: String

    private let log: DatabaseQueryLog
    private let formatter: DatabaseSessionLogFormatter
    private var streamTask: Task<Void, Never>?

    init(databaseName: String, log: DatabaseQueryLog, formatter: DatabaseSessionLogFormatter? = nil) {
        self.databaseName = databaseName
        self.log = log
        self.formatter = formatter ?? DatabaseSessionLogFormatter()
        entries = []
        streamTask = Task { await observeLog() }
    }

    deinit {
        streamTask?.cancel()
    }

    var displayEntries: [DisplayEntry] {
        let filtered = entries.filter { entry in
            let matchesQuery = searchText.isEmpty || entry.sql.localizedCaseInsensitiveContains(searchText)
            let matchesFilter = switch statusFilter {
            case .all:
                true
            case .success:
                entry.outcome.isSuccess
            case .failure:
                !entry.outcome.isSuccess
            }
            return matchesQuery && matchesFilter
        }
        return filtered.map { formatter.makeDisplayEntry(from: $0) }
    }

    func updateSearch(text: String) {
        searchText = text
    }

    func updateStatusFilter(_ filter: StatusFilter) {
        statusFilter = filter
    }

    private func observeLog() async {
        let stream = await log.entriesStream()
        for await snapshot in stream {
            await MainActor.run {
                self.entries = snapshot
            }
        }
    }
}

enum StatusFilter: String, CaseIterable, Identifiable {
    case all
    case success
    case failure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .success:
            "Success"
        case .failure:
            "Failure"
        }
    }
}

struct DatabaseSessionLogFormatter {
    private let dateFormatter: DateFormatter

    init(dateFormatter: DateFormatter? = nil) {
        if let dateFormatter {
            self.dateFormatter = dateFormatter
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            self.dateFormatter = formatter
        }
    }

    func makeDisplayEntry(from entry: DatabaseQueryLogEntry) -> DatabaseSessionLogViewModel.DisplayEntry {
        DatabaseSessionLogViewModel.DisplayEntry(
            id: entry.id,
            timestampText: dateFormatter.string(from: entry.timestamp),
            sql: entry.sql,
            outcome: entry.outcome
        )
    }
}

extension DatabaseSessionLogViewModel {
    static func preview() -> DatabaseSessionLogViewModel {
        let entries = [
            DatabaseQueryLogEntry(timestamp: .distantPast, sql: "SELECT * FROM artists", outcome: .success),
            DatabaseQueryLogEntry(timestamp: .now.addingTimeInterval(-60), sql: "UPDATE albums SET title = 'Acoustic'", outcome: .failure("Foreign key violation")),
        ]
        let log = DatabaseQueryLog.preview(with: entries)
        return DatabaseSessionLogViewModel(databaseName: "analytics", log: log)
    }
}
