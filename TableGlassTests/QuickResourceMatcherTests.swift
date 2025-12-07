import Foundation
import Testing

@testable import TableGlass

struct QuickResourceMatcherTests {
    private let sessionID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    @Test
    func ranksTightMatchesFirst() throws {
        let index = QuickResourceIndex(
            sessionID: sessionID,
            sessionName: "analytics",
            items: [
                QuickResourceItem(
                    sessionID: sessionID,
                    sessionName: "analytics",
                    catalog: "main",
                    namespace: "public",
                    name: "orders",
                    kind: .table
                ),
                QuickResourceItem(
                    sessionID: sessionID,
                    sessionName: "analytics",
                    catalog: "main",
                    namespace: "sales",
                    name: "customer_orders",
                    kind: .table
                ),
                QuickResourceItem(
                    sessionID: sessionID,
                    sessionName: "analytics",
                    catalog: "analytics",
                    namespace: "derived",
                    name: "orders_view",
                    kind: .view
                ),
            ],
            lastUpdated: Date()
        )

        let matches = QuickResourceMatcher.rankedMatches(query: "ord", in: index)

        #expect(matches.map(\.item.name).prefix(3) == ["orders", "customer_orders", "orders_view"])
        #expect(matches.first?.score.sortValue ?? .max < matches.last?.score.sortValue ?? .max)
    }

    @Test
    func filtersByKindScope() throws {
        let index = QuickResourceIndex(
            sessionID: sessionID,
            sessionName: "analytics",
            items: [
                QuickResourceItem(
                    sessionID: sessionID,
                    sessionName: "analytics",
                    catalog: "main",
                    namespace: "public",
                    name: "orders",
                    kind: .table
                ),
                QuickResourceItem(
                    sessionID: sessionID,
                    sessionName: "analytics",
                    catalog: "main",
                    namespace: "public",
                    name: "orders_v",
                    kind: .view
                ),
                QuickResourceItem(
                    sessionID: sessionID,
                    sessionName: "analytics",
                    catalog: "main",
                    namespace: "public",
                    name: "orders_proc",
                    kind: .storedProcedure
                ),
            ],
            lastUpdated: Date()
        )

        let matches = QuickResourceMatcher.rankedMatches(
            query: "orders",
            in: index,
            scope: .view
        )

        #expect(matches.count == 1)
        #expect(matches.first?.item.kind == .view)
        #expect(matches.first?.item.name == "orders_v")
    }

    @Test
    func appliesStableOrderingForTies() throws {
        let index = QuickResourceIndex(
            sessionID: sessionID,
            sessionName: "analytics",
            items: [
                QuickResourceItem(
                    id: "a",
                    sessionID: sessionID,
                    sessionName: "analytics",
                    catalog: "main",
                    namespace: "public",
                    name: "orders_2023",
                    kind: .table
                ),
                QuickResourceItem(
                    id: "b",
                    sessionID: sessionID,
                    sessionName: "analytics",
                    catalog: "archive",
                    namespace: "public",
                    name: "orders_2023",
                    kind: .table
                ),
            ],
            lastUpdated: Date()
        )

        let matches = QuickResourceMatcher.rankedMatches(query: "orders_2023", in: index)

        #expect(matches.count == 2)
        #expect(matches.map(\.item.catalog) == ["archive", "main"])
    }
}
