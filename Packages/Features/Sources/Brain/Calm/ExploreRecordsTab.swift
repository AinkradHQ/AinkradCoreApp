import CoreUI
import SwiftUI

/// Explore, Records: every current record across the open rooms, with a type filter and "Important only" (backed by at least
/// three sources). Evidence is the Rooms tab (a room's sources); history with Undo is the Activity tab.
struct ExploreRecordsTab: View {
    let brain: BrainModel
    @State private var type = ""
    @State private var important = false
    @State private var rows: [BrainAreaRecordWire] = []
    @State private var failure: String?

    private static let areas = ["me", "rules", "knowledge", "timeline"]
    private static let types = ["", "rule", "preference", "fact", "decision", "task", "project-state", "summary"]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                CoreSelect(
                    nil, selection: $type,
                    options: Self.types.map { CoreSelectOption($0, $0.isEmpty ? "All types" : $0.replacingOccurrences(of: "-", with: " ")) }
                )
                .frame(width: Space.s8 * 7)
                CoreCheckbox("Important only", isOn: $important)
                Spacer()
                Text(BrainWords.plural(shown.count, "record", "records")).coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary).monospacedDigit()
            }
            if let failure { Text(failure).foregroundStyle(GlassInk.secondary) }
            VStack(spacing: 2) {
                ForEach(shown) { r in
                    CoreRow(r.body, subtitle: "\(r.roomName) · \(r.type) · \(r.support) \(r.support == 1 ? "source" : "sources")",
                        symbol: CalmArea.symbol(r.type))
                        .transition(.opacity)
                }
            }
            .animation(Motion.out(Motion.ui), value: shown.map(\.id))
        }
        .task { await load() }
        .accessibilityIdentifier("brain-explore-records")
    }

    private var shown: [BrainAreaRecordWire] {
        rows.filter { (type.isEmpty || $0.type == type) && (!important || $0.support >= 3) }
    }

    private func load() async {
        guard let routes = brain.service?.importRoutes else { return }
        var all: [BrainAreaRecordWire] = []
        for a in Self.areas {
            do { all += try await routes.area(a, limit: 200).records } catch { failure = BrainWords.failure(error) }
        }
        rows = all.sorted { ($0.support, $0.seenAt) > ($1.support, $1.seenAt) }
    }
}
