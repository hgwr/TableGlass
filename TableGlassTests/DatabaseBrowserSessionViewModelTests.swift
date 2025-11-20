import TableGlassKit
import Testing

@testable import TableGlass

@MainActor
struct DatabaseBrowserSessionViewModelTests {

    @Test
    func refreshBuildsTreeFromMetadata() async throws {
        let session = DatabaseBrowserSessionViewModel(
            databaseName: "preview",
            status: .online,
            isReadOnly: false,
            metadataProvider: PreviewDatabaseMetadataProvider(schema: .previewBrowserSchema)
        )

        await session.refresh()

        #expect(session.treeNodes.count == 2)
        let catalogNames = Set(session.treeNodes.map(\.title))
        #expect(catalogNames.contains("main"))
        #expect(catalogNames.contains("archive"))
        #expect(session.selectedNode == nil)
    }

    @Test
    func expandingLoadsChildrenLazily() async throws {
        let session = DatabaseBrowserSessionViewModel(
            databaseName: "preview",
            status: .online,
            isReadOnly: false,
            metadataProvider: PreviewDatabaseMetadataProvider(schema: .previewBrowserSchema)
        )

        await session.refresh()

        guard let mainCatalog = session.treeNodes.first(where: { $0.title == "main" }) else {
            #expect(Bool(false), "Expected main catalog to be present")
            return
        }

        session.toggleExpansion(for: mainCatalog.id, isExpanded: true)

        guard let publicNamespace = session.treeNodes
            .first(where: { $0.title == "main" })?
            .children
            .first(where: { $0.title == "public" }) else {
            #expect(Bool(false), "Expected public namespace after expanding main")
            return
        }

        session.toggleExpansion(for: publicNamespace.id, isExpanded: true)

        let objectNames = session.treeNodes
            .first(where: { $0.title == "main" })?
            .children
            .first(where: { $0.title == "public" })?
            .children
            .map(\.title) ?? []

        #expect(objectNames.contains("artists"))
        #expect(objectNames.contains("albums"))
        #expect(objectNames.contains("top_artists"))
    }
}
