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
    private var persistence: QueryHistoryPersisting?

    init(
        capacity: Int = 5_000,
        initialEntries: [String] = [],
        persistence: QueryHistoryPersisting? = nil
    ) {
        self.capacity = max(1, capacity)
        self.persistence = persistence
        self.entries = Self.mergedEntries(from: initialEntries, capacity: self.capacity)

        Task {
            await self.bootstrapFromPersistence(initialEntries: initialEntries)
        }
    }

    func append(_ sql: String) async {
        await append(sql, shouldPersist: true)
    }

    func append(contentsOf entries: [String]) async {
        await append(contentsOf: entries, shouldPersist: true)
    }

    func snapshot() async -> [String] {
        await synchronizeWithPersistence()
        return Array(entries.reversed())
    }

    func search(containing query: String) async -> [String] {
        await synchronizeWithPersistence()
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedQuery.isEmpty else {
            return Array(entries.reversed())
        }

        return entries.reversed().filter { entry in
            entry.lowercased().contains(normalizedQuery)
        }
    }

    private func append(_ sql: String, shouldPersist: Bool) async {
        if shouldPersist {
            await synchronizeWithPersistence()
        }

        var updated = entries
        let didChange = Self.applyAppend(sql, to: &updated, capacity: capacity)
        guard didChange else { return }

        entries = updated

        if shouldPersist {
            await persist()
        }
    }

    private func append(contentsOf entries: [String], shouldPersist: Bool) async {
        if shouldPersist {
            await synchronizeWithPersistence()
        }

        var updated = self.entries
        var didChange = false
        for sql in entries {
            didChange = Self.applyAppend(sql, to: &updated, capacity: capacity) || didChange
        }

        guard didChange else { return }
        self.entries = updated

        if shouldPersist {
            await persist()
        }
    }

    private func persist() async {
        guard let persistence = await resolvePersistence() else { return }
        let currentEntries = entries
        await MainActor.run {
            persistence.save(currentEntries)
        }
    }

    private func synchronizeWithPersistence() async {
        guard let persistence = await resolvePersistence() else { return }
        let persisted = await MainActor.run {
            persistence.load()
        }
        guard !persisted.isEmpty else { return }
        entries = Self.applyCapacity(to: persisted, capacity: capacity)
    }
}

private extension DatabaseQueryHistory {
    func bootstrapFromPersistence(initialEntries: [String]) async {
        guard let persistence = await resolvePersistence() else { return }
        let persisted = await MainActor.run {
            persistence.load()
        }
        guard !persisted.isEmpty else { return }

        let merged = Self.mergedEntries(from: persisted + initialEntries, capacity: capacity)
        guard merged != entries else { return }
        entries = merged
        await persist()
    }

    func resolvePersistence() async -> QueryHistoryPersisting? {
        if let persistence {
            return persistence
        }
        let store = await MainActor.run {
            UserDefaultsQueryHistoryStore()
        }
        persistence = store
        return store
    }

    static func mergedEntries(from entries: [String], capacity: Int) -> [String] {
        var merged: [String] = []
        for sql in entries {
            _ = applyAppend(sql, to: &merged, capacity: capacity)
        }
        return merged
    }

    @discardableResult
    static func applyAppend(_ sql: String, to entries: inout [String], capacity: Int) -> Bool {
        let normalized = normalize(sql)
        guard !normalized.isEmpty else { return false }
        if entries.last == normalized {
            return false
        }

        entries.append(normalized)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        return true
    }

    static func applyCapacity(to entries: [String], capacity: Int) -> [String] {
        if entries.count <= capacity {
            return entries
        }
        let excess = entries.count - capacity
        return Array(entries.dropFirst(excess))
    }

    static func normalize(_ sql: String) -> String {
        sql.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
