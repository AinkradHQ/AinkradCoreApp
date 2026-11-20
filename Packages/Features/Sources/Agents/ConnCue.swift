import CoreUI
import SwiftUI

/// CN5: an agent's call through a Core connection (the runner's typed tools, `github.get_issue`, `jira.create_issue`) as
/// one quiet line in the transcript; a refused one as a warning line with the way to allow it. Names only, never payloads.
struct ConnCue: View {
    @Environment(\.coreAccent) private var paneAccent
    let tool: String
    let summary: String
    /// nil while it runs.
    let ok: Bool?
    let why: String
    var openConnections: (() -> Void)?

    nonisolated static let kinds = ["github": "GitHub", "jira": "Jira", "linear": "Linear", "slack": "Slack"]

    /// The service of a connection tool, or nil for any other tool.
    nonisolated static func kind(_ tool: String) -> String? {
        let p = tool.split(separator: ".", maxSplits: 1)
        return p.count == 2 ? kinds[p[0].lowercased()] : nil
    }

    /// `github.get_issue` + `#142` → `Get issue #142 with GitHub`.
    nonisolated static func line(_ tool: String, _ summary: String, done: Bool = false) -> String {
        let op =
            tool.split(separator: ".", maxSplits: 1).last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? tool
        var words = op.split(separator: " ").map(String.init)
        // Done reads in the past: "Got issue #142 from GitHub" (review 2026-11-16).
        if done, let v = words.first { words[0] = past(v) }
        let phrase = words.joined(separator: " ")
        let verb = phrase.prefix(1).uppercased() + phrase.dropFirst()
        let with = done && op.hasPrefix("get") ? "from" : "with"
        return "\(verb)\(summary.isEmpty ? "" : " \(summary)") \(with) \(kind(tool) ?? "a connection")"
    }

    /// Only the first letter: a provider's name keeps its capitals ("with GitHub", never "with github").
    nonisolated static func lowerFirst(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }

    /// The past tense of a connection verb: irregular ones by name, the rest with -ed.
    nonisolated static func past(_ verb: String) -> String {
        let irregular = ["get": "got", "read": "read", "send": "sent", "find": "found", "make": "made", "run": "ran"]
        if let p = irregular[verb.lowercased()] { return p }
        if verb.hasSuffix("e") { return verb + "d" }
        return verb + "ed"
    }

    var body: some View {
        let refused = ok == false
        HStack(spacing: Space.s2) {
            Image(systemName: refused ? "exclamationmark.triangle" : ok == nil ? "link" : "checkmark.circle")
                .foregroundStyle(refused ? GlassInk.amberInk : SessionInk.text2)
            Text(
                refused
                    ? "Couldn't \(Self.lowerFirst(Self.line(tool, summary)))\(why.isEmpty ? "" : ": \(why)")"
                    : Self.line(tool, summary, done: ok == true)
            )
            .coreFont(size: MacTextSize.meta).foregroundStyle(refused ? GlassInk.primary : SessionInk.text2)
            .lineLimit(2)
            if refused, let openConnections {
                Button("Allow in Connections", action: openConnections).buttonStyle(.plain)
                    .coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.accentInk(paneAccent))
            }
        }
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s1)
        .background(refused ? GlassInk.amber.opacity(0.12) : GlassInk.well, in: coreShape(Radius.control))
        .accessibilityElement(children: .combine)
    }
}
