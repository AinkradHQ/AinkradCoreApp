import CoreUI
import SwiftUI

/// One record beside its list (mockup 16, record): its area and place, how sure Brain is, where it comes from, how it
/// changed, and Forget (archived, never deleted). The files and sessions themselves are under Sources, What Brain read.
struct RecordDetail: View {
    let brain: BrainModel
    let record: BrainAreaRecordWire
    let area: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                if let a = BrainTab(rawValue: area) { chip(a.title) }
                chip(record.roomName)
                Spacer(minLength: Space.s2)
                if record.support > 1 { StateBadge("Sure", tone: .done, symbol: "checkmark") }
                CoreIconButton(symbol: "xmark", label: "Close") { brain.calm.picked = nil }
            }
            Text(record.body).coreFont(size: MacTextSize.title, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Text("Where it comes from").coreFont(size: MacTextSize.headline, weight: .semibold)
                .foregroundStyle(GlassInk.secondary)
            CoreRow(
                BrainWords.plural(record.support, "source", "sources"),
                subtitle: "Brain saw this \(record.support == 1 ? "once" : "\(record.support) times")",
                symbol: "doc.on.doc")
            CoreRow(record.roomName, subtitle: "The place it is kept in", symbol: "folder", action: openPlace) {
                Image(systemName: "chevron.right").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            }
            Text("How it changed").coreFont(size: MacTextSize.headline, weight: .semibold)
                .foregroundStyle(GlassInk.secondary)
            step(record.seenAt, "Last seen")
            step(record.createdAt, "First learned")
            HStack {
                Spacer()
                Button(role: .destructive) {
                    Task { await brain.calm.forget(record) }
                } label: {
                    Label("Forget this", systemImage: "trash")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .help("Take this out of memory. It is archived, never deleted.")
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-record-detail")
    }

    private func chip(_ text: String) -> some View {
        Text(text).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
            .lineLimit(1)
            .padding(.horizontal, Space.s2).padding(.vertical, 2)
            .background(GlassInk.well, in: coreShape(Radius.chip))
    }

    private func step(_ iso: String, _ what: String) -> some View {
        HStack(spacing: Space.s3) {
            Text(ExploreEvidenceTab.when(iso)).foregroundStyle(GlassInk.secondary)
                .frame(width: Space.s8 * 3, alignment: .leading)
            Text(what)
        }
        .coreFont(size: MacTextSize.meta)
    }

    private func openPlace() {
        brain.view(record.room)
        brain.go(.rooms)
        brain.placeOpen = true
        Task { await brain.inspect(record.room) }
    }
}
