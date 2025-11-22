import TableGlassKit
import Testing

@testable import TableGlass

struct DatabaseQueryLogTests {

    @Test
    func retainsWithinCapacity() async throws {
        let log = DatabaseQueryLog(capacity: 3)
        await log.append(sql: "SELECT 1", outcome: .success, timestamp: Date(timeIntervalSince1970: 0))
        await log.append(sql: "SELECT 2", outcome: .success, timestamp: Date(timeIntervalSince1970: 1))
        await log.append(sql: "SELECT 3", outcome: .failure("boom"), timestamp: Date(timeIntervalSince1970: 2))
        await log.append(sql: "SELECT 4", outcome: .success, timestamp: Date(timeIntervalSince1970: 3))

        let entries = await log.entriesSnapshot()
        #expect(entries.count == 3)
        #expect(entries.first?.sql == "SELECT 2")
        #expect(entries.last?.sql == "SELECT 4")
    }

    @Test
    func loggingExecutorRecordsOutcomes() async throws {
        let log = DatabaseQueryLog(capacity: 5)
        let successExecutor = LoggingDatabaseQueryExecutor(base: StubExecutor(result: .success(DatabaseQueryResult())), log: log)
        _ = try await successExecutor.execute(DatabaseQueryRequest(sql: "SELECT 1"))

        let failureExecutor = LoggingDatabaseQueryExecutor(
            base: StubExecutor(result: .failure(DummyError.failed)),
            log: log
        )
        do {
            _ = try await failureExecutor.execute(DatabaseQueryRequest(sql: "DELETE FROM items"))
            #expect(Bool(false), "Expected failure to throw")
        } catch {
            // Expected
        }

        let entries = await log.entriesSnapshot()
        #expect(entries.count == 2)
        #expect(entries.first?.outcome == .success)
        #expect(entries.last?.outcome == .failure(DummyError.failed.localizedDescription))
    }

    @Test
    func formatsTimestampsForDisplay() async throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let subject = DatabaseSessionLogFormatter(dateFormatter: formatter)

        let entry = DatabaseQueryLogEntry(timestamp: Date(timeIntervalSince1970: 0), sql: "SELECT 1", outcome: .success)
        let display = subject.makeDisplayEntry(from: entry)

        #expect(display.timestampText == "1970-01-01 00:00:00")
        #expect(display.sql == "SELECT 1")
    }
}

private struct StubExecutor: DatabaseQueryExecutor {
    let result: Result<DatabaseQueryResult, Error>

    func execute(_ request: DatabaseQueryRequest) async throws -> DatabaseQueryResult {
        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}

enum DummyError: Error {
    case failed
}
