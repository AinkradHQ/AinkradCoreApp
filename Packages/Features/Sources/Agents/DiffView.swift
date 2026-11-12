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

/// An edit as a diff: file name, lines added and removed, the lines with their numbers. Long ones fold after `fold` lines.
struct DiffBlock: View {
    let lines: [DiffLine]
    static let fold = 14
    @State private var all = false

    var body: some View {
        let shown = all ? lines : Array(lines.prefix(Self.fold))
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(shown) { l in
                        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                            Text(l.number.map(String.init) ?? "").frame(width: 28, alignment: .trailing)
                                .foregroundStyle(l.kind == .context ? GlassInk.secondary : tint(l.kind))
                            Text(l.text.isEmpty ? " " : l.text).foregroundStyle(
                                l.kind == .context ? GlassInk.secondary : GlassInk.primary)
                            Spacer(minLength: 0)
                        }
                        .coreFont(size: 12, design: .monospaced)
                        .padding(.horizontal, Space.s2).padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(l.kind == .context ? .clear : tint(l.kind).opacity(0.18))
                    }
                }
                .fixedSize(horizontal: true, vertical: false).frame(minWidth: 0)
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

    private func tint(_ k: DiffLine.Kind) -> Color { k == .added ? GlassInk.green : GlassInk.red }
}
