import Foundation
import TableGlassKit

struct QuickResourceIndex: Sendable {
    var sessionID: UUID
    var sessionName: String
    var items: [QuickResourceItem]
    var lastUpdated: Date
}

extension QuickResourceIndex {
    static func from(
        schema: DatabaseSchema,
        sessionID: UUID,
        sessionName: String,
        timestamp: Date = Date()
    ) -> QuickResourceIndex {
        let items = schema.catalogs.flatMap { catalog in
            catalog.namespaces.flatMap { namespace in
                tablesAndViews(
                    in: namespace,
                    catalogName: catalog.name,
                    sessionID: sessionID,
                    sessionName: sessionName
                ) + storedProcedures(
                    in: namespace,
                    catalogName: catalog.name,
                    sessionID: sessionID,
                    sessionName: sessionName
                )
            }
        }

        return QuickResourceIndex(
            sessionID: sessionID,
            sessionName: sessionName,
            items: items,
            lastUpdated: timestamp
        )
    }

    private static func tablesAndViews(
        in namespace: DatabaseNamespace,
        catalogName: String,
        sessionID: UUID,
        sessionName: String
    ) -> [QuickResourceItem] {
        let tables = namespace.tables.map {
            QuickResourceItem(
                sessionID: sessionID,
                sessionName: sessionName,
                catalog: catalogName,
                namespace: namespace.name,
                name: $0.name,
                kind: .table
            )
        }

        let views = namespace.views.map {
            QuickResourceItem(
                sessionID: sessionID,
                sessionName: sessionName,
                catalog: catalogName,
                namespace: namespace.name,
                name: $0.name,
                kind: .view
            )
        }

        return tables + views
    }

    private static func storedProcedures(
        in namespace: DatabaseNamespace,
        catalogName: String,
        sessionID: UUID,
        sessionName: String
    ) -> [QuickResourceItem] {
        namespace.procedures.map {
            QuickResourceItem(
                sessionID: sessionID,
                sessionName: sessionName,
                catalog: catalogName,
                namespace: namespace.name,
                name: $0.name,
                kind: .storedProcedure
            )
        }
    }
}

struct QuickResourceItem: Identifiable, Hashable, Sendable {
    let id: String
    let sessionID: UUID
    let sessionName: String
    let catalog: String
    let namespace: String
    let name: String
    let kind: QuickResourceKind
    let searchableText: String
    let searchableComponents: [String]

    init(
        id: String? = nil,
        sessionID: UUID,
        sessionName: String,
        catalog: String,
        namespace: String,
        name: String,
        kind: QuickResourceKind
    ) {
        self.sessionID = sessionID
        self.sessionName = sessionName
        self.catalog = catalog
        self.namespace = namespace
        self.name = name
        self.kind = kind
        self.id = id ?? "\(sessionID.uuidString)::\(kind.rawValue)::\(catalog).\(namespace).\(name)"

        let path = "\(catalog).\(namespace).\(name)"
        let components = [sessionName, catalog, namespace, name, kind.rawValue]
        self.searchableComponents = components.map { $0.lowercased() }
        self.searchableText = (components + [path]).joined(separator: " ").lowercased()
    }

    var pathDescription: String {
        "\(catalog).\(namespace).\(name)"
    }
}

enum QuickResourceKind: String, CaseIterable, Sendable {
    case table
    case view
    case storedProcedure

    var displayName: String {
        switch self {
        case .table:
            return "Table"
        case .view:
            return "View"
        case .storedProcedure:
            return "Stored Procedure"
        }
    }

    var systemImageName: String {
        switch self {
        case .table:
            return "tablecells"
        case .view:
            return "eye"
        case .storedProcedure:
            return "gearshape"
        }
    }

    var bias: Int {
        switch self {
        case .table:
            return 0
        case .view:
            return 10
        case .storedProcedure:
            return 14
        }
    }
}

struct QuickResourceMatch: Identifiable, Hashable, Sendable {
    let id: String
    let item: QuickResourceItem
    let score: QuickResourceScore
}

struct QuickResourceScore: Comparable, Hashable, Sendable {
    let alignmentPenalty: Int
    let prefixBonus: Int
    let wordBonus: Int
    let lengthPenalty: Int
    let kindBias: Int

