import Foundation
import TableGlassKit

actor PreviewDatabaseMetadataProvider: DatabaseMetadataProvider {
    private let schema: DatabaseSchema

    init(schema: DatabaseSchema = .previewBrowserSchema) {
        self.schema = schema
    }

    func metadata(scope: DatabaseMetadataScope) async throws -> DatabaseSchema {
        try await Task.sleep(nanoseconds: 25_000_000)

        let filteredCatalogs = schema.catalogs.compactMap { catalog -> DatabaseCatalog? in
            let namespaces = catalog.namespaces
                .filter { namespace in
                    guard let allowedSchemas = scope.schemaNames else { return true }
                    return allowedSchemas.contains(namespace.name)
                }
                .compactMap { namespace -> DatabaseNamespace? in
                    let tables = scope.includeTables ? namespace.tables : []
                    let views = scope.includeViews ? namespace.views : []
                    let procedures = scope.includeProcedures ? namespace.procedures : []

                    guard !tables.isEmpty || !views.isEmpty || !procedures.isEmpty else { return nil }

                    return DatabaseNamespace(
                        name: namespace.name,
                        tables: tables,
                        views: views,
                        procedures: procedures
                    )
                }

            guard !namespaces.isEmpty else { return nil }

            return DatabaseCatalog(
                name: catalog.name,
                namespaces: namespaces
            )
        }

        return DatabaseSchema(catalogs: filteredCatalogs)
    }
}

extension PreviewDatabaseMetadataProvider: DatabaseQueryExecutor {
    func execute(_ request: DatabaseQueryRequest) async throws -> DatabaseQueryResult {
        try await Task.sleep(nanoseconds: 10_000_000)
        let rows = Self.previewRows(for: request.sql)
        return DatabaseQueryResult(rows: rows, affectedRowCount: rows.count)
    }

    private static func previewRows(for sql: String) -> [DatabaseQueryRow] {
        let lowercased = sql.lowercased()
        if lowercased.contains("artists") {
            return [
                DatabaseQueryRow(values: [
                    "id": .int(1),
                    "name": .string("Alice & The Cats"),
                    "country": .string("US"),
                    "bio": .string("Emerging indie group with layered synths and long-form lyrics that test truncation handling."),
                ]),
                DatabaseQueryRow(values: [
                    "id": .int(2),
                    "name": .string("Neon Rivers"),
                    "country": .string("DE"),
                    "bio": .string("Known for cinematic electronica. Latest release blends acoustic strings with glitch textures."),
                ]),
            ]
        }

        if lowercased.contains("albums") {
            return [
                DatabaseQueryRow(values: [
                    "id": .int(10),
                    "artist_id": .int(1),
                    "title": .string("Arcade Nights"),
                    "metadata": .string("{\"moods\":[\"upbeat\",\"nostalgic\"],\"released\":2017}"),
                ]),
            ]
        }

        return [
            DatabaseQueryRow(values: [
                "id": .int(1),
                "payload": .string("{\"status\":\"ok\",\"context\":\"preview\"}"),
                "notes": .string("Preview query data available during UI tests."),
            ])
        ]
    }
}

extension DatabaseSchema {
    nonisolated(unsafe) static var previewBrowserSchema: DatabaseSchema {
        DatabaseSchema(
            catalogs: [
                DatabaseCatalog(
                    name: "main",
                    namespaces: [
                        DatabaseNamespace(
                            name: "public",
                            tables: [
                                DatabaseTable(
                                    name: "artists",
                                    columns: [
                                        DatabaseColumn(name: "id", dataType: .integer, isNullable: false),
                                        DatabaseColumn(name: "name", dataType: .text, isNullable: false),
                                        DatabaseColumn(name: "country", dataType: .text)
                                    ],
                                    primaryKey: ["id"]
                                ),
                                DatabaseTable(
                                    name: "albums",
                                    columns: [
                                        DatabaseColumn(name: "id", dataType: .integer, isNullable: false),
                                        DatabaseColumn(name: "artist_id", dataType: .integer, isNullable: false),
                                        DatabaseColumn(name: "title", dataType: .text)
                                    ],
                                    primaryKey: ["id"]
                                ),
                            ],
                            views: [
                                DatabaseView(name: "top_artists", definition: "SELECT * FROM artists LIMIT 50")
                            ],
                            procedures: [
                                DatabaseStoredProcedure(
                                    name: "refresh_caches",
                                    parameters: [
                                        DatabaseStoredProcedureParameter(
                                            name: "force",
                                            direction: .input,
                                            dataType: .boolean
                                        )
                                    ]
                                )
                            ]
                        ),
                        DatabaseNamespace(
                            name: "reporting",
                            tables: [
                                DatabaseTable(
                                    name: "fact_sales",
                                    columns: [
                                        DatabaseColumn(name: "id", dataType: .integer, isNullable: false),
                                        DatabaseColumn(name: "amount", dataType: .numeric(precision: 12, scale: 2))
                                    ],
                                    primaryKey: ["id"]
                                ),
                            ],
                            views: [
                                DatabaseView(name: "daily_summary", definition: nil)
                            ]
                        )
                    ]
                ),
                DatabaseCatalog(
                    name: "archive",
                    namespaces: [
                        DatabaseNamespace(
                            name: "vault",
                            tables: [
                                DatabaseTable(
                                    name: "events_2023",
                                    columns: [
                                        DatabaseColumn(name: "event_id", dataType: .custom("uuid"), isNullable: false),
                                        DatabaseColumn(name: "occurred_at", dataType: .timestamp(withTimeZone: true))
                                    ]
                                )
                            ],
                            procedures: [
                                DatabaseStoredProcedure(name: "compact_partitions")
                            ]
                        )
                    ]
                )
            ]
        )
    }
}
