import CoreUI
import SwiftUI

struct DiffLine: Equatable, Identifiable {
    enum Kind { case context, added, removed }
    let id: Int
    let kind: Kind
    let number: Int?
    let text: String
}

enum DiffLines {
    /// The lines an edit removed and added, with up to two unchanged lines of context each side. Common first and last lines are
    /// context; the middle is removed, then added. ponytail: not an LCS diff; a moved line shows as removed and added.
    static func make(old: String, new: String) -> [DiffLine] {
        let a = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let b = new.isEmpty ? [] : new.components(separatedBy: "\n")
        var pre = 0
        while pre < a.count, pre < b.count, a[pre] == b[pre] { pre += 1 }
        var suf = 0
        while suf < a.count - pre, suf < b.count - pre, a[a.count - 1 - suf] == b[b.count - 1 - suf] { suf += 1 }
        var out: [DiffLine] = []
        func add(_ k: DiffLine.Kind, _ n: Int?, _ t: String) {
            out.append(DiffLine(id: out.count, kind: k, number: n, text: t))
        }
        for i in max(0, pre - 2)..<pre { add(.context, i + 1, a[i]) }
        for i in pre..<(a.count - suf) { add(.removed, i + 1, a[i]) }
        for i in pre..<(b.count - suf) { add(.added, i + 1, b[i]) }
        for i in (a.count - suf)..<min(a.count, a.count - suf + 2) { add(.context, i + 1 + b.count - a.count, a[i]) }
        return out
    }
}

/// An edit as a diff (Ahmed, 2026-11-15: no pill per line): one block, each line a full-width band with a quiet tint, its
/// number and a + or − sign (the meaning never rests on colour alone). Long lines wrap; long diffs fold after `fold` lines.
struct DiffBlock: View {
    let lines: [DiffLine]
    static let fold = 14
    @State private var all = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        let shown = all ? lines : Array(lines.prefix(Self.fold))
        VStack(alignment: .leading, spacing: 0) {
            if lines.isEmpty {
                // An edit the tool reported without its lines (a plain Edit/Write step).
                Text("The tool did not send the changed lines for this edit.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).padding(Space.s2)
            }
            ForEach(shown) { l in
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text(l.number.map(String.init) ?? "").frame(width: Space.s6, alignment: .trailing)
                        .foregroundStyle(palette.text2)
                    Text(sign(l.kind)).frame(width: Space.s2).foregroundStyle(
                        l.kind == .context ? palette.text2 : tint(l.kind))
                    Text(l.text.isEmpty ? " " : l.text)
                        .foregroundStyle(l.kind == .context ? palette.text2 : palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .coreFont(size: 12, design: .monospaced)
                .padding(.horizontal, Space.s2).padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                // A plain, square band flush with its neighbours: one block, rounded only at its outer corners
                // (Ahmed, 2026-11-16: "each line is corner rounded on its own").
                .background { Rectangle().fill(l.kind == .context ? .clear : tint(l.kind).opacity(0.12)) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    (l.kind == .added ? "Added: " : l.kind == .removed ? "Removed: " : "") + l.text)
            }
            if lines.count > Self.fold {
                Button(all ? "Show less" : "Show \(lines.count - Self.fold) more lines") { all.toggle() }
                    .buttonStyle(.plain).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.blueInk)
                    .padding(Space.s2)
            }
        }
        .textSelection(.enabled)
        .padding(.vertical, Space.s1)
        .background(GlassInk.sunk(0.22), in: coreShape(Radius.control))
        .clipShape(coreShape(Radius.control))
    }

    private func sign(_ k: DiffLine.Kind) -> String {
        switch k {
        case .added: "+"
        case .removed: "−"
        case .context: " "
        }
    }

    private func tint(_ k: DiffLine.Kind) -> Color { k == .added ? GlassInk.green : GlassInk.red }
}
