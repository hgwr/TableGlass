import Combine
import Foundation

@MainActor
final class QuickResourcePaletteViewModel: ObservableObject {
    @Published var isPresented: Bool = false
    @Published var searchText: String = ""
    @Published var selectedScope: QuickResourceKind?
    @Published private(set) var matches: [QuickResourceMatch] = []
    @Published private(set) var isRefreshingMetadata: Bool = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isIndexEmpty: Bool = false

    private let browserViewModel: DatabaseBrowserViewModel
    private var indices: [UUID: QuickResourceIndex] = [:]
    private var searchTask: Task<Void, Never>?
    private var followUpRefreshTask: Task<Void, Never>?
    private let metadataMaximumAge: TimeInterval = 60 * 3
    private let resultLimit = 60

    init(browserViewModel: DatabaseBrowserViewModel) {
        self.browserViewModel = browserViewModel
    }

    func present() {
        if isPresented {
            Task { await refreshIndices() }
            return
        }
        isPresented = true
        searchText = ""
        scheduleSearch()
        Task { await refreshIndices() }
    }

    func dismiss() {
        isPresented = false
        matches = []
        followUpRefreshTask?.cancel()
        searchTask?.cancel()
    }

    func refreshIndices() async {
        isRefreshingMetadata = true
        let fetched = await browserViewModel.quickResourceIndices(maximumAge: metadataMaximumAge)
        indices = Dictionary(uniqueKeysWithValues: fetched.map { ($0.sessionID, $0) })
        lastUpdated = fetched.map(\.lastUpdated).max()
        isIndexEmpty = fetched.flatMap(\.items).isEmpty
        let sessionRefreshing = browserViewModel.sessions.contains { $0.isRefreshing }
        isRefreshingMetadata = sessionRefreshing
        scheduleFollowUpRefreshIfNeeded(isRefreshing: sessionRefreshing)
        await MainActor.run {
            updateResults()
        }
    }

    func scheduleSearch() {
        searchTask?.cancel()
        let currentQuery = searchText
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard let self else { return }
            await MainActor.run {
                if self.searchText == currentQuery {
                    self.updateResults()
                }
            }
        }
    }

    func handleScopeChange() {
        updateResults()
    }

    private func scheduleFollowUpRefreshIfNeeded(isRefreshing: Bool) {
        followUpRefreshTask?.cancel()
        guard isRefreshing, isPresented else { return }

        followUpRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, self.isPresented else { return }
            await self.refreshIndices()
        }
    }

    private func updateResults() {
        let mergedItems = indices.values.flatMap(\.items)
        let combinedIndex = QuickResourceIndex(
            sessionID: UUID(),
            sessionName: "combined",
            items: mergedItems,
            lastUpdated: lastUpdated ?? Date()
        )
        matches = QuickResourceMatcher.rankedMatches(
            query: searchText,
            in: combinedIndex,
            scope: selectedScope,
            limit: resultLimit
        )
    }
}
