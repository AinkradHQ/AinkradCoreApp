import Admin
import CoreKit
import Foundation

/// What the focused pages of details v2 do beyond what the model already did: several kinds (API 112), Running saved as one
/// change, and a permanent delete.
extension ProjectsModel {
    /// The kinds after a tap on `tapped`: several may be on, "Not software" only alone, and at least one stays on.
    static func toggled(_ kinds: [ProjectKind], _ tapped: ProjectKind) -> [ProjectKind] {
        if tapped == .other { return [.other] }
        var on = kinds.filter { $0 != .other }
        if let i = on.firstIndex(of: tapped) {
            if on.count > 1 { on.remove(at: i) }
        } else {
            on.append(tapped)
        }
        return ProjectKind.allCases.filter(on.contains)
    }

    /// A tap on a type tile. A Core with API 112 keeps the list; an older one keeps the one kind, the tile tapped.
    func tapKind(_ tapped: ProjectKind, for p: ProjectItem) {
        guard core112 else {
            setKind(tapped, for: p)
            return
        }
        let next = Self.toggled(p.allKinds, tapped)
        guard next != p.allKinds else { return }
        Task { await change(p, ProjectPatch(kinds: next.map(\.rawValue)), why: "Change what \(p.name) is.") }
    }

    /// Runner, CPU, memory and idle stop as one change, so Save asks for Touch ID once. Empty when nothing differs.
    static func runningPatch(from project: ProjectItem, runner: String, limits: ProjectLimits) -> ProjectPatch {
        var p = limitsPatch(from: project.limits, to: limits)
        if runner != project.runner { p.runner = runner }
        return p
    }

    func saveRunning(_ p: ProjectItem, runner: String, limits: ProjectLimits) async -> Bool {
        let patch = Self.runningPatch(from: p, runner: runner, limits: limits)
        return await change(p, patch, why: "Change where and how \(p.name) runs.")
    }

    /// Deletes the project for good (API 112): archived first when it is not, then deleted, behind one Touch ID.
    func deleteForever(_ p: ProjectItem) async {
        guard core112, let service, !busy, mayWrite() else { return }
        busy = true
        defer { busy = false }
        do {
            try await host.elevated(
                "Delete \(p.name) for good, with its copies and runs.", done: "deleted", keepsEdit: false
            ) {
                if !p.archived { try await service.archive(project: p.id) }
                try await service.delete(project: p.id)
            }
        } catch is AdminDeclined {
            return
        } catch {
            host.shell.showToast(runWords(error), kind: .warn)
            return
        }
        closeProject()
        host.shell.closePane(Self.paneID(p.id))
        await reload()
        host.shell.showToast("\(p.name) deleted")
    }
}

/// Builds as the Builds page lists them: the run history grouped by day, newest first.
struct BuildDay: Equatable {
    let title: String
    let runs: [RunRecord]
}

enum BuildWords {
    static func days(_ runs: [RunRecord], failedOnly: Bool, now: Date, calendar: Calendar = .current) -> [BuildDay] {
        let kept = runs.filter { !failedOnly || $0.state == "failed" }
            .sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
        var out: [BuildDay] = []
        var order: [Date] = []
        var by: [Date: [RunRecord]] = [:]
        for r in kept {
            let d = calendar.startOfDay(for: r.startedAt ?? now)
            if by[d] == nil { order.append(d) }
            by[d, default: []].append(r)
        }
        for d in order {
            let title: String
            if calendar.isDate(d, inSameDayAs: now) {
                title = "Today"
            } else if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(d, inSameDayAs: y) {
                title = "Yesterday"
            } else {
                title = d.formatted(.dateTime.day().month(.abbreviated))
            }
            out.append(BuildDay(title: title, runs: by[d] ?? []))
        }
        return out
    }

    /// "3 min 12 s", "9 s", "1 h 4 min".
    static func duration(_ s: TimeInterval) -> String {
        let t = Int(max(0, s).rounded())
        if t < 60 { return "\(t) s" }
        if t < 3600 { return t % 60 == 0 ? "\(t / 60) min" : "\(t / 60) min \(t % 60) s" }
        return t % 3600 / 60 == 0 ? "\(t / 3600) h" : "\(t / 3600) h \(t % 3600 / 60) min"
    }

    /// "idle 4 min of 30" as the Core words it: (4, 30), or nil.
    static func idle(_ line: String?) -> (now: Int, of: Int)? {
        guard let line else { return nil }
        let n = line.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return n.count >= 2 ? (n[0], n[1]) : nil
    }
}
