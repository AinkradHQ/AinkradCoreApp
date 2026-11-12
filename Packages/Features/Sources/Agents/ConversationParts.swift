import CoreUI
import SwiftUI

/// Command output folded after a dozen lines, with the rest one click away.
struct FoldedOutput: View {
    let text: String
    static let fold = 12
    @State private var all = false

    var body: some View {
        let lines = text.components(separatedBy: "\n")
        let more = lines.count - Self.fold
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(all || more <= 0 ? text : lines.prefix(Self.fold).joined(separator: "\n"))
                .coreFont(size: 12, design: .monospaced).foregroundStyle(GlassInk.secondary)
            if more > 0 {
                Button(all ? "Show less" : "Show \(more) more lines") { all.toggle() }
                    .buttonStyle(.plain).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.blueInk)
            }
        }
    }
}

/// A file edit as a collapsible row that opens to a real diff (N42).
struct EditCard: View {
    let name: String
    let path: String
    let old: String
    let new: String
    let ok: Bool?
    let ms: Int?
    @Binding var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let lines = DiffLines.make(old: old, new: new)
        let add = lines.filter { $0.kind == .added }.count
        let del = lines.filter { $0.kind == .removed }.count
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if reduce { expanded.toggle() } else { withAnimation(.smooth(duration: 0.25)) { expanded.toggle() } }
            } label: {
                HStack(spacing: Space.s2) {
                    Image(systemName: "chevron.right").coreFont(size: 10, weight: .semibold)
                        .foregroundStyle(GlassInk.secondary).rotationEffect(.degrees(expanded ? 90 : 0)).frame(
                            width: 12)
                    Image(systemName: "pencil").foregroundStyle(GlassInk.blue).frame(width: 16)
                    Text(name.lowercased() == "write" ? "Wrote" : "Edited").coreFont(size: MacTextSize.body)
                    Text(PathWords.short(path)).coreFont(size: MacTextSize.body, design: .monospaced)
                        .lineLimit(1).truncationMode(.middle)
                    Text("+\(add)").foregroundStyle(GlassInk.green).monospacedDigit()
                    Text("−\(del)").foregroundStyle(GlassInk.red).monospacedDigit()
                    Spacer(minLength: Space.s2)
                    if let ms { Text("\(coreDecimal(Double(ms) / 1000, 1)) s").foregroundStyle(GlassInk.secondary) }
                    switch ok {
                    case true?: Image(systemName: "checkmark").foregroundStyle(GlassInk.green)
                    case false?: Image(systemName: "xmark").foregroundStyle(GlassInk.red)
                    case nil: ProgressView().controlSize(.small).scaleEffect(0.7)
                    }
                }
                .coreFont(size: MacTextSize.meta).padding(.horizontal, Space.s2).frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(path)
            if expanded {
                DiffBlock(lines: lines).padding([.horizontal, .bottom], Space.s2).transition(.opacity)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .background(GlassInk.well, in: coreShape(Radius.control + 2))
        .overlay { coreShape(Radius.control + 2).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .clipShape(coreShape(Radius.control + 2))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Edited \(path), \(add) added, \(del) removed")
    }
}

/// The CLI's todo list as a checklist.
struct TodoCard: View {
    let items: [TodoItem]

    var body: some View {
        let done = items.filter { $0.status == .completed }.count
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text("Plan").coreFont(size: MacTextSize.body, weight: .bold)
                Text("\(done) of \(items.count)").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .padding(.horizontal, Space.s2).background(GlassInk.well, in: coreShape(4))
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Image(systemName: symbol(t.status)).foregroundStyle(
                        t.status == .pending ? GlassInk.secondary : GlassInk.blue
                    )
                    .frame(width: 16)
                    Text(t.text).strikethrough(t.status == .completed).foregroundStyle(
                        t.status == .completed ? GlassInk.secondary : GlassInk.primary)
                }
                .coreFont(size: MacTextSize.body)
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plan, \(done) of \(items.count) done")
    }

    private func symbol(_ s: TodoItem.Status) -> String {
        switch s {
        case .completed: "checkmark.square.fill"
        case .inProgress: "square.inset.filled"
        case .pending: "square"
        }
    }
}

/// Between turns: a thin line with the time and what the turn cost.
struct TurnDivider: View {
    let at: Date
    let cost: Int64?
    let tokens: Int64?

    var body: some View {
        let bits = [
            at.formatted(date: .omitted, time: .shortened), AgentWords.cost(cost),
            tokens.map { "\(AgentWords.tokens($0)) tokens" },
        ]
        .compactMap { $0 }
        HStack(spacing: Space.s2) {
            coreShape(0.5).fill(GlassInk.track).frame(height: 1)
            Text("turn done · " + bits.joined(separator: " · ")).coreFont(size: MacTextSize.meta)
                .foregroundStyle(GlassInk.secondary).fixedSize().help(AgentWords.exactCost(cost) ?? "")
            coreShape(0.5).fill(GlassInk.track).frame(height: 1)
        }
        .padding(.vertical, Space.s2)
        .accessibilityElement(children: .combine)
    }
}
