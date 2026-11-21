import CoreUI
import SwiftUI

/// Everything about one row: the sentence, then who, what, when and the details as plain pairs.
struct AuditDetail: View {
    let admin: AdminModel
    let item: AuditItem?
    @State private var technical = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let a = item {
                let area = AuditWords.area(a.action)
                let s = AuditWords.sentence(a, deviceName: { admin.deviceNames[$0] }) {
                    admin.registry.item($0).map(SettingWords.title)
                }
                IconTile(area.symbol, hue: area.hue, size: 44, bounce: a.seq)
                (Text(s.who).bold() + Text(" \(s.verb) ") + Text(s.what).bold())
                    .coreFont(size: MacTextSize.headline).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Space.s2) {
                    fact("clock.fill", AdminWords.whenExact(a.at))
                    fact(a.actor == .system ? "server.rack" : "person.fill", a.actor.label)
                    fact(area.symbol, area.title)
                    fact(
                        AuditWords.origin(a.origin).symbol,
                        "Started by: " + AuditWords.originSentence(a.origin, deviceName: { admin.deviceNames[$0] }))
                }
                let rows = AuditWords.detailRows(a, deviceName: { admin.deviceNames[$0] })
                let pairs = rows.plain
                if !pairs.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        ForEach(pairs, id: \.0) { k, v in
                            HStack(alignment: .firstTextBaseline) {
                                Text(k.replacingOccurrences(of: "_", with: " ").capitalized).foregroundStyle(
                                    GlassInk.secondary)
                                Spacer(minLength: Space.s2)
                                Text(v).coreFont(size: MacTextSize.body, design: .monospaced).textSelection(
                                    .enabled
                                )
                                .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(Space.s3)
                    .background(GlassInk.sunk(0.2), in: coreShape(Radius.control))
                }
                DisclosureGroup("Technical details", isExpanded: $technical) {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        ForEach(Array(rows.technical.enumerated()), id: \.offset) { _, kv in
                            HStack(alignment: .firstTextBaseline) {
                                Text(kv.0.capitalized).foregroundStyle(GlassInk.secondary)
                                Spacer(minLength: Space.s2)
                                Text(kv.1).coreFont(size: MacTextSize.meta, design: .monospaced)
                                    .textSelection(.enabled).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    .padding(.top, Space.s1)
                }
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .help("The ids, entry number and action code behind this row.")
            } else {
                Text("Pick a row to see everything about it.").foregroundStyle(GlassInk.secondary)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .topLeading)
        .coreWell()
        .animation(.smooth(duration: 0.25), value: item?.seq)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Row details")
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).foregroundStyle(GlassInk.primary)
    }
}

/// When things happened across the rows loaded: flat bars, the busiest slice tallest.
struct Activity: View {
    @Environment(\.coreAccent) private var paneAccent
    let cells: [Double]
    let from: Date
    let to: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, v in
                    coreShape(2)
                        .fill(v <= 0 ? GlassInk.track.opacity(0.5) : GlassInk.accent(paneAccent))
                        .frame(maxWidth: .infinity).frame(height: 4 + CGFloat(v) * 28)
                }
            }
            .frame(height: 32, alignment: .bottom)
            .accessibilityHidden(true)
            HStack {
                Text(from.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                Text("When things happened").fontWeight(.semibold)
                Spacer()
                Text(to.formatted(date: .abbreviated, time: .shortened))
            }
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rows over time, \(AdminWords.when(from)) to \(AdminWords.when(to))")
    }
}