    var sortValue: Int {
        alignmentPenalty
            + lengthPenalty
            + kindBias
            - prefixBonus
            - wordBonus
    }

    static func < (lhs: QuickResourceScore, rhs: QuickResourceScore) -> Bool {
        lhs.sortValue < rhs.sortValue
    }
}

enum QuickResourceMatcher {
    static func rankedMatches(
        query: String,
        in index: QuickResourceIndex,
        scope: QuickResourceKind? = nil,
        limit: Int = 50
    ) -> [QuickResourceMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()

        let candidates = index.items.filter { item in
            guard scope == nil || scope == item.kind else { return false }
            guard !normalized.isEmpty else { return true }
            return item.searchableText.contains(normalized)
        }

        guard !normalized.isEmpty else {
            let matches = candidates.map { item in
                QuickResourceMatch(
                    id: item.id,
                    item: item,
                    score: QuickResourceScore(
                        alignmentPenalty: 0,
                        prefixBonus: 0,
                        wordBonus: 0,
                        lengthPenalty: lengthPenalty(for: item),
                        kindBias: item.kind.bias
                    )
                )
            }

            return sortMatches(matches)
                .prefix(limit)
                .map { $0 }
        }

        let matches = candidates.compactMap { item in
            score(normalizedQuery: normalized, item: item)
        }

        return sortMatches(matches.map(\.match))
            .prefix(limit)
            .map { $0 }
    }
}

private extension QuickResourceMatcher {
    static func score(normalizedQuery: String, item: QuickResourceItem) -> (match: QuickResourceMatch, score: QuickResourceScore)? {
        let tokens = item.name
            .split { $0 == "_" || $0 == "." }
            .map { String($0).lowercased() }

        guard let alignment = bestAlignment(for: normalizedQuery, item: item, tokens: tokens) else {
            return nil
        }

        let prefixBonus = item.searchableText.hasPrefix(normalizedQuery) ? 30 : 0
        let wordBonus = wordMatchBonus(query: normalizedQuery, components: item.searchableComponents + tokens)
        let score = QuickResourceScore(
            alignmentPenalty: alignment,
            prefixBonus: prefixBonus,
            wordBonus: wordBonus,
            lengthPenalty: lengthPenalty(for: item),
            kindBias: item.kind.bias
        )

        return (
            QuickResourceMatch(id: item.id, item: item, score: score),
            score
        )
    }

    static func alignmentPenalty(for query: String, in target: String) -> Int? {
        var currentIndex = target.startIndex
        var penalty = 0

        for character in query {
            guard let foundIndex = target[currentIndex...].firstIndex(of: character) else {
                return nil
            }

            penalty += target.distance(from: currentIndex, to: foundIndex)
            currentIndex = target.index(after: foundIndex)
        }

        return penalty
    }

    static func bestAlignment(for query: String, item: QuickResourceItem, tokens: [String]) -> Int? {
        let targets = [
            item.name.lowercased(),
            item.pathDescription.lowercased(),
            item.searchableText
        ] + tokens

        return targets.compactMap { alignmentPenalty(for: query, in: $0) }.min()
    }

    static func wordMatchBonus(query: String, components: [String]) -> Int {
        if components.contains(query) {
            return 40
        }

        if components.contains(where: { $0.hasPrefix(query) }) {
            return 20
        }

        return 0
    }

    static func lengthPenalty(for item: QuickResourceItem) -> Int {
        max(0, item.searchableText.count / 12)
    }

    static func sortMatches(_ matches: [QuickResourceMatch]) -> [QuickResourceMatch] {
        matches.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score < rhs.score
            }

            if lhs.item.sessionName.caseInsensitiveCompare(rhs.item.sessionName) != .orderedSame {
                return lhs.item.sessionName.lowercased() < rhs.item.sessionName.lowercased()
            }

            if lhs.item.pathDescription.caseInsensitiveCompare(rhs.item.pathDescription) != .orderedSame {
                return lhs.item.pathDescription.lowercased() < rhs.item.pathDescription.lowercased()
            }

            if lhs.item.kind != rhs.item.kind {
                return lhs.item.kind.rawValue < rhs.item.kind.rawValue
            }

            return lhs.item.id < rhs.item.id
        }
    }
}
