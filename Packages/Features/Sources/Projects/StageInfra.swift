import CoreUI
import SwiftUI

/// The infrastructure stage: the project's services as a small map. The Core does not report how services connect, so the nodes
/// are laid out as a tree in the order the run lists them (the first is the entry) and the caption says so. While it runs,
/// small packets travel along the links and the health squares breathe; Reduce Motion keeps only the breathing.
struct InfraStage: View {
    let project: ProjectItem
    /// Seven nodes are legible in the stage; the rest are one click away in Services.
    static let limit = 7
    static let nodeSize = CGSize(width: 168, height: 58)
    @Environment(\.accessibilityReduceMotion) private var reduce

    struct Node: Identifiable {
        let id: Int
        let name: String
        let line: String
        let tone: Tone
        var point = CGPoint.zero
    }
    enum Tone { case ok, warn, bad, off }

    var nodes: [Node] {
        let live = project.live?.services ?? []
        let running = project.tag == .running || project.tag == .starting
        let all: [Node] =
            live.isEmpty
            ? (project.draft?.services ?? []).enumerated().map {
                Node(id: $0.offset, name: $0.element, line: "Not started", tone: .off)
            }
            : live.enumerated().map { i, s in
                let tone: Tone =
                    s.state == .exited ? .bad : s.state == .up ? (s.health == "unhealthy" ? .warn : .ok) : .off
                let line =
                    s.state == .up
                    ? "\(s.health == "unhealthy" ? "Not healthy" : "Up")\(s.memory == "–" ? "" : " · \(s.memory)")"
                    : (running || s.state == .exited ? Overview.serviceLine(s) : "Stopped")
                return Node(id: i, name: s.name, line: line, tone: tone)
            }
        return Array(all.prefix(Self.limit))
    }

    /// Depth of node i in a binary tree: 0 | 1 2 | 3 4 5 6.
    static func depth(_ i: Int) -> Int { Int(log2(Double(i + 1))) }
    static func parent(_ i: Int) -> Int { (i - 1) / 2 }

    /// Node centres inside `size`: one column per depth, the nodes of a column spread down it.
    static func layout(count: Int, in size: CGSize) -> [CGPoint] {
        guard count > 0 else { return [] }
        let cols = depth(count - 1) + 1
        let inset = nodeSize.width / 2 + Space.s6
        return (0..<count).map { i in
            let d = depth(i)
            let inCol = (0..<count).filter { depth($0) == d }
            let r = inCol.firstIndex(of: i) ?? 0
            // Columns sit a fixed gap apart around the centre, not stretched to the far edges.
            let gap = cols == 1 ? 0 : min((size.width - 2 * inset) / CGFloat(cols - 1), nodeSize.width + Space.s8 * 2)
            let x = size.width / 2 + (CGFloat(d) - CGFloat(cols - 1) / 2) * gap
            let y = size.height * (CGFloat(r) + 0.5) / CGFloat(inCol.count)
            return CGPoint(x: x, y: y)
        }
    }

    var body: some View {
        let list = nodes
        let total = project.live?.services.count ?? project.draft?.services.count ?? 0
        GeometryReader { g in
            let pts = Self.layout(count: list.count, in: CGSize(width: g.size.width, height: g.size.height - Space.s6))
            let running = project.tag == .running
            ZStack(alignment: .topLeading) {
                // No lines: the Core does not say how services connect, and a guessed tree would claim it does.
                ForEach(list) { n in
                    NodeView(node: n, beat: running).position(pts[n.id])
                }
                if total > list.count {
                    Text("+\(total - list.count) more in Services").foregroundStyle(GlassInk.secondary)
                        .padding(Space.s3).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Services of \(project.name)")
    }

    private struct NodeView: View {
        let node: Node
        let beat: Bool
        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Space.s2 - 2) {
                    coreShape(2).fill(colour).frame(width: 8, height: 8)
                        .coreBreathing(beat && node.tone == .ok)
                    Text(node.name).coreFont(size: MacTextSize.meta + 1, weight: .semibold).lineLimit(1)
                }
                Text(node.line).coreFont(size: MacTextSize.meta)
                    .foregroundStyle(node.tone == .bad ? GlassInk.redInk : GlassInk.secondary).lineLimit(2)
            }
            .padding(.horizontal, Space.s3 - 1).frame(
                width: InfraStage.nodeSize.width, height: InfraStage.nodeSize.height, alignment: .leading
            )
            .coreCard(GlassInk.card, radius: Radius.cardMac)
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .help("\(node.name): \(node.line)")
            .accessibilityElement(children: .combine)
        }
        private var colour: Color {
            switch node.tone {
            case .ok: GlassInk.green
            case .warn: GlassInk.amber
            case .bad: GlassInk.red
            case .off: GlassInk.secondary
            }
        }
    }
}
