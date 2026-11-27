import CoreUI
import SwiftUI

/// The inspector's Prototype section: what a click on this layer does in Present — go to another screen (a top-level
/// frame), with or without a fade. Written as the layer's `link` prop (`{to, transition}`).
struct PrototypeBlock: View {
    let editor: DesignEditor
    let node: EditorNode

    /// Every top-level frame of every page, with a label that tells equal names apart (by page, then by number).
    private var screens: [(id: String, label: String)] {
        let pages = editor.layers.children(of: nil).filter { $0.type == "page" }
        let all = pages.flatMap { page in
            editor.layers.children(of: page.id).filter { ($0.type == "frame" || $0.type == "component") && $0.id != node.id }
                .map { (layer: $0, page: page) }
        }
        var seen: [String: Int] = [:]
        return all.map { e in
            var label = e.layer.title
            if pages.count > 1 { label += " · \(e.page.title)" }
            seen[label, default: 0] += 1
            if seen[label]! > 1 { label += " (\(seen[label]!))" }
            return (e.layer.id, label)
        }
    }
    private var link: DJSON? { node.props["link"] }
    private var targetLabel: String? { link?["to"]?.string.flatMap { to in screens.first { $0.id == to }?.label } }

    var body: some View {
        InspectorBlock("Prototype") {
            if link != nil {
                InspectorIcon(symbol: "minus", label: "Remove the link") { editor.set("link", nil) }
            }
        } content: {
            if screens.isEmpty {
                Text("Add another frame to link to it.").coreFont(size: MacTextSize.meta).foregroundStyle(
                    GlassInk.secondary)
            } else {
                // Targets are picked by their id (names repeat, and there can be several pages).
                let list = screens
                InlineMenu(
                    label: "On click", value: targetLabel ?? "nothing", choices: ["nothing"] + list.map(\.label)
                ) { pick in
                    guard let to = list.first(where: { $0.label == pick }) else { return editor.set("link", nil) }
                    editor.set(
                        "link",
                        .object(["to": .string(to.id), "transition": .string(link?["transition"]?.string ?? "fade")]))
                }
                if targetLabel != nil {
                    IconChoices(
                        choices: [("none", "bolt", "Instant"), ("fade", "circle.lefthalf.filled", "Fade")],
                        current: link?["transition"]?.string ?? "fade"
                    ) { t in
                        guard let to = link?["to"] else { return }
                        editor.set("link", .object(["to": to, "transition": .string(t)]))
                    }
                }
                Text("Click it in Present to go there.").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            }
        }
    }
}
