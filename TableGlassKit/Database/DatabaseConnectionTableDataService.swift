import Foundation

public actor DatabaseConnectionTableDataService: DatabaseTableDataService {
    private let connection: any DatabaseConnection

    public init(connection: some DatabaseConnection) {
        self.connection = connection
    }

    public func fetchPage(for table: DatabaseTableIdentifier, page: Int, pageSize: Int) async throws -> DatabaseTablePage {
        let limit = max(1, pageSize) + 1
        let offset = max(0, page) * pageSize
        let sql = """
        SELECT * FROM \(qualifiedName(for: table))
        ORDER BY 1
        LIMIT $1 OFFSET $2
        """
        let result = try await connection.execute(
            DatabaseQueryRequest(
                sql: sql,
                parameters: [.int(Int64(limit)), .int(Int64(offset))]
            )
        )
        let hasMore = result.rows.count > pageSize
        let trimmedRows = Array(result.rows.prefix(pageSize))
        let rows = trimmedRows.map { DatabaseTableRow(values: $0) }
        return DatabaseTablePage(columns: [], rows: rows, hasMore: hasMore)
    }

    public func updateRow(
        for table: DatabaseTableIdentifier,
        row: DatabaseTableRow,
        changedValues: [String: DatabaseQueryValue]
    ) async throws -> DatabaseTableRow {
        guard !changedValues.isEmpty else { return row }

        var parameters: [DatabaseQueryValue] = []
        let assignments = changedValues.map { column, value -> String in
            parameters.append(value)
            return "\(quoteIdentifier(column)) = $\(parameters.count)"
        }
        let predicate = try makePredicate(
            from: row.values,
            startingAt: parameters.count + 1,
            parameters: &parameters
        )

        let sql = """
        UPDATE \(qualifiedName(for: table))
        SET \(assignments.joined(separator: ", "))
        WHERE \(predicate)
        RETURNING *
        """

        let result = try await connection.execute(DatabaseQueryRequest(sql: sql, parameters: parameters))
        guard let updated = result.rows.first else {
            throw DatabaseError.queryFailed("Update failed.")
        }

        return DatabaseTableRow(id: row.id, values: updated)
    }

    public func insertRow(for table: DatabaseTableIdentifier, values: [String: DatabaseQueryValue]) async throws -> DatabaseTableRow {
        if values.isEmpty {
            let result = try await connection.execute(
                DatabaseQueryRequest(sql: "INSERT INTO \(qualifiedName(for: table)) DEFAULT VALUES RETURNING *")
            )
            guard let inserted = result.rows.first else {
                throw DatabaseError.queryFailed("Insert failed.")
            }
            return DatabaseTableRow(values: inserted)
        }

        let columns = values.keys.sorted()
        var parameters: [DatabaseQueryValue] = []
        let placeholders: [String] = columns.enumerated().map { index, key in
            parameters.append(values[key] ?? .null)
            return "$\(index + 1)"
        }

        let sql = """
        INSERT INTO \(qualifiedName(for: table)) (\(columns.map(quoteIdentifier).joined(separator: ", ")))
        VALUES (\(placeholders.joined(separator: ", ")))
        RETURNING *
        """

        let result = try await connection.execute(DatabaseQueryRequest(sql: sql, parameters: parameters))
        guard let inserted = result.rows.first else {
            throw DatabaseError.queryFailed("Insert failed.")
        }

        return DatabaseTableRow(values: inserted)
    }

    public func deleteRow(for table: DatabaseTableIdentifier, row: DatabaseTableRow) async throws {
        var parameters: [DatabaseQueryValue] = []
        let predicate = try makePredicate(from: row.values, startingAt: 1, parameters: &parameters)
        let sql = "DELETE FROM \(qualifiedName(for: table)) WHERE \(predicate)"
        let result = try await connection.execute(DatabaseQueryRequest(sql: sql, parameters: parameters))
        let affected = result.affectedRowCount ?? 0
        guard affected > 0 else {
            throw DatabaseError.queryFailed("Row could not be deleted.")
        }
    }
}

private extension DatabaseConnectionTableDataService {
    func qualifiedName(for table: DatabaseTableIdentifier) -> String {
        let schema = quoteIdentifier(table.namespace)
        let name = quoteIdentifier(table.name)
        return "\(schema).\(name)"
    }

    func quoteIdentifier(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    func makePredicate(
        from row: DatabaseQueryRow,
        startingAt baseIndex: Int,
        parameters: inout [DatabaseQueryValue]
    ) throws -> String {
        var clauses: [String] = []
        var index = baseIndex
        for (column, value) in row.values {
            if value == .null {
                clauses.append("\(quoteIdentifier(column)) IS NULL")
            } else {
                parameters.append(value)
                clauses.append("\(quoteIdentifier(column)) = $\(index)")
                index += 1
            }
        }

        guard !clauses.isEmpty else {
            throw DatabaseError.queryFailed("No columns available to identify the row.")
        }

        return clauses.joined(separator: " AND ")
    }
}
