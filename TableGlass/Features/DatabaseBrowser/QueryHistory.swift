import Foundation

protocol QueryHistoryPersisting: Sendable {
    func load() -> [String]
    func save(_ entries: [String])
}

struct UserDefaultsQueryHistoryStore: QueryHistoryPersisting {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "com.tableglass.sqlHistory") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [String] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            return []
        }
    }

    func save(_ entries: [String]) {
        do {
            let data = try JSONEncoder().encode(entries)
            defaults.set(data, forKey: key)
        } catch {
            // Ignore persistence errors to avoid impacting UI.
        }
    }
}

actor DatabaseQueryHistory {
    private let capacity: Int
    private var entries: [String]
    private let persistence: QueryHistoryPersisting?

    init(
        capacity: Int = 5_000,
        initialEntries: [String] = [],
        persistence: QueryHistoryPersisting? = UserDefaultsQueryHistoryStore()
    ) {
        self.capacity = max(1, capacity)
        self.persistence = persistence
        self.entries = []

        let persisted = persistence?.load() ?? []
        append(contentsOf: persisted + initialEntries, shouldPersist: false)
        persist()
    }

    func append(_ sql: String) {
        append(sql, shouldPersist: true)
    }

    func append(contentsOf entries: [String]) {
        append(contentsOf: entries, shouldPersist: true)
    }

    func snapshot() -> [String] {
        synchronizeWithPersistence()
        return Array(entries.reversed())
    }

    func search(containing query: String) -> [String] {
        synchronizeWithPersistence()
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedQuery.isEmpty else {
            return snapshot()
        }

        return entries.reversed().filter { entry in
            entry.lowercased().contains(normalizedQuery)
        }
    }

    private func append(_ sql: String, shouldPersist: Bool) {
        if shouldPersist {
            synchronizeWithPersistence()
        }
        let normalized = normalize(sql)
        guard !normalized.isEmpty else { return }
        if entries.last == normalized {
            return
        }

        var updated = entries
        updated.append(normalized)
        if updated.count > capacity {
            updated.removeFirst(updated.count - capacity)
        }
        entries = updated

        if shouldPersist {
            persist()
        }
    }

    private func append(contentsOf entries: [String], shouldPersist: Bool) {
        if shouldPersist {
            synchronizeWithPersistence()
        }
        var didChange = false
        for sql in entries {
            let before = self.entries
            append(sql, shouldPersist: false)
            didChange = didChange || before != self.entries
        }
        if didChange && shouldPersist {
            persist()
        }
    }

    private func persist() {
        persistence?.save(entries)
    }

    private func synchronizeWithPersistence() {
        guard let persistence else { return }
        let persisted = persistence.load()
        guard !persisted.isEmpty else { return }
        entries = applyCapacity(to: persisted)
    }

    private func applyCapacity(to entries: [String]) -> [String] {
        if entries.count <= capacity {
            return entries
        }
        let excess = entries.count - capacity
        return Array(entries.dropFirst(excess))
    }

    private func normalize(_ sql: String) -> String {
        sql.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
