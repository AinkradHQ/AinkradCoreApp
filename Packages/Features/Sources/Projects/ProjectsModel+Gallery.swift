import Foundation

/// The gallery's switch in the header.
enum GallerySegment: String, CaseIterable, Sendable { case all, running, archived }

/// What the gallery shows: the segment, the Filter field, and the cursor's steps.
extension ProjectsModel {
    /// Every project the segment starts from.
    var segmentProjects: [ProjectItem] {
        switch segment {
        case .all: return projects
        case .running: return projects.filter { !$0.archived && isRunningOrStarting($0) }
        case .archived:
            var seen = Set<Int64>()
            return (projects.filter(\.archived) + archivedList).filter { seen.insert($0.id).inserted }
        }
    }

    func count(_ s: GallerySegment) -> Int {
        switch s {
        case .all: projects.count
        case .running: projects.filter { !$0.archived && isRunningOrStarting($0) }.count
        case .archived: Set(projects.filter(\.archived).map(\.id) + archivedList.map(\.id)).count
        }
    }

    /// The gallery's cards: the segment, then the Filter field (name, link name, kind, description and repo names).
    var shown: [ProjectItem] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let base = segmentProjects
        guard !q.isEmpty else { return base }
        return base.filter { p in
            p.name.lowercased().contains(q) || p.slug.contains(q) || p.description.lowercased().contains(q)
                || p.kind.title.lowercased().contains(q) || p.kind.short.lowercased().contains(q)
                || p.repos.contains { $0.name.lowercased().contains(q) }
        }
    }

    /// The cursor moves by `step` cards (one for left and right, a row for up and down) and stays on a card.
    func moveCursor(by step: Int) {
        let ids = shown.map(\.id)
        guard !ids.isEmpty else { return }
        let at = cursor.flatMap { ids.firstIndex(of: $0) }
        guard let at else {
            cursor = step > 0 ? ids[0] : ids[ids.count - 1]
            return
        }
        cursor = ids[min(max(at + step, 0), ids.count - 1)]
    }

    /// Esc in the gallery: clears the Filter first, then the cursor.
    func clearGalleryState() -> Bool {
        if !filter.isEmpty {
            filter = ""
            return true
        }
        if cursor != nil {
            cursor = nil
            return true
        }
        return false
    }

    /// The Filter says nothing matched: the plain words, with the typed text.
    var filterText: String { filter.trimmingCharacters(in: .whitespaces) }

    /// "Try copying again": every repo that failed, not one of them.
    func retryCopies(_ p: ProjectItem) {
        let failed = p.repos.filter { $0.copy.isFailed }
        guard !failed.isEmpty else { return }
        Task { await fetch(failed, in: p) }
    }

    /// A repo of the project could not be copied because GitHub is not connected (or the connection was refused).
    func copyNeedsConnection(_ p: ProjectItem) -> Bool {
        p.repos.contains { if case .failed(let why, _) = $0.copy { why.needsConnection } else { false } }
    }

    /// "4 min ago", for the stale notice.
    func listAge(now: Date = Date()) -> String? {
        guard let loadedAt else { return nil }
        let s = Int(now.timeIntervalSince(loadedAt))
        if s < 60 { return "a moment ago" }
        if s < 3600 { return "\(s / 60) min ago" }
        return "\(s / 3600) h ago"
    }
}
