import Foundation
import TableGlassKit
import Testing

@testable import TableGlass

@MainActor
struct DatabaseTableContentViewModelTests {
    private let tableID = DatabaseTableIdentifier(catalog: "main", namespace: "public", name: "artists")
    private let columns: [DatabaseColumn] = [
        DatabaseColumn(name: "id", dataType: .integer, isNullable: false),
        DatabaseColumn(name: "name", dataType: .text, isNullable: false),
        DatabaseColumn(name: "country", dataType: .text, isNullable: true),
    ]

    @Test
    func loadingFetchesFirstPage() async throws {
        let service = MockDatabaseTableDataService(
            table: tableID,
            columns: columns,
            rows: [
                DatabaseTableRow(values: DatabaseQueryRow(values: ["id": .int(1), "name": .string("One")]))
            ]
        )
        let viewModel = DatabaseTableContentViewModel(tableDataService: service, pageSize: 1)

        await viewModel.loadIfNeeded(for: tableID, columns: columns)

        #expect(viewModel.rows.count == 1)
        #expect(viewModel.hasMorePages == false)
        let snapshot = await service.snapshot(for: tableID)
        #expect(snapshot.count == 1)
    }

    @Test
    func prefetchesNextPageWhenApproachingEnd() async throws {
        let pageSize = 4
        let rows = (1...(pageSize * 2)).map { index in
            DatabaseTableRow(values: DatabaseQueryRow(values: [
                "id": .int(Int64(index)),
                "name": .string("Name \(index)"),
            ]))
        }
        let service = MockDatabaseTableDataService(table: tableID, columns: columns, rows: rows)
        let viewModel = DatabaseTableContentViewModel(tableDataService: service, pageSize: pageSize)

        await viewModel.loadIfNeeded(for: tableID, columns: columns)

        #expect(await service.recordedFetchPages(for: tableID) == [0])

        guard let triggerRow = viewModel.rows.suffix(2).first else {
            Issue.record("Expected at least two rows to trigger prefetch")
            return
        }

        await viewModel.prefetchNextPageIfNeeded(currentRowID: triggerRow.id)

        let fetchedPages = await service.recordedFetchPages(for: tableID)
        #expect(fetchedPages.contains(1))
        #expect(viewModel.rows.count == pageSize * 2)
    }

    @Test
    func commitRowUpdatesChanges() async throws {
        let service = MockDatabaseTableDataService(
            table: tableID,
            columns: columns,
            rows: [
                DatabaseTableRow(values: DatabaseQueryRow(values: ["id": .int(1), "name": .string("Original")]))
            ]
        )
        let viewModel = DatabaseTableContentViewModel(tableDataService: service, pageSize: 1)
        await viewModel.loadIfNeeded(for: tableID, columns: columns)

        guard let row = viewModel.rows.first else {
            Issue.record("Expected a row to edit")
            return
        }

        viewModel.updateCell(id: row.id, column: "name", text: "Updated")
        await viewModel.commitRow(row.id)

        let stored = await service.snapshot(for: tableID)
        #expect(stored.first?.values.values["name"] == .string("Updated"))
        #expect(viewModel.rows.first?.hasChanges == false)
    }

    @Test
    func insertAndDeleteRowsFlow() async throws {
        let service = MockDatabaseTableDataService(table: tableID, columns: columns, rows: [])
        let viewModel = DatabaseTableContentViewModel(tableDataService: service, pageSize: 10)
        await viewModel.loadIfNeeded(for: tableID, columns: columns)

        viewModel.addRow()
        guard let pending = viewModel.rows.first else {
            Issue.record("Expected new row to be present")
            return
        }

        viewModel.updateCell(id: pending.id, column: "id", text: "10")
        viewModel.updateCell(id: pending.id, column: "name", text: "New Artist")
        await viewModel.commitRow(pending.id)

        var stored = await service.snapshot(for: tableID)
        #expect(stored.count == 1)

        if let saved = viewModel.rows.first {
            viewModel.selection = [saved.id]
            await viewModel.deleteSelectedRows()
        }

        stored = await service.snapshot(for: tableID)
        #expect(stored.isEmpty)
    }

    @Test
    func validationErrorsSurfaceOnMissingRequiredField() async throws {
        let service = MockDatabaseTableDataService(
            table: tableID,
            columns: columns,
            rows: [
                DatabaseTableRow(values: DatabaseQueryRow(values: ["id": .int(5), "name": .string("Stale")]))
            ]
        )
        let viewModel = DatabaseTableContentViewModel(tableDataService: service, pageSize: 10)
        await viewModel.loadIfNeeded(for: tableID, columns: columns)

        guard let row = viewModel.rows.first else {
            Issue.record("Missing expected row")
            return
        }

        viewModel.updateCell(id: row.id, column: "name", text: "")
        await viewModel.commitRow(row.id)

        #expect(viewModel.rows.first?.error?.contains("requires a value") == true)
        #expect(viewModel.bannerError?.isEmpty == false)
    }

    @Test
    func deleteSelectedRowsAggregatesErrors() async throws {
        let failingOne = DatabaseTableRow(id: UUID(), values: DatabaseQueryRow(values: ["id": .int(1)]))
        let failingTwo = DatabaseTableRow(id: UUID(), values: DatabaseQueryRow(values: ["id": .int(2)]))
        let succeed = DatabaseTableRow(id: UUID(), values: DatabaseQueryRow(values: ["id": .int(3)]))
        let service = MockDatabaseTableDataService(
            table: tableID,
            columns: columns,
            rows: [failingOne, failingTwo, succeed],
            behavior: MockTableBehavior(failingRowIDs: [failingOne.id, failingTwo.id])
        )
        let viewModel = DatabaseTableContentViewModel(tableDataService: service, pageSize: 10)
        await viewModel.loadIfNeeded(for: tableID, columns: columns)

        viewModel.selection = [failingOne.id, failingTwo.id, succeed.id]
        await viewModel.deleteSelectedRows()

        #expect(viewModel.rows.count == 2)
        #expect(viewModel.selection == Set([failingOne.id, failingTwo.id]))
        #expect(viewModel.bannerError?.contains(failingOne.id.uuidString) == true)
        #expect(viewModel.bannerError?.contains(failingTwo.id.uuidString) == true)
    }

    @Test
    func previewServiceDoesNotClearStateWhenPagingBeyondEnd() async throws {
        let service = PreviewDatabaseTableDataService()
        let tableID = DatabaseTableIdentifier(catalog: "main", namespace: "public", name: "artists")

        let firstPage = try await service.fetchPage(for: tableID, page: 0, pageSize: 10)
        let initialCount = firstPage.rows.count

        let emptyPage = try await service.fetchPage(for: tableID, page: 10, pageSize: 10)
        #expect(emptyPage.rows.isEmpty)

        let refreshed = try await service.fetchPage(for: tableID, page: 0, pageSize: 10)
        #expect(refreshed.rows.count == initialCount)
    }
}
