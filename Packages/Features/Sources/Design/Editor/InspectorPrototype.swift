import CoreUI
import SwiftUI

/// The inspector's Prototype section: what a click on this layer does in Present — go to another screen (a top-level
/// frame), with or without a fade. Written as the layer's `link` prop (`{to, transition}`).
struct PrototypeBlock: View {
    let editor: DesignEditor
    let node: EditorNode

    private var screens: [DesignLayer] {
        guard let page = editor.layers.children(of: nil).first else { return [] }
        return editor.layers.children(of: page.id).filter {
            ($0.type == "frame" || $0.type == "component") && $0.id != node.id
        }
    }
    private var link: DJSON? { node.props["link"] }
    private var target: DesignLayer? { link?["to"]?.string.flatMap { editor.layers[$0] } }

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
                InlineMenu(
                    label: "On click", value: target?.title ?? "nothing",
                    choices: ["nothing"] + screens.map(\.title)
                ) { pick in
                    guard let to = screens.first(where: { $0.title == pick }) else { return editor.set("link", nil) }
                    editor.set(
                        "link",
                        .object(["to": .string(to.id), "transition": .string(link?["transition"]?.string ?? "fade")]))
                }
                if target != nil {
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
