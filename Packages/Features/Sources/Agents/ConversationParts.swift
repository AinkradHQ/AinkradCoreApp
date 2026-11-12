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
                .coreFont(size: MacTextSize.meta + 1, design: .monospaced).foregroundStyle(GlassInk.secondary)
            if more > 0 {
                Button(all ? "Show less" : "Show \(more) more lines") { all.toggle() }
                    .buttonStyle(CoreButtonStyle(.plain, size: .small))
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
    @Environment(\.corePalette) private var palette

    var body: some View {
        let lines = DiffLines.make(old: old, new: new)
        let add = lines.filter { $0.kind == .added }.count
        let del = lines.filter { $0.kind == .removed }.count
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduce ? nil : Motion.out(Motion.ui)) { expanded.toggle() }
            } label: {
                HStack(spacing: Space.s2) {
                    Image(systemName: "chevron.right").coreFont(size: MacTextSize.meta, weight: .semibold)
                        .foregroundStyle(palette.text2).rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: Space.s3)
                    Image(systemName: "pencil").foregroundStyle(palette.primary).frame(width: Space.s4)
                    Text(name.lowercased() == "write" ? "Wrote" : "Edited").coreFont(size: MacTextSize.body)
                    Text(PathWords.short(path)).coreFont(size: MacTextSize.body, design: .monospaced)
                        .lineLimit(1).truncationMode(.middle)
                    Text("+\(add)").foregroundStyle(palette.tone(.run).ink).monospacedDigit()
                    Text("−\(del)").foregroundStyle(palette.tone(.fail).ink).monospacedDigit()
                    Spacer(minLength: Space.s2)
                    if let ms {
                        Text(coreUnit(coreDecimal(Double(ms) / 1000, 1), "s")).foregroundStyle(palette.text2)
                            .monospacedDigit()
                    }
                    switch ok {
                    case true?:
                        Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(palette.primary)
                            .accessibilityLabel("Done")
                    case false?:
                        Image(systemName: "xmark").fontWeight(.semibold).foregroundStyle(palette.tone(.fail).ink)
                            .accessibilityLabel("Failed")
                    case nil: WorkingBar(width: Space.s8)
                    }
                }
                .coreFont(size: MacTextSize.meta).padding(.horizontal, Space.s3).frame(minHeight: MacSize.controlLg)
                .contentShape(Rectangle())
            }
            .buttonStyle(ToolRowStyle()).help(path)
            if expanded {
                DiffBlock(lines: lines).padding([.horizontal, .bottom], Space.s2)
                    .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: -Space.s1)))
            }
        }
        .foregroundStyle(palette.text)
        .clipShape(coreShape(Radius.control))
        .coreWell(radius: Radius.control)
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
                Text("Plan").coreFont(size: MacTextSize.body, weight: .semibold)
                Text("\(done) of \(items.count)").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .monospacedDigit()
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
        .coreWell()
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
