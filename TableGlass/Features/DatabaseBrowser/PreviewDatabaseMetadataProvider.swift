import Foundation
import TableGlassKit

actor PreviewDatabaseMetadataProvider: DatabaseMetadataProvider {
    private let schema: DatabaseSchema

    init(schema: DatabaseSchema = .previewBrowserSchema) {
        self.schema = schema
    }

    func metadata(scope: DatabaseMetadataScope) async throws -> DatabaseSchema {
        try await Task.sleep(nanoseconds: 25_000_000)
        return schema
    }
}

extension DatabaseSchema {
    static var previewBrowserSchema: DatabaseSchema {
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
