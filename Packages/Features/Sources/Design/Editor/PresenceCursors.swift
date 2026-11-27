import CoreUI
import SwiftUI

/// Someone on the canvas as the engine lists them (`de_presence_list`): a person or an AI session, and whether this
/// viewer follows them. Their cursors and selections are drawn on the canvas by the engine itself, in one colour each.
struct Collaborator: Identifiable, Equatable, Sendable {
    let id: String  // the `peer` id `de_follow` takes
    let label: String
    let isAI: Bool
    let following: Bool

    /// The colours the engine marks peers with, by the order they joined (`overlay.rs`, slot 1 first). The chip wears the
    /// colour of the cursor.
    static let palette: [UInt32] = [0x8B5CF6, 0x14B8A6, 0xF97316, 0xEC4899, 0x84CC16, 0x06B6D4]

    static func color(at index: Int) -> Color {
        let v = palette[(index + 1) % palette.count]
        return Color(
            red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// `[{"peer","label","kind","following"}]`. The peer is another device's text: bad entries are dropped, the label is cut.
    static func decode(_ data: Data?) -> [Collaborator] {
        struct Row: Decodable {
            var peer: String?
            var label: String?
            var kind: String?
            var following: Bool?
        }
        guard let data, let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [] }
        return rows.prefix(64).compactMap { r in
            guard let id = r.peer, !id.isEmpty, id.count <= 128 else { return nil }
            let ai = r.kind == "ai"
            let label = String((r.label ?? "").filter { !$0.isNewline }.prefix(40))
            return Collaborator(
                id: id, label: label.isEmpty ? (ai ? "An AI session" : "Someone") : label, isAI: ai,
                following: r.following == true)
        }
    }

    var words: String {
        let who = isAI ? "\(label), an AI session" : label
        return following ? "Following \(who). Pan or zoom to stop." : "Follow \(who)'s view"
    }
}

/// The header's people: one chip per person on the canvas, in the colour of their cursor; a click follows their view, a
/// second click (or panning) stops.
struct CollaboratorChips: View {
    let people: [Collaborator]
    let follow: (Collaborator) -> Void

    var body: some View {
        HStack(spacing: Space.s1) {
            ForEach(Array(people.prefix(5).enumerated()), id: \.element.id) { i, p in
                Button {
                    follow(p)
                } label: {
                    HStack(spacing: Space.s1) {
                        coreShape(2).fill(Collaborator.color(at: i)).frame(width: 8, height: 8)
                        Text(p.label).lineLimit(1)
                        if p.following { Image(systemName: "eye").accessibilityHidden(true) }
                    }
                    .coreFont(size: MacTextSize.meta, weight: .medium)
                    .padding(.horizontal, Space.s2)
                    .frame(height: MacSize.chip)
                    .background(
                        p.following ? Collaborator.color(at: i).opacity(0.28) : GlassInk.well,
                        in: coreShape(Radius.chip)
                    )
                    .contentShape(coreShape(Radius.chip))
                }
                .buttonStyle(.plain)
                .help(p.words)
                .accessibilityLabel(p.words)
                .accessibilityAddTraits(p.following ? .isSelected : [])
            }
            if people.count > 5 { Text("+\(people.count - 5)").foregroundStyle(GlassInk.secondary) }
        }
        .animation(Motion.out(Motion.hover), value: people)
    }
}

extension DesignEditor {
    /// Follows a person's view, or stops when already following them.
    func follow(_ c: Collaborator) {
        backend?.follow(c.following ? "" : c.id)
        reload()
    }
}
