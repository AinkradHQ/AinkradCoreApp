import CoreUI
import SwiftUI

/// CN5: an agent's call through a Core connection (the runner's typed tools, `github.get_issue`, `jira.create_issue`) as
/// one quiet line in the transcript; a refused one as a warning line with the way to allow it. Names only, never payloads.
struct ConnCue: View {
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
    nonisolated static func line(_ tool: String, _ summary: String) -> String {
        let op =
            tool.split(separator: ".", maxSplits: 1).last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? tool
        let verb = op.prefix(1).uppercased() + op.dropFirst()
        return "\(verb)\(summary.isEmpty ? "" : " \(summary)") with \(kind(tool) ?? "a connection")"
    }

    var body: some View {
        let refused = ok == false
        HStack(spacing: Space.s2) {
            Image(systemName: refused ? "exclamationmark.triangle" : ok == nil ? "link" : "checkmark.circle")
                .foregroundStyle(refused ? GlassInk.orange : GlassInk.secondary)
            Text(
                refused
                    ? "Couldn't \(Self.line(tool, summary).lowercased())\(why.isEmpty ? "" : ": \(why)")"
                    : Self.line(tool, summary)
            )
            .font(.system(size: MacTextSize.meta)).foregroundStyle(refused ? GlassInk.primary : GlassInk.secondary)
            .lineLimit(2)
            if refused, let openConnections {
                Button("Allow in Connections", action: openConnections).buttonStyle(.plain)
                    .font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(GlassInk.blue)
            }
        }
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s1)
        .background(refused ? GlassInk.orange.opacity(0.12) : GlassInk.well, in: coreShape(Radius.control))
        .overlay {
            coreShape(Radius.control).strokeBorder(
                refused ? GlassInk.orange.opacity(0.35) : GlassInk.wellEdge, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
