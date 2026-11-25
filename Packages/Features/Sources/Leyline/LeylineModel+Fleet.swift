import CoreGraphics
import CoreUI
import Foundation

/// The page's state as the map, the list and the host panel read it: selection, the open group, arrow keys, typing to find,
/// and the live numbers (health, activity) the Core keeps.
extension LeylineModel {
    /// More hosts than `RouteLayout.bigFleet`: the map shows groups.
    var bigMap: Bool { fleet.count > RouteLayout.bigFleet }
    var mapGroups: [HostGroup] { HostGroup.grouping(fleet) }
    var listGroups: [HostGroup] { HostGroup.grouping(shown) }
    /// Hosts with an AI request waiting for a person.
    var approvalIDs: Set<String> { Set(extras.compactMap { $0.value.approval == nil ? nil : $0.key }) }
    /// Hosts that answered the Core's last check.
    var onlineCount: Int { fleet.filter { $0.reach?.up == true }.count }
    var selectedHost: HostItem? { hostItem(selected) }
    /// Hosts other hosts are reached through.
    var jumpIDs: Set<String> { Set(hosts.flatMap(\.jumpChain)) }

    func groupTitle(_ h: HostItem) -> String { h.group ?? HostGroup.shared }

    /// The group spread out on a big map: the one picked, else the selected host's, else the first.
    var currentGroup: String? {
        let titles = mapGroups.map(\.title)
        if let g = openGroup, titles.contains(g) { return g }
        return selectedHost.map(groupTitle) ?? titles.first
    }

    func select(_ id: String?) {
        selected = id
        if let h = hostItem(id) { openGroup = groupTitle(h) }
        if let id { Task { await loadActivity(id) } }
    }

    /// Opens a group on a big map and selects its first host that matches the find field.
    func showGroup(_ title: String) {
        openGroup = title
        if let h = mapGroups.first(where: { $0.title == title })?.hosts.first(where: matches) { select(h.id) }
    }

    /// The find field changed: the selection moves to the first match when it no longer matches.
    func filterChanged() {
        guard let first = shown.first else { return }
        if selectedHost.map(matches) != true { select(first.id) }
    }

    /// A letter typed with no field focused goes to the find field.
    func type(_ s: String) {
        filter += s
        filterChanged()
    }

    // MARK: arrow keys

    /// The map's card centres in grid steps (a column is 360 wide, a row 105 high): what ← → ↑ ↓ measure on a small map.
    var smallMapPoints: [String: CGPoint] {
        RouteLayout.place(fleet).mapValues { CGPoint(x: CGFloat($0.col + 1) * 360, y: CGFloat($0.row) * 105) }
    }

    /// Moves the selection; false when there is nowhere to go.
    @discardableResult
    func move(dx: Int, dy: Int) -> Bool {
        let before = selected
        switch layout {
        case .list:
            guard dy != 0 else { return false }
            select(FleetNav.step(listGroups.flatMap(\.hosts).map(\.id), from: selected, by: dy))
        case .map where bigMap:
            let titles = mapGroups.map(\.title)
            if dx != 0 {
                guard let g = FleetNav.step(titles, from: currentGroup, by: dx) else { return false }
                showGroup(g)
            } else {
                let ids = mapGroups.first { $0.title == currentGroup }?.hosts.filter(matches).map(\.id) ?? []
                select(FleetNav.step(ids, from: selected, by: dy))
            }
        case .map:
            let all = smallMapPoints
            let points = all.filter { id, _ in hostItem(id).map(matches) ?? false }
            let from = selected.flatMap { all[$0] } ?? CGPoint(x: 0, y: (all.values.map(\.y).max() ?? 0) / 2)
            guard let next = FleetNav.nearest(from: from, in: points.filter { $0.key != selected }, dx: dx, dy: dy)
            else { return false }
            select(next)
        }
        return selected != before
    }

    // MARK: live numbers

    /// Reads every host's stored health from the Core (a table read, nothing is probed), at most once a minute.
    func refreshHealth(force: Bool = false) async {
        guard let service, load == .ready else { return }
        if !force, let at = healthReadAt, Date().timeIntervalSince(at) < 60 { return }
        healthReadAt = Date()
        let ids = fleet.map(\.id)
        let read = await withTaskGroup(of: (String, HostHealth?).self) { group in
            for id in ids { group.addTask { (id, try? await service.health(host: id)) } }
            var out: [String: HostHealth] = [:]
            for await (id, h) in group { if let h, h.state != .unknown || h.memPct != nil { out[id] = h } }
            return out
        }
        healthByHost = read
    }

    /// The last three things that happened on a host, for its panel.
    func loadActivity(_ id: String) async {
        guard let service, let rows = try? await service.history(host: id) else { return }
        activity[id] = Array(rows.sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }.prefix(3))
    }

    // MARK: the embedded terminal

    /// The terminal the host view shows: the one opened before, else a new one (a terminal needs Touch ID).
    func terminal(for id: String) async throws -> String {
        if let t = hostTerminals[id] { return t }
        guard let service else { throw LeylineFailure.notYet }
        let name = hostItem(id)?.name ?? "the host"
        let t = try await host.elevated("Open a terminal on \(name).", done: "opened", keepsEdit: false) {
            try await service.openTerminal(host: id, rows: 30, cols: 100)
        }
        hostTerminals[id] = t
        watchRecording(terminal: t, host: id)
        return t
    }
}
