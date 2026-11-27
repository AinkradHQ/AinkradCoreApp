import CoreUI
import SwiftUI

/// Right-click on a layer on the canvas: what Figma offers for it, written as the same edit ops the layers panel uses. The
/// canvas selected the layer under the pointer first, so the menu is about the selection.
struct CanvasLayerMenu: View {
    let editor: DesignEditor

    var body: some View {
        let ids = editor.selection
        let first = ids.first.flatMap { editor.layers[$0] }
        let one = ids.count == 1
        let hidden = first?.hidden == true
        let canParent = first?.parent.flatMap { editor.layers[$0] }.map { $0.type != "page" } ?? false
        let ro = editor.readOnly
        Button("Rename") { if let id = ids.first { editor.renaming = id } }.disabled(ro || !one)
        Button("Duplicate") { _ = editor.duplicate() }.disabled(ro)
        Divider()
        Button("Bring Forward") { if let id = ids.first { editor.step(id, up: true) } }.disabled(ro || !one)
        Button("Send Backward") { if let id = ids.first { editor.step(id, up: false) } }.disabled(ro || !one)
        Divider()
        Button(hidden ? "Show Layer" : "Hide Layer") { editor.setHidden(ids, !hidden) }.disabled(ro)
        Button("Select Parent") { editor.selectParent() }.disabled(!one || !canParent)
        Divider()
        Button("Delete", role: .destructive) { editor.deleteSelected() }.disabled(ro)
    }
}
