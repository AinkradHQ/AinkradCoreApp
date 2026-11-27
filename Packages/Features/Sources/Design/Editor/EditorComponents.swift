import CoreUI
import SwiftUI

extension DesignEditor {
    /// The components of this design, for the insert menu.
    var components: [DesignLayer] { layers.layers.filter { $0.type == "component" } }

    func createComponent() {
        guard !selection.isEmpty else { return notify("Select a frame to make it a component.") }
        guard backend?.createComponent() == true else {
            return notify("A page cannot become a component. Select a frame or layers.")
        }
        notice = nil
        reload()
    }

    func detachInstance() {
        guard selection.contains(where: { layers[$0]?.type == "instance" }) else {
            return notify("Select an instance to detach it.")
        }
        guard backend?.detachInstance() == true else {
            return notify("That instance cannot be detached. Its component may be gone.")
        }
        notice = nil
        reload()
    }

    /// Places an instance of `component` where the canvas is looking (inside the frame there, else on the page). The engine
    /// puts it inside whatever is at that point, which may be the component itself (an instance that repeats forever): then
    /// it is undone and placed beside the component instead.
    @discardableResult
    func insertInstance(_ component: DesignLayer) -> Bool {
        guard let b = backend, attached else { return false }
        let ref = "\(doc)/\(component.id)"
        guard b.insertInstance(ref, at: nil) else { return false }
        reload()
        if let id = selection.first, let p = layers[id]?.parent, layers.isInside(p, of: component.id) {
            b.undo()
            reload()
            guard let box = NodeBox(node(of: component.id)), let cam = b.camera(),
                layers[component.id]?.parent == currentPage?.id,
                b.insertInstance(
                    ref,
                    at: CGPoint(x: (box.maxX + 40) * cam.zoom + cam.pan.x, y: box.y * cam.zoom + cam.pan.y))
            else {
                notice = "Place the instance on the page, beside the component, not inside it."
                return false
            }
            reload()
        }
        notice = nil
        return true
    }
}

/// The Components menu next to Image in the canvas toolbar: this design's components, placed as instances.
struct ComponentsMenu: View {
    @Bindable var editor: DesignEditor

    var body: some View {
        Menu {
            let list = editor.components
            if list.isEmpty {
                Text("No components yet. Select a frame and press ⌥⌘K.")
            }
            ForEach(list.prefix(40)) { c in
                Button {
                    editor.insertInstance(c)
                } label: {
                    Label(c.title, systemImage: "diamond")
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "diamond").coreFont(size: MacTextSize.title).foregroundStyle(GlassInk.primary)
                Image(systemName: "chevron.down").coreFont(size: 9, weight: .semibold).foregroundStyle(
                    GlassInk.secondary)
            }
            .frame(height: MacSize.controlLg + Space.s1).padding(.horizontal, Space.s2)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .modifier(ToolHover())
        .help("Components: place an instance of one of this design's components")
        .accessibilityLabel("Components")
        .accessibilityIdentifier("design-components")
    }
}
