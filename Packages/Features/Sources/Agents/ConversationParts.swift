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
                .coreFont(size: MacTextSize.meta + 1, design: .monospaced).foregroundStyle(SessionInk.text2)
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
                withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) { expanded.toggle() }
            } label: {
                // The same quiet line as every tool step: icon, verb, file, +/−, time and its mark.
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Image(systemName: "pencil").coreFont(size: MacTextSize.body).foregroundStyle(SessionInk.text2)
                        .frame(width: Space.s4)
                    Text(name.lowercased() == "write" ? "Wrote" : "Edited").coreFont(size: MacTextSize.body)
                        .foregroundStyle(SessionInk.text2)
                    Text(PathWords.short(path)).coreFont(size: 12, design: .monospaced).foregroundStyle(SessionInk.text)
                        .lineLimit(1).truncationMode(.middle)
                    Text("+\(add)").foregroundStyle(palette.tone(.run).ink).monospacedDigit()
                    Text("−\(del)").foregroundStyle(palette.tone(.fail).ink).monospacedDigit()
                    if let ms {
                        Text(coreUnit(coreDecimal(Double(ms) / 1000, 1), "s")).foregroundStyle(SessionInk.text2)
                            .monospacedDigit()
                    }
                    switch ok {
                    case true?:
                        Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(palette.primary)
                            .accessibilityLabel("Done")
                    case false?:
                        Image(systemName: "xmark").fontWeight(.semibold).foregroundStyle(palette.tone(.fail).ink)
                            .accessibilityLabel("Failed")
                    case nil: CoreWorkingBar(width: Space.s8)
                    }
                    Spacer(minLength: 0)
                }
                .coreFont(size: MacTextSize.meta).padding(.horizontal, Space.s2).frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(CoreQuietPressStyle(radius: Radius.control, scale: 0.99, hoverFill: true)).help(path)
            if expanded {
                DiffBlock(lines: lines).padding([.horizontal, .bottom], Space.s2)
                    .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: -Space.s1)))
            }
        }
        .foregroundStyle(palette.text)
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
                Text("Tasks").coreFont(size: MacTextSize.body, weight: .semibold)
                Text("\(done) of \(items.count)").coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
                    .monospacedDigit()
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Image(systemName: symbol(t.status)).foregroundStyle(
                        t.status == .pending ? SessionInk.text2 : GlassInk.blue
                    )
                    .frame(width: 16)
                    Text(t.text).strikethrough(t.status == .completed).foregroundStyle(
                        t.status == .completed ? SessionInk.text2 : GlassInk.primary)
                }
                .coreFont(size: MacTextSize.body)
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .sessionSurface(radius: Radius.cardMac)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tasks, \(done) of \(items.count) done")
    }

    private func symbol(_ s: TodoItem.Status) -> String {
        switch s {
        case .completed: "checkmark.square.fill"
        case .inProgress: "square.inset.filled"
        case .pending: "square"
        }
    }
}
