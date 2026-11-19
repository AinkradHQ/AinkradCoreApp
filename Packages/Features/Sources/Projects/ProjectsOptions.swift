import CoreUI
import Foundation
import SwiftUI

/// The first API minor of Core 0.10 (the same number as the Core page's `CoreMinor.v010`).
enum ProjectsMinor { static let v010: Int32 = 95 }

/// What a run gets unless a project says otherwise: the Core's `GET/PUT /api/v1/projects/defaults`. Saving sets every project.
struct ProjectLimits: Equatable, Sendable {
    var cpus: Double
    var memoryMb: Int64
    var idleMinutes: Int
    var idleNever: Bool

    /// The Core's own defaults until something is saved.
    static let standard = ProjectLimits(cpus: 2, memoryMb: 4096, idleMinutes: 30, idleNever: false)

    private struct Wire: Codable {
        var cpu_limit: Double
        var mem_limit_mb: Int64
        var idle_minutes: Int
        var idle_never: Bool
    }

    static func decode(_ data: Data) throws -> ProjectLimits {
        let w = try JSONDecoder().decode(Wire.self, from: data)
        return ProjectLimits(cpus: w.cpu_limit, memoryMb: w.mem_limit_mb, idleMinutes: w.idle_minutes, idleNever: w.idle_never)
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(
            Wire(cpu_limit: cpus, mem_limit_mb: memoryMb, idle_minutes: idleMinutes, idle_never: idleNever))
    }
}

/// Settings, Apps, Projects, Options (E2-4): what a project may use while it runs (on the Core), whether the gallery lists
/// archived projects, and where opening a project shows it (both kept per Mac).
@MainActor enum ProjectsOptions {
    static var options: AppOptions { .shared("projects") }
    static let showArchivedKey = "showArchived"
    static let openInKey = "openIn"

    static var showArchived: Bool { options.bool(showArchivedKey, false) }
    static var openIn: OpenIn { OpenIn(rawValue: options.string(openInKey, OpenIn.newWorkspace.rawValue)) ?? .newWorkspace }

    enum OpenIn: String, CaseIterable {
        case newWorkspace = "new", thisWorkspace = "this"
        var title: String { self == .newWorkspace ? "A new workspace" : "This workspace" }
    }

    static let cores = [1, 2, 4, 8]
    static let memoryGB = [1, 2, 4, 8]

    /// "Stop when nobody visits": the minutes each choice means; 0 is Never.
    static let idleChoices: [(minutes: Int, title: String)] = [
        (15, "After 15 min"), (30, "After 30 min"), (120, "After 2 hours"), (0, "Never"),
    ]

    /// The picked choice for limits the Core holds: a value the menu has no row for (set from elsewhere) shows as the nearest
    /// choice at or above it.
    static func idleChoice(_ l: ProjectLimits) -> Int {
        if l.idleNever { return 0 }
        return idleChoices.dropLast().first { $0.minutes >= l.idleMinutes }?.minutes ?? 120
    }

    static func setIdle(_ l: ProjectLimits, minutes: Int) -> ProjectLimits {
        var l = l
        l.idleNever = minutes == 0
        if minutes > 0 { l.idleMinutes = minutes }
        return l
    }

    static func coreChoice(_ l: ProjectLimits) -> Int { cores.first { Double($0) >= l.cpus } ?? 8 }
    static func memoryChoice(_ l: ProjectLimits) -> Int { memoryGB.first { Int64($0) * 1024 >= l.memoryMb } ?? 8 }
}

struct ProjectsOptionsTab: View {
    @Environment(\.coreAccent) private var paneAccent
    let model: ProjectsModel
    let options = ProjectsOptions.options

    var body: some View {
        VStack(spacing: Space.s4) {
            GlassSection("When a project runs", symbol: "play.circle", hue: GlassInk.accent(paneAccent)) {
                VStack(spacing: Space.s2) {
                    if let l = model.limits {
                        OptionSelectRow(
                            "Processor", sub: "The most a project can use", symbol: "cpu",
                            selection: Binding(
                                get: { ProjectsOptions.coreChoice(l) },
                                set: { n in model.saveLimits { $0.cpus = Double(n) } }),
                            options: ProjectsOptions.cores.map { CoreSelectOption($0, $0 == 1 ? "1 core" : "\($0) cores") })
                        OptionSelectRow(
                            "Memory", sub: "The most a project can use", symbol: "memorychip",
                            selection: Binding(
                                get: { ProjectsOptions.memoryChoice(l) },
                                set: { g in model.saveLimits { $0.memoryMb = Int64(g) * 1024 } }),
                            options: ProjectsOptions.memoryGB.map { CoreSelectOption($0, "\($0) GB") })
                        OptionSelectRow(
                            "Stop when nobody visits", sub: "Saves power on your server", symbol: "moon.zzz",
                            selection: Binding(
                                get: { ProjectsOptions.idleChoice(l) },
                                set: { m in model.saveLimits { $0 = ProjectsOptions.setIdle($0, minutes: m) } }),
                            options: ProjectsOptions.idleChoices.map { CoreSelectOption($0.minutes, $0.title) })
                    } else {
                        Text(model.limitsNote).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    }
                }
            }
            GlassSection("Tidying", symbol: "archivebox", hue: GlassInk.accent(paneAccent), index: 1) {
                VStack(spacing: Space.s2) {
                    OptionSwitchRow(
                        "Show archived projects", sub: "Archived projects keep their repos, secrets and notes",
                        symbol: "archivebox",
                        isOn: Binding(
                            get: { options.bool(ProjectsOptions.showArchivedKey, false) },
                            set: { on in
                                options.set(ProjectsOptions.showArchivedKey, on)
                                model.resync()
                            }))
                    OptionSelectRow(
                        "Open projects in", symbol: "rectangle.on.rectangle",
                        selection: options.text(ProjectsOptions.openInKey, ProjectsOptions.OpenIn.newWorkspace.rawValue),
                        options: ProjectsOptions.OpenIn.allCases.map { CoreSelectOption($0.rawValue, $0.title) })
                }
            }
        }
        .task { await model.loadLimits() }
    }
}
