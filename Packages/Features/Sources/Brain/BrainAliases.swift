import CoreUI
import Observation
import SwiftUI

/// Settings, Apps, Brain: the rooms the Core files as another project ("Same project as…" in an import review, API minor
/// 72). Read from the Core each time; Remove forgets one, and the Core keeps the two rooms apart again.
@MainActor @Observable
final class SameProjectList {
    private let source: @MainActor () -> BrainRoutes?
    private(set) var aliases: [RoomAlias] = []
    var notice: String?

    init(routes: @escaping @MainActor () -> BrainRoutes?) { source = routes }

    func reload() async {
        guard let routes = source() else { return }
        aliases = (try? await routes.aliases()) ?? []
    }

    func remove(_ a: RoomAlias) async {
        guard let routes = source() else { return }
        notice = nil
        do { aliases = try await routes.removeAlias(a.from) } catch { notice = BrainWords.failure(error) }
    }
}

struct SameProjectSection: View {
    let list: SameProjectList

    /// Nothing remembered: no section at all. The owner reads the list (`.task` on an empty view never runs).
    var body: some View {
        if !list.aliases.isEmpty || list.notice != nil {
            GlassSection(
                "Same project", sub: "Rooms the Core files under another name.", symbol: "arrow.triangle.merge",
                hue: GlassInk.blue, index: 3
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    if let n = list.notice {
                        Text(n).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.red)
                    }
                    ForEach(list.aliases) { a in
                        CoreRow(a.from, subtitle: "Filed as \(a.to)", symbol: "folder") {
                            Button("Remove") { Task { await list.remove(a) } }
                                .buttonStyle(CoreButtonStyle(.plain, size: .small))
                                .help("Keep \(a.from) apart from \(a.to) from now on.")
                                .accessibilityLabel("Remove \(a.from) from \(a.to)")
                        }
                    }
                }
            }
            .accessibilityIdentifier("brain-same-project-settings")
        }
    }
}
