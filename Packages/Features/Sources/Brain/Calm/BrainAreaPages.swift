import CoreUI
import SwiftUI

/// Me, Rules & preferences, Knowledge and Timeline (mockup 15): the Core's current records of the area, best supported first,
/// grouped the way the page reads. Only the important ones are shown; the search has everything. A record opens its detail
/// beside the list.
struct CalmArea: View {
    let brain: BrainModel
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    private var calm: BrainCalmModel { brain.calm }

    private var subtitle: String {
        switch calm.page {
        case .me: "Written by Brain from how you work. Changes itself as you do."
        case .rules: "Brain turns how you work into short rules and starts using them right away."
        case .knowledge: "The facts and decisions Brain is sure enough about to rely on."
        case .timeline: "Your work, told as it happened. Only what mattered."
        default: ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(calm.page.title).coreFont(size: MacTextSize.title, weight: .semibold)
                    Text(subtitle).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                }
                Spacer()
                if calm.page == .knowledge {
                    HStack(spacing: Space.s1) {
                        seg("Facts", "fact")
                        seg("Decisions", "decision")
                    }
                }
            }
            if calm.records.isEmpty {
                Text(calm.loading ? "Reading…" : "Nothing here yet. Brain fills this in as it learns.")
                    .foregroundStyle(GlassInk.secondary).padding(Space.s4)
                    .frame(maxWidth: .infinity, alignment: .leading).coreWell()
            } else {
                HStack(alignment: .top, spacing: Space.s4) {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(Array(calm.records.enumerated()), id: \.element.id) { i, r in
                                    CoreRow(
                                        r.body, subtitle: sub(r), symbol: Self.symbol(r.type),
                                        selected: calm.picked == r.id, action: { calm.picked = r.id }
                                    ) {
                                        if r.support > 1 { StateBadge("Sure", tone: .done, symbol: "checkmark") }
                                    }
                                    .coreRise(shown, min(i, 8))
                                }
                            }
                            .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: calm.records.map(\.id))
                        }
                        if calm.total > calm.records.count {
                            HStack(spacing: Space.s2) {
                                Text("Showing the \(calm.records.count) most important of \(calm.total).")
                                Button("See everything") {
                                    calm.searchArea = calm.page.area ?? ""
                                    brain.go(.records)
                                }
                                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                            }
                            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        }
                    }
                    if let r = calm.records.first(where: { $0.id == calm.picked }) {
                        RecordDetail(brain: brain, record: r, area: calm.page.area ?? "")
                            .frame(width: Space.s8 * 12)
                            .transition(.opacity)
                    }
                }
                .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: calm.picked)
            }
            if calm.areas?.lockedRooms ?? 0 > 0 {
                Text("\(BrainWords.plural(calm.areas?.lockedRooms ?? 0, "room", "rooms")) not shown until unlocked.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
        }
        .onAppear { shown = true }
        .accessibilityIdentifier("brain-area-page")
    }

    private func seg(_ title: String, _ type: String) -> some View {
        Button(title) { Task { await calm.setKnowledge(type) } }
            .buttonStyle(CoreButtonStyle(calm.knowledgeType == type ? .prominent : .secondary, size: .small))
    }

    private func sub(_ r: BrainAreaRecordWire) -> String {
        var s = r.roomName
        if r.support > 1 { s += " · seen \(r.support) times" }
        return s
    }

    static func symbol(_ type: String) -> String {
        switch type {
        case "rule": "checkmark.circle"
        case "preference": "heart"
        case "decision": "checkmark.seal"
        case "fact": "lightbulb"
        case "task": "circle.dashed"
        case "project-state": "clock"
        default: "text.alignleft"
        }
    }
}
