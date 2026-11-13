import CoreUI
import Foundation
import SwiftUI

/// A risky Code Mode operation the Core holds until you decide (plan E6): `ainkrad.<operation>` with a sentence of what it will
/// change, the arguments the AI session passed (secrets already redacted by the Core, long texts cut) and why it needs you.
public struct CodeModeAsk: Equatable, Sendable {
    public struct Arg: Equatable, Sendable, Identifiable {
        public var key: String
        public var value: String
        public var id: String { key }
        /// The Core's redaction mark: shown as a chip, never as text.
        public var hidden: Bool { value.lowercased().contains("redacted") }
        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }
    public var summary: String
    public var args: [Arg]
    public var reason: String
    public init(summary: String, args: [Arg], reason: String) {
        self.summary = summary
        self.args = args
        self.reason = reason
    }

    private static func json(_ v: Any) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys]) else { return "\(v)" }
        return String(data: d, encoding: .utf8) ?? "\(v)"
    }

    /// Reads the request's `input` when it is the Core's JSON `{summary, args, reason}`; any other text is not a Code Mode card.
    static func parse(_ input: String) -> CodeModeAsk? {
        guard let data = input.data(using: .utf8),
            let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            o["summary"] != nil || o["args"] != nil
        else { return nil }
        let args = (o["args"] as? [String: Any] ?? [:]).keys.sorted().map { k -> Arg in
            let v = (o["args"] as? [String: Any])?[k]
            let text: String =
                switch v {
                case let s as String: s
                case let n as NSNumber: n.stringValue
                case let v?: json(v)
                default: ""
                }
            return Arg(key: k, value: text)
        }
        return CodeModeAsk(summary: o["summary"] as? String ?? "", args: args, reason: o["reason"] as? String ?? "")
    }
}

extension ApprovalRequest {
    /// The operation id when this is a Core-held Code Mode write (`ainkrad.brainAiPropose` is `brainAiPropose`).
    public var codeModeOp: String? { tool.hasPrefix("ainkrad.") ? String(tool.dropFirst("ainkrad.".count)) : nil }
    public var codeMode: CodeModeAsk? { codeModeOp == nil ? nil : CodeModeAsk.parse(input) }
    /// What a decided or expired line says: the sentence of a Code Mode ask, else the command or file.
    public var shownInput: String { codeMode?.summary ?? input }
}

/// What a Code Mode approval will do, as one block in place of a command well: the sentence, the arguments one per line, and
/// why it asks. It is the same on the inbox card and on the transcript card.
struct CodeModeAskView: View {
    let ask: CodeModeAsk
    var compact = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if !ask.summary.isEmpty {
                Text(ask.summary).coreFont(size: MacTextSize.body, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !ask.args.isEmpty {
                VStack(alignment: .leading, spacing: Space.s1) {
                    ForEach(ask.args.prefix(compact ? 5 : 8)) { a in
                        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                            Text(a.key.replacingOccurrences(of: "_", with: " "))
                                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                                .frame(width: Space.s8 * 2, alignment: .leading).lineLimit(1)
                            if a.hidden {
                                Label("Hidden", systemImage: "lock.fill")
                                    .coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(palette.text2)
                                    .padding(.horizontal, Space.s2).padding(.vertical, 1)
                                    .background(GlassInk.well, in: coreShape(Radius.control))
                                    .help("The Core hides this value, so it is not shown here.")
                            } else {
                                Text(a.value).coreFont(size: MacTextSize.meta, design: .monospaced)
                                    .lineLimit(compact ? 1 : 3).truncationMode(.tail).textSelection(.enabled)
                                    .help(a.value)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    if ask.args.count > (compact ? 5 : 8) {
                        Text("and \(ask.args.count - (compact ? 5 : 8)) more").coreFont(size: MacTextSize.meta)
                            .foregroundStyle(palette.text2)
                    }
                }
                .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                .background(GlassInk.sunk(0.25), in: coreShape(Radius.control))
            }
            if !ask.reason.isEmpty {
                Label(ask.reason, systemImage: "info.circle").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
