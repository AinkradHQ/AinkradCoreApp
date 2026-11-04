import Foundation
import Observation

/// Settings, Security, Audit: a searchable, paged list of what was done, newest first. Only `kind`, `target` and `actor`
/// can be filtered; the Core pages by sequence (`before`).
@MainActor @Observable
final class AuditModel {
    static let pageSize = 50

    private(set) var items: [AuditItem] = []
    private(set) var nextBefore: Int64?
    var state: SectionState = .loading
    private(set) var loadingMore = false
    private(set) var moreError: String?
    var filter = AuditFilter() { didSet { if filter != oldValue { scheduleSearch() } } }
    var selected: Int64?
    @ObservationIgnored private var search: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private weak var hub: AdminModel?

    init(hub: AdminModel) { self.hub = hub }

    var selection: AuditItem? { selected.flatMap { s in items.first { $0.seq == s } } }
    var hasMore: Bool { nextBefore != nil }

    func reset() {
        items = []
        nextBefore = nil
        state = .loading
        selected = nil
    }

    /// Reads the first page again with the current filters.
    func reload() async {
        guard let hub, let service = hub.service else { return }
        generation += 1
        let mine = generation
        if items.isEmpty { state = .loading }
        do {
            let page = try await service.audit(before: nil, limit: Self.pageSize, filter: filter)
            guard mine == generation else { return }
            items = page.items
            nextBefore = page.nextBefore
            moreError = nil
            if let s = selected, !items.contains(where: { $0.seq == s }) { selected = nil }
            state = items.isEmpty && filter.isEmpty ? .empty : .ready
        } catch {
            guard mine == generation else { return }
            state = hub.state(for: error)
        }
    }

    func loadOlder() async {
        guard let hub, let service = hub.service, let before = nextBefore, !loadingMore else { return }
        loadingMore = true
        moreError = nil
        defer { loadingMore = false }
        let mine = generation
        do {
            let page = try await service.audit(before: before, limit: Self.pageSize, filter: filter)
            guard mine == generation else { return }
            items += page.items.filter { n in !items.contains { $0.seq == n.seq } }
            nextBefore = page.nextBefore
        } catch { moreError = hub.words(error) }
    }

    func clearFilters() { filter = AuditFilter() }

    /// A new search a moment after the last keystroke.
    private func scheduleSearch() {
        search?.cancel()
        search = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    func move(_ step: Int) {
        guard !items.isEmpty else { return }
        let i = selected.flatMap { s in items.firstIndex { $0.seq == s } } ?? (step > 0 ? -1 : items.count)
        selected = items[min(max(i + step, 0), items.count - 1)].seq
    }
}
