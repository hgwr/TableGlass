import Foundation

public struct DatabaseQueryRequest: Sendable, Hashable {
    public var sql: String
    public var parameters: [DatabaseQueryValue]

    public init(sql: String, parameters: [DatabaseQueryValue] = []) {
        self.sql = sql
        self.parameters = parameters
    }
}

public enum DatabaseQueryValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case date(Date)
    case data(Data)
    case uuid(UUID)

    public var description: String {
        switch self {
        case .null:
            return "NULL"
        case .bool(let value):
            return value ? "true" : "false"
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .string(let value):
            return value
        case .date(let value):
            return ISO8601DateFormatter().string(from: value)
        case .data(let value):
            return "<data, \(value.count) bytes>"
        case .uuid(let value):
            return value.uuidString
        }
    }
}

public struct DatabaseQueryRow: Sendable, Equatable {
    public var values: [String: DatabaseQueryValue]

    public init(values: [String: DatabaseQueryValue] = [:]) {
        self.values = values
    }

    public subscript(column column: String) -> DatabaseQueryValue? {
        values[column]
    }
}

public struct DatabaseQueryResult: Sendable, Equatable {
    public var rows: [DatabaseQueryRow]
    public var affectedRowCount: Int?

    public init(rows: [DatabaseQueryRow] = [], affectedRowCount: Int? = nil) {
        self.rows = rows
        self.affectedRowCount = affectedRowCount
    }
}

public struct DatabaseMetadataScope: Sendable, Hashable {
    public var schemaNames: [String]?
    public var includeTables: Bool
    public var includeViews: Bool
    public var includeProcedures: Bool

    public init(
        schemaNames: [String]? = nil,
        includeTables: Bool = true,
        includeViews: Bool = true,
        includeProcedures: Bool = true
    ) {
        self.schemaNames = schemaNames
        self.includeTables = includeTables
        self.includeViews = includeViews
        self.includeProcedures = includeProcedures
    }
}

public struct DatabaseSchema: Sendable, Equatable {
    public var catalogs: [DatabaseCatalog]

    public init(catalogs: [DatabaseCatalog]) {
        self.catalogs = catalogs
    }
}

public struct DatabaseCatalog: Sendable, Equatable {
    public var name: String
    public var namespaces: [DatabaseNamespace]

    public init(name: String, namespaces: [DatabaseNamespace]) {
        self.name = name
        self.namespaces = namespaces
    }
}

public struct DatabaseNamespace: Sendable, Equatable {
    public var name: String
    public var tables: [DatabaseTable]
    public var views: [DatabaseView]
    public var procedures: [DatabaseStoredProcedure]

    public init(
        name: String,
        tables: [DatabaseTable] = [],
        views: [DatabaseView] = [],
        procedures: [DatabaseStoredProcedure] = []
    ) {
        self.name = name
        self.tables = tables
        self.views = views
        self.procedures = procedures
    }
}

public struct DatabaseTable: Sendable, Equatable {
    public var name: String
    public var columns: [DatabaseColumn]
    public var primaryKey: [String]

    public init(name: String, columns: [DatabaseColumn], primaryKey: [String] = []) {
        self.name = name
        self.columns = columns
        self.primaryKey = primaryKey
    }
}

public struct DatabaseColumn: Sendable, Equatable {
    public var name: String
    public var dataType: DatabaseColumnDataType
    public var isNullable: Bool
    public var defaultValue: DatabaseQueryValue?

    public init(
        name: String,
        dataType: DatabaseColumnDataType,
        isNullable: Bool = true,
        defaultValue: DatabaseQueryValue? = nil
    ) {
        self.name = name
        self.dataType = dataType
        self.isNullable = isNullable
        self.defaultValue = defaultValue
    }
}

public enum DatabaseColumnDataType: Sendable, Equatable {
    case integer
    case numeric(precision: Int?, scale: Int?)
    case boolean
    case text
    case binary
    case timestamp(withTimeZone: Bool)
    case date
    case custom(String)
}

public struct DatabaseView: Sendable, Equatable {
    public var name: String
    public var definition: String?

    public init(name: String, definition: String? = nil) {
        self.name = name
        self.definition = definition
    }
}

public struct DatabaseStoredProcedure: Sendable, Equatable {
    public var name: String
    public var parameters: [DatabaseStoredProcedureParameter]
    public var returnType: DatabaseColumnDataType?

    public init(
        name: String,
        parameters: [DatabaseStoredProcedureParameter] = [],
        returnType: DatabaseColumnDataType? = nil
    ) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
    }
}

public struct DatabaseStoredProcedureParameter: Sendable, Equatable {
    public enum Direction: Sendable {
        case input
        case output
        case inputOutput
    }

    public var name: String
    public var direction: Direction
    public var dataType: DatabaseColumnDataType

    public init(name: String, direction: Direction, dataType: DatabaseColumnDataType) {
        self.name = name
        self.direction = direction
        self.dataType = dataType
    }
}
