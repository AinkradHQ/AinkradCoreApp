import CoreUI
import SwiftUI

/// The tool's reasoning, folded to one quiet italic line that opens to the text (Core API 95 stores Claude's thinking blocks).
struct ThinkingBlock: View {
    let text: String
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Button {
                withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) { open.toggle() }
            } label: {
                HStack(spacing: Space.s1) {
                    Image(systemName: "chevron.right").coreFont(size: MacTextSize.meta, weight: .semibold)
                        .rotationEffect(.degrees(open ? 90 : 0)).frame(width: Space.s3)
                    Text("Thought").coreFont(size: MacTextSize.body).italic()
                }
                .foregroundStyle(SessionInk.text2).frame(minHeight: 26).contentShape(Rectangle())
            }
            .buttonStyle(CoreQuietPressStyle(radius: Radius.control, scale: 0.99, hoverFill: true))
            .help(open ? "Hide what it thought" : "Show what it thought")
            if open {
                Text(text).coreFont(size: MacTextSize.body).italic().foregroundStyle(SessionInk.text2)
                    .lineSpacing(4).textSelection(.enabled)
                    .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                    .background(SessionInk.row, in: coreShape(Radius.row))
                    .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: -Space.s1)))
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Which file a code block is for: a path in the fence's info string (```swift Sources/A.swift, ```swift:Sources/A.swift,
/// ```swift title="Sources/A.swift"), else the last path written in the text before it. nil when neither names one.
enum CodeTarget {
    static func path(info: String, before: String?) -> String? {
        let tokens = info.split(whereSeparator: { " :=\"'`".contains($0) }).dropFirst()
        if let t = tokens.first(where: looksLikePath) { return String(t) }
        // `title=` style: the language is the first token, the rest may carry it.
        if let b = before {
            let words = b.split(whereSeparator: { $0.isWhitespace || "`'\"()[]:,".contains($0) })
            if let w = words.last(where: looksLikePath) { return String(w).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        }
        return nil
    }

    /// A path has an extension or a slash, and is not a URL, a version or a bare number.
    static func looksLikePath(_ s: Substring) -> Bool {
        guard !s.contains("://"), !s.hasPrefix("//"), s.count > 2, s.count < 200 else { return false }
        if s.contains("/") { return s.first != "/" || s.count > 3 }
        guard let dot = s.lastIndex(of: "."), dot != s.startIndex else { return false }
        let ext = s[s.index(after: dot)...]
        return (1...5).contains(ext.count) && ext.allSatisfy { $0.isLetter || $0.isNumber } && ext.contains { $0.isLetter }
    }
}

/// The `@name` being typed at the end of a message: its folder and what is typed of the name.
struct MentionToken: Equatable {
    var dir: String
    var prefix: String
    /// The characters it takes up at the end of the text, `@` included.
    var length: Int

    static func at(end text: String) -> MentionToken? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        let rest = text[text.index(after: at)...]
        guard !rest.contains(where: { $0.isWhitespace }) else { return nil }
        // The @ starts a word: not the middle of an email.
        if at != text.startIndex, !text[text.index(before: at)].isWhitespace { return nil }
        let s = String(rest)
        let dir = s.contains("/") ? String(s[..<s.lastIndex(of: "/")!]) : ""
        let prefix = s.contains("/") ? String(s[s.index(after: s.lastIndex(of: "/")!)...]) : s
        return MentionToken(dir: dir, prefix: prefix, length: s.count + 1)
    }
}

/// The @ picker above the composer: the session's files, one folder at a time, folders first. Click or ⇥ takes one.
struct MentionPicker: View {
    let entries: [FolderEntry]
    let pick: Int
    let choose: (FolderEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.prefix(8).enumerated()), id: \.element.id) { i, e in
                Button { choose(e) } label: {
                    HStack(spacing: Space.s2) {
                        Image(systemName: e.dir ? "folder" : "doc").foregroundStyle(SessionInk.text2)
                            .frame(width: Space.s4)
                        Text(e.name + (e.dir ? "/" : "")).coreFont(size: MacTextSize.body, design: .monospaced)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Space.s3).frame(minHeight: MacSize.controlLg)
                    .background(i == pick ? SessionInk.hover : .clear, in: coreShape(Radius.control))
                    .contentShape(Rectangle())
                }
                .buttonStyle(CoreQuietPressStyle(radius: Radius.control, scale: 0.99, hoverFill: true))
            }
        }
        .padding(Space.s1).coreGlass(radius: Radius.row, interactive: false)
        .accessibilityLabel("Files")
    }
}

/// What Apply does with a code block: the model writes it to the path (asked for first when the block names none).
struct ApplyCode {
    var files: [String]
    var write: (_ path: String, _ code: String) -> Void
}

extension EnvironmentValues {
    @Entry var applyCode: ApplyCode? = nil
}
