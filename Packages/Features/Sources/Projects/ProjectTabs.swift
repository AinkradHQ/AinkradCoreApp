import CoreUI
import SwiftUI

/// Small views the rail tabs share (Core 0.10, E11-3): the stat tile, the usage sparkline, who-changed-what, and the Brain
/// records of the project's place. Numbers come from `ProjectInsightsModel`; a missing one is drawn as "–", never guessed.
struct InsightTile: View {
    let title: String
    let value: String
    let line: String
    var spark: [Double]?
    var meter: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title).foregroundStyle(GlassInk.secondary)
            Text(value).coreFont(size: MacTextSize.title, weight: .semibold)
            Text(line).foregroundStyle(GlassInk.secondary).lineLimit(1)
            if let spark, !spark.isEmpty { CoreSpark(spark).frame(height: Space.s4) }
            if let meter { CoreMeter(meter, low: false, label: title).frame(height: Space.s2) }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, minHeight: Space.s8 * 3, alignment: .topLeading)
        .coreCard(GlassInk.well, radius: Radius.cardMac)
        .accessibilityElement(children: .combine)
    }
}

/// "Who changed what": commits by author as bars, then the newest changes. Sessions and people sit in one list.
struct ChangesCard: View {
    let insights: ProjectInsightsModel
    let now: Date

    var body: some View {
        Island(title: "Who changed what", sub: "This week") {
            if let c = insights.changes {
                VStack(alignment: .leading, spacing: Space.s2) {
                    if c.byAuthor.isEmpty && c.recent.isEmpty {
                        Text("No changes yet.").foregroundStyle(GlassInk.secondary)
                    }
                    let top = Double(c.byAuthor.map(\.count).max() ?? 1)
                    ForEach(Array(c.byAuthor.prefix(4).enumerated()), id: \.offset) { _, a in
                        HStack(spacing: Space.s2) {
                            Text(a.who).lineLimit(1).frame(width: Space.s8 * 3, alignment: .leading)
                            CoreMeter(Double(a.count) / top, low: false, label: a.who)
                            Text("\(a.count)").monospacedDigit().foregroundStyle(GlassInk.secondary)
                        }
                    }
                    ForEach(c.recent.prefix(4)) { r in
                        HStack(spacing: Space.s2) {
                            Image(systemName: r.kind == "session" ? "sparkles" : "arrow.triangle.branch")
                                .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                            Text("\(r.who): \(r.summary)").lineLimit(1)
                            Spacer(minLength: 0)
                            Text(runsAgo(r.at, now: now)).foregroundStyle(GlassInk.secondary)
                        }
                    }
                }
            } else {
                Text("Loading…").foregroundStyle(GlassInk.secondary)
            }
        }
        .task { await insights.loadChanges() }
    }
}

/// A Brain record as one quiet row: its kind and its text, plain.
struct KnownRow: View {
    let r: KnownRecord
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Image(systemName: "externaldrive").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            Text(r.body).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            StateBadge(r.kind.isEmpty ? "Note" : r.kind.capitalized, tone: .queue, symbol: "circle")
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .coreCard(GlassInk.well, radius: Radius.row)
    }
}
